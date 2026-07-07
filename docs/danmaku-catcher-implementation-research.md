# 弹幕捕手实现方式调研

调研对象：桌面端「弹幕捕手」当前打开的 Electron 应用。

调研时间：2026-07-06。

调研范围：

- 添加直播间/直播店铺
- 打印机连接
- 热敏标签纸与打印模板设置

注意：当前窗口实际 URL 带有 `userInfo` 查询参数，里面包含登录 token、手机号等敏感信息，本文不记录这些参数。

## 1. 应用架构结论

弹幕捕手不是一个纯本地客户端，也不是一个纯网页。它是「Electron 本地壳 + 远程 SaaS 业务页面 + 本地打印/平台授权能力」的组合。

### 1.1 本地 Electron 壳

安装路径：

- `/Applications/弹幕捕手.app`

主包：

- `/Applications/弹幕捕手.app/Contents/Resources/app.asar`

应用信息：

- package name：`@danmaku-catcher/electron`
- Electron 客户端版本：`1.0.9`
- main：`dist/main/index.js`

用户数据目录：

- `/Users/zcc/Library/Application Support/@danmaku-catcher/electron`

本地壳负责：

- 创建主窗口并加载远程页面。
- 通过 preload 暴露 `window.danmakuAPI`。
- 枚举系统打印机。
- 创建隐藏打印窗口并调用系统打印。
- 保存本地打印参数。
- 打开平台登录窗口并采集平台 Cookie。
- 代理网络请求、WebSocket、iframe view、日志、用户 session 等本地能力。

### 1.2 远程业务页面

桌面端加载的业务入口：

- `https://saas.fhd001.com/dmbs/electron/index.html`
- 当前页面路由：`#/danmakuCatcher`

远程业务页面稳定版资源：

- `stable/manifest.js`
- `stable/js/index.0b244875.js`
- `stable/js/runtime~index.2b003208.js`
- `stable/js/vendor.64084aef.js`
- 异步 chunk：`143.27ac037b.js`、`882.5c8f986b.js`、`common.3786d1a5.js`

远程业务页面负责：

- 页面 UI：扣数打印、直播间下拉、打印模板、打印机选择、规则配置、弹幕列表等。
- 直播间/店铺绑定关系。
- 模板列表与模板编辑。
- 自动打印业务规则。
- 调用 `window.danmakuAPI` 完成本地打印、平台连接、WebSocket 等能力。

### 1.3 API 基础地址

远程页面的业务 API base：

- `https://saasapi.fhd001.com/live`

页面请求里 `/dmbs/` 会被重写到上述 base，且请求会带 token。

主要接口：

- `/dmbs/api/account/queryUserShopBindsV2`
- `/dmbs/api/account/queryLiveUserAccount`
- `/dmbs/api/account/queryUserPlatformAccounts`
- `/dmbs/api/live/liveShopConnectStatus`
- `/dmbs/api/live/liveShopData`
- `/dmbs/api/live/liveBroadcastCommentsOpenV2`
- `/dmbs/api/live/liveBroadcastCommentsClose`
- `/dmbs/api/live/queryLiveBroadcastCommentsPolicy`
- `/dmbs/api/live/liveBroadcastCommentsFilterPolicy`
- `/dmbs/api/live/broadcastCommentsHandlerPolicyCursor`
- `/dmbs/api/template/getLiveBroadcastCommentTemplates.do`
- `/dmbs/api/template/getLiveBroadcastCommentTemplate.do`
- `/dmbs/api/template/saveLiveBroadcastCommentTemplate.do`
- `/dmbs/api/template/saveDefaultLiveBroadcastCommentTemplate.do`
- `/dmbs/api/template/deleteLiveBroadcastCommentTemplate.do`

Electron 主进程额外会调用：

- `https://saasapi.fhd001.com/live/api/workbench/checkV2`
- `https://saasapi.fhd001.com/live/api/account/saveMerchantShopBackendInfo`

## 2. 添加直播间实现方式

### 2.1 页面层不是手填房间号，而是添加直播店铺

当前页面上的“直播间”下拉数据来自用户绑定的直播店铺。添加流程本质上是：

1. 用户点击添加直播店铺/直播间。
2. 页面弹出平台选择弹窗。
3. 用户选择抖音、抖音达人、小红书、千牛、TikTok、虾皮、视频号、快手等平台。
4. Electron 打开对应平台的登录/工作台窗口。
5. 用户在平台工作台完成登录。
6. 客户端根据 URL 匹配规则判断登录是否完成。
7. Electron 采集平台 Cookie/店铺信息。
8. Cookie 上传或保存到后端。
9. 前端刷新直播间列表。

前端弹窗文案：

- 标题：`选择平台，在平台登录想要添加的直播间账号`
- 底部提示：`连接不上直播间请确保已登录平台工作台，如仍有问题请联系客服`

前端点击平台卡片后调用：

- `connectPlatformWithMessage(name, platformId)`
- 内部最终调用 `window.danmakuAPI.platform.connect(platformId, shopId?, options?)`

成功后前端执行：

- `refreshLiveShops()`
- 重置/刷新相关扣数状态
- 关闭弹窗并回填成功的 `shopId`

### 2.2 平台运行时配置由远程页面下发

远程页面启动后会向 Electron 注册平台配置：

```js
window.danmakuAPI.platformRuntime.register({
  schemaVersion: 1,
  revision: "app-desktop-platform-registry-v1",
  platforms: ...
})
```

每个平台配置必须包含：

- `name`
- `loginUrl`
- `cookieDomain`
- `contentScriptMatch`
- `pageHandlerMatch`

已发现的平台配置：

| 平台 ID | 业务 key | 添加弹窗展示 | name | loginUrl |
| --- | --- | --- | --- | --- |
| `1` | `fxg` | 是 | `抖音工作台` | `https://fxg.jinritemai.com/login/common` |
| `4` | `fxg_kol` | 是 | `抖音达人工作台` | `https://buyin.jinritemai.com/mpa/account/login` |
| `2` | `xhs` | 是 | `小红书工作台` | `https://customer.xiaohongshu.com/login?service=https://ark.xiaohongshu.com/app-system/home` |
| `3` | `tb` | 是 | `千牛工作台` | `https://loginmyseller.taobao.com/?from=&f=top&style=&sub=true&redirect_url=https%3A%2F%2Fmyseller.taobao.com%2Fhome.htm%2Flive-dashboard-qn%2F` |
| `5` | `tiktok` | 是，要求客户端版本不低于 `1.20.0` | `Tiktok工作台` | `https://seller.tiktokshopglobalselling.com/account/login` |
| `6` | `shopee` | 是 | `虾皮工作台` | `https://seller.shopee.cn/account/signin` |
| `7` | `ec` | 是 | `视频号工作台` | `https://channels.weixin.qq.com/login.html` |
| `8` | `ks` | 是 | `快手工作台` | `https://login.kwaixiaodian.com/?biz=zone&redirect_url=https%3A%2F%2Fs.kwaixiaodian.com%2Fzone%2Forder%2Flist` |
| `99` | `wx_store` | 否，配置存在但当前添加弹窗过滤掉 | `微信小店工作台` | `https://store.weixin.qq.com/shop?redirect_url=%2Forder%2Flist` |

补充核对：本地 Chrome 扩展包 `/Users/zcc/Documents/git-workspace-zcc/dmbs/danmaku-catcher-1.24.0-chrome/reverse-engineered-danmaku-catcher/src/shared/platforms.js` 中，`fxg` 的 `loginUrl` 是 `https://fxg.jinritemai.com/`，桌面端研究记录为 `https://fxg.jinritemai.com/login/common`。迅拣默认使用显式登录页 `/login/common`，保留工作台首页作为后续兼容回退。

对应的 Cookie 域名、页面匹配和补充 Cookie URL：

| 平台 | cookieDomain | contentScriptMatch | pageHandlerMatch | cookieUrls/allowedDomains |
| --- | --- | --- | --- | --- |
| 抖音工作台 | `jinritemai.com` | `*://fxg.jinritemai.com/*` | `*://fxg.jinritemai.com/ffa/mshop/homepage/index` | 无 |
| 抖音达人工作台 | `jinritemai.com` | `*://buyin.jinritemai.com/*` | `*://buyin.jinritemai.com/dashboard*` | 无 |
| 小红书工作台 | `xiaohongshu.com` | `*://ark.xiaohongshu.com/*` | `*://ark.xiaohongshu.com/app-system/home` | 无 |
| 千牛工作台 | `taobao.com` | `*://myseller.taobao.com/*` | `*://myseller.taobao.com/home.htm/live-dashboard-qn/` | 无 |
| TikTok 工作台 | `tiktokshopglobalselling.com` | `*://seller.us.tiktokshopglobalselling.com/*` | `*://seller.us.tiktokshopglobalselling.com/homepage*` | 无 |
| 虾皮工作台 | `shopee.cn` | `*://seller.shopee.cn/?cnsc_shop_id=*` | `*://seller.shopee.cn/*` | 无 |
| 视频号工作台 | `weixin.qq.com` | `*://channels.weixin.qq.com/platform/*` | `*://channels.weixin.qq.com/platform/*` | 无 |
| 快手工作台 | `kwaixiaodian.com` | `*://*.kwaixiaodian.com/*` | `*://s.kwaixiaodian.com/zone/order/list*` | `cookieUrls = ["https://s.kwaixiaodian.com/zone/order/list"]` |
| 微信小店工作台 | `weixin.qq.com` | `*://store.weixin.qq.com/*` | `*://store.weixin.qq.com/shop/order/list*` | `cookieUrls = ["https://store.weixin.qq.com/shop/order/list"]`，`allowedDomains = ["store.weixin.qq.com"]` |

这个设计的关键点是：平台规则不写死在本地客户端版本里，而是由远程业务包下发。客户端只负责执行“注册表”。

补充说明：微信小店虽然在平台注册表里存在，也属于本地授权支持平台，但当前“选择平台，在平台登录想要添加的直播间账号”弹窗会执行 `Number(platformId) !== WX_STORE` 过滤，所以这个入口不会展示微信小店卡片。

### 2.3 Electron 平台连接流程

前端调用 `window.danmakuAPI.platform.connect(...)` 后，preload 会转发到主进程 IPC：

- IPC channel：`platform:connect`
- 主进程入口：`qr.connect(platformId, requesterWebContentsId, userAccount, shopId, options)`

主进程连接逻辑：

1. 根据 `platformId` 从 runtime registry 取平台配置。
2. 如果不是 `localAuth`，要求当前用户已有登录 token。
3. 防止同一窗口同一平台重复连接。
4. 生成 `requestId`，记录到 `activeRequests`。
5. 打开或复用平台授权窗口。
6. 给平台窗口绑定导航监听。
7. 当 URL 同时命中 `contentScriptMatch` 和 `pageHandlerMatch`，开始延迟采集 Cookie。
8. 采集成功后回调前端 `platform:connect-result`。

前端等待结果的超时时间：

- 120 秒

主进程连接请求超时时间：

- 300 秒

### 2.4 平台授权窗口的 session 设计

首次连接使用临时 session：

```text
platform-temp-{platformId}-{timestamp}-{random}
```

已有店铺 session 使用持久 session：

```text
persist:platform-{platformId}-{shopId}
```

窗口参数：

- `BrowserWindow` 尺寸：`1440 x 900`
- `contextIsolation: true`
- `nodeIntegration: false`
- `sandbox: true`
- `webSecurity: true`
- 覆盖 User-Agent 为桌面 Chrome UA

窗口创建后直接执行：

```text
BrowserWindow.loadURL(platformConfig.loginUrl)
```

所以“添加直播间”打开的登录页就是上表的 `loginUrl`。主进程还会给授权窗口加域名白名单：

1. `cookieDomain`
2. `loginUrl` 的 hostname
3. `loginUrl` hostname 的二级根域名
4. 平台额外配置的 `allowedDomains`

授权窗口里如果发生非 HTTP(S) 跳转会被阻止；如果跳到不在白名单内的域名，会阻止在授权窗口内继续打开，并改用系统外部浏览器打开。

连接成功后，如果是临时 session，会迁移 Cookie 到持久 session：

```text
platform-temp-* -> persist:platform-{platformId}-{shopId}
```

这样下次同一个平台店铺可以复用登录态。

### 2.5 Cookie 采集与上传

主进程采集 Cookie 的策略：

1. 先按 `loginUrl` 取 Cookie。
2. 再按 `cookieDomain` 取 Cookie。
3. 再按 `.${cookieDomain}` 取 Cookie。
4. 部分平台还配置了 `cookieUrls`，会按 URL 补充采集。

采集时使用 `name=value@domain` 去重，最终上传/保存时再组装成：

```text
name1=value1;name2=value2
```

注意：文档只记录实现方式，不记录任何真实 Cookie 值。

#### 2.5.1 本地保存 Cookie 的位置和生命周期

弹幕捕手没有把平台 Cookie 写到自己的普通 JSON 配置文件里，而是使用 Electron/Chromium session 管理：

1. 首次添加平台时，创建临时 session：`platform-temp-{platformId}-{timestamp}-{random}`。
2. 用户完成平台登录，URL 命中 `contentScriptMatch + pageHandlerMatch` 后，主进程延迟约 `2500ms` 开始采集 Cookie。
3. 后端校验成功并返回 `shopId` 后，把临时 session 的所有 Cookie 迁移到店铺持久 session：`persist:platform-{platformId}-{shopId}`。
4. 迁移时会先清空目标持久 session 的 storage/cache，再逐条写入 Cookie，保留 `name/value/domain/path/secure/httpOnly/expirationDate`。
5. 迁移完成后清空临时 session 的 storage/cache。
6. 然后把 `persist:platform-{platformId}-{shopId}` 里的 Cookie 再同步一份到当前弹幕捕手用户主 session，便于后续页面或接口复用登录态。

这个设计意味着：同一个平台店铺的登录态以 `platformId + shopId` 为隔离维度保存。下次连接同一个店铺时，可以复用 `persist:platform-{platformId}-{shopId}`。

#### 2.5.2 非 localAuth：加密上传到 `checkV2`

非 localAuth 流程：

- 组装 `{ platform, key: cookieString, shops? }`
- AES 加密数据
- RSA 加密 AES key
- 上传到 `https://saasapi.fhd001.com/live/api/workbench/checkV2`
- 后端返回 `shopId/shopName/success/error`

请求体是 `application/x-www-form-urlencoded`：

```text
key={RSA加密后的AESKey}:{AES加密后的JSON}&token={当前弹幕捕手用户token}
```

这里的 `key` 不是明文 Cookie，而是加密后的载荷。载荷明文结构在加密前大致是：

```json
{
  "platform": 1,
  "key": "name1=value1;name2=value2",
  "shops": []
}
```

`shops` 不是所有平台都有。已发现 TikTok 会在上传前额外调用 TikTok 店铺信息接口：

```text
GET https://seller.us.tiktokshopglobalselling.com/api/v1/shop_im/multi_shop/user/get_info_list
```

它会把返回的店铺映射为 `ShopId/ShopName/ShopRegion` 后随 Cookie 一起上传，方便后端识别多店铺。

#### 2.5.3 localAuth：本地解析店铺并保存商家后台 Cookie

localAuth 流程：

- 当前本地支持集合：抖音工作台、微信小店工作台
- 前端可传 `options.localAuth`
- 主进程不走 `checkV2` 上传校验，而是在本地用平台 Cookie 解析店铺信息
- 若包含 `livePlatform/liveShopId/platformShopId`，额外保存商家后台 Cookie：

```text
POST https://saasapi.fhd001.com/live/api/account/saveMerchantShopBackendInfo
```

参数：

- `livePlatform`
- `liveShopId`
- `platformShopId`
- `cookie`
- `token`

本地解析店铺信息的方式：

| 平台 | 解析方式 | 取值 |
| --- | --- | --- |
| 抖音工作台 | 带当前 session Cookie 请求 `https://pigeon.jinritemai.com/backstage/currentuser?...` | 从响应 `data.ShopId` 和 `data.ShopName` 解析 |
| 微信小店工作台 | 带当前 session Cookie 请求 `https://store.weixin.qq.com/shop-faas/mmecnodelogin/session/getShopSwitchList?token=&lang=zh_CN` | 取 `list[0].appid` 作为 `shopId`，`list[0].nickname` 作为 `shopName` |

保存商家后台 Cookie 时，请求体是 `application/x-www-form-urlencoded`，形态如下：

```text
livePlatform={直播平台}&liveShopId={直播店铺ID}&platformShopId={平台店铺ID}&cookie={URL编码后的Cookie串}&token={当前弹幕捕手用户token}
```

这里的 `cookie` 是从 `persist:platform-{platformId}-{platformShopId}` 重新按 `loginUrl/cookieDomain/.cookieDomain/cookieUrls` 汇总出来的 Cookie 串。

### 2.6 直播间列表如何生成

前端全局 store 初始化时会拉直播店铺绑定关系：

```text
POST /dmbs/api/account/queryUserShopBindsV2
```

返回数据字段会被映射为页面的直播间列表：

- `livePlatform` -> `platform`
- `liveShopId` -> `shopId`
- `liveShopName` -> `shopName`

然后逐个调用连接状态接口：

```text
POST /dmbs/api/live/liveShopConnectStatus
```

如果接口返回有数据，页面上会显示已连接。

### 2.7 自动打印启动时如何连接直播间弹幕

用户点击“开启自动打印”后，并不是再走添加直播间流程，而是使用已绑定店铺数据连接弹幕。

流程：

1. 通过 `liveShopData` 拿店铺 Cookie：

```text
POST /dmbs/api/live/liveShopData
```

2. 由平台 adapter 根据 Cookie 和店铺信息获取直播房间号。
3. 成功后连接平台弹幕 WebSocket。
4. 收到弹幕后进入扣数匹配、去重、防多打、打印队列。

失败文案可以看出链路：

- `店铺连接已失效，请重新连接店铺后重试`
- `获取直播房间号失败，请确认店铺正在直播中`
- `WebSocket 连接超时，请检查网络连接或重试`

补充结论：

- `common.3786d1a5.js` 里确实有通用 `websocket-core`，抽象了 `liveShopData -> adapter.getRoomId -> adapter.buildUrl -> adapter.decodeMessage`。
- 后续重新核对稳定业务包后，结论修正为：弹幕捕手的小红书链路以 ark 工作台 Cookie 作为登录态，并存在客户端侧继续解析直播信息和拉取弹幕的逻辑。
- 因此迅拣可以复刻的部分不止是授权采集，还应补齐本机小红书 adapter：从 `access-token-ark.xiaohongshu.com=customer.ark.AT-...` 等工作台 Cookie 派生直播信息，再连接或轮询小红书弹幕源。
- 当前迅拣客户端仍不能直接复用 `xhs_live` 的 redlive 登录态方案；后续应围绕 ark 工作台 Cookie 实现等价本机 adapter。

## 3. 打印机连接实现方式

### 3.1 不是直连 USB/蓝牙，而是使用系统打印机

弹幕捕手的打印机连接不是直接打开 USB、串口、蓝牙或 ESC/POS/TSPL socket。

它使用 Electron/Chromium 的系统打印能力：

```js
webContents.getPrintersAsync()
webContents.print(options, callback)
```

所以页面上的“已连接”本质含义是：

- 当前选择的打印机存在于操作系统打印机列表。
- 打印前可通过系统打印状态做简单校验。
- 真正打印由系统打印队列完成。

这解释了为什么页面能选择 `Deli_M1022W` 这类系统打印机，也能识别虚拟打印机并提示。

### 3.2 前端打印机选择组件

前端打印机选择组件逻辑：

1. 调用 `window.danmakuAPI.print.getPrinters()`。
2. 将返回项映射成 `{ name, type: "local" }`。
3. 查找 `isDefault` 打印机作为默认打印机。
4. 如果当前没有选择值，优先自动选择默认打印机。
5. 如果没有打印机，展示 `暂无可用打印机（点我刷新）`，点击会重新拉取。

页面组件 class：

- `.printer-select`

UI 文案：

- `请选择打印机`
- `本地打印机`
- `暂无可用打印机（点我刷新）`

### 3.3 Electron 侧打印机枚举

preload 暴露：

```js
window.danmakuAPI.print.getPrinters()
```

主进程实现：

```js
const win = await getPrintWindow()
return await win.webContents.getPrintersAsync()
```

返回的是 Electron 的系统打印机对象列表，通常包含：

- `name`
- `displayName`
- `description`
- `status`
- `isDefault`
- 其他系统打印属性

### 3.4 打印任务如何执行

前端提交打印：

```js
window.danmakuAPI.print.print(payload)
```

测试打印 payload 的核心字段：

```js
{
  printer: selectedPrinter.name,
  silent: true,
  copies: 1,
  rePrintAble: 1,
  document: preparePrintDocument(...)
}
```

主进程打印流程：

1. 取 `payload.printer`，如果没有则取本地存储的 `defaultPrinter`。
2. 如果仍没有，则从系统打印机列表里找 `isDefault`。
3. 用 `getPrintersAsync()` 校验打印机存在。
4. 按设置里的 `printerStatusCheckRetries` 和 `printerStatusCheckInterval` 检查打印机状态。
5. 生成或接收 HTML 打印内容。
6. 发送 HTML 到隐藏打印窗口。
7. 隐藏打印窗口加载内容、等待图片、执行自适应字号。
8. 隐藏窗口发回 `print-content-loaded`。
9. 主进程调用 `webContents.print(options)`。
10. 写入/更新打印日志。

### 3.5 打印任务是串行队列

主进程内部有打印任务队列：

- 新任务 push 到队列。
- 如果已有任务执行中，新任务等待。
- 当前任务结束后继续取下一个。

这样可以避免多条弹幕同时扣中时并发调用系统打印，导致热敏机丢单、乱序或状态异常。

### 3.6 打印日志

本地会创建 `print_logs` 表保存打印记录。

关键字段：

- `printer`
- `templateId`
- `data`
- `pageNum`
- `status`
- `rePrintAble`
- `errorMessage`
- `printId`

状态：

- `pending`
- `success`
- `failed`

前端也有重打接口：

- `window.danmakuAPI.print.getPrintLogs(...)`
- `window.danmakuAPI.print.rePrint(...)`
- `window.danmakuAPI.print.clearPrintLogs()`

### 3.7 系统打印机设置入口

菜单栏和托盘菜单里有本地打印设置入口：

- 打印设置
- 打印渲染窗口
- 重置打印缓存
- 打印机列表
- 打印机队列
- macOS 下有 CUPS Web 界面、AppleScript 导航等入口

这说明它依赖系统打印子系统调试打印机，而不是自己实现设备驱动。

## 4. 热敏标签纸和打印模板实现方式

### 4.1 标签纸尺寸主要由“打印模板”决定

页面里的“打印模板/设置模板”是业务模板系统，里面存储热敏标签纸的尺寸、字段、坐标、字体和边距。

模板接口：

```text
POST /dmbs/api/template/getLiveBroadcastCommentTemplates.do
POST /dmbs/api/template/getLiveBroadcastCommentTemplate.do
POST /dmbs/api/template/saveLiveBroadcastCommentTemplate.do
POST /dmbs/api/template/saveDefaultLiveBroadcastCommentTemplate.do
POST /dmbs/api/template/deleteLiveBroadcastCommentTemplate.do
```

模板核心字段：

- `id`
- `name`
- `size`，例如 `50x40`
- `margin`，例如 `0x0`
- `attribute`，JSON 字符串
- `updateTime`

`attribute` 中的关键结构：

```json
{
  "header": {
    "width": 48,
    "height": 40,
    "style": "overflow:hidden;",
    "attrs": [
      {
        "name": "昵称",
        "code": "nickName",
        "type": "text",
        "top": 8.831,
        "left": 1.794,
        "width": 48.206,
        "height": 5,
        "style": "fontSize:14;fontFamily:黑体;fontWeight:bold;align:left",
        "prefix": "昵称",
        "showPrefix": true
      }
    ]
  },
  "cargoPaddingH": 0
}
```

已看到的默认标签模板名称包括：

- `标签纸50x30`
- `标签纸40x30`
- `标签纸60x40`
- `标签纸50x40`
- `标签纸76x130`
- 以及多种 48x70、38x60、74x130 等变体

### 4.2 前端如何把模板转成 HTML

如果当前客户端支持 HTML 打印文档：

```js
window.danmakuAPI.print.supportsHtmlDocument() === true
```

前端会直接把模板渲染成 HTML：

```js
{
  html,
  pageSize: { width: template.size.width, height: template.size.height },
  paddingH
}
```

生成规则：

1. 解析模板 `attribute.header`。
2. 解析 `size` 为 `{ width, height }`，单位是 mm。
3. 解析 `margin` 为 `{ top, left, bottom, right }`。
4. 外层容器：

```css
position: relative;
width: {template.width}mm;
height: {template.height}mm;
overflow: hidden;
```

5. 每个字段生成绝对定位的 `<div>`：

```css
position: absolute;
top: {field.top + margin.top}mm;
left: {field.left + margin.left}mm;
width: {field.width}mm;
height: {field.height}mm;
```

6. text 字段用 `data[code]` 填值。
7. image 字段生成 `<img>`。
8. custom 字段优先使用 `data[code]`，否则使用模板固定值。
9. 超出处理：
   - `wrap`：允许换行。
   - 非 wrap：`white-space: nowrap; overflow: hidden;`
   - `autoFontSize`：额外加 `data-text-overflow="autoFontSize"`。
10. `@page` 设置：

```css
@page {
  border: 0;
  padding: 0cm;
  margin: 0cm;
  size: {width}mm {height}mm portrait;
}
```

如果客户端不支持 HTML 文档，前端会回退：

```js
{
  templateId: Number(template.id),
  templateUpdateTime: template.updateTime,
  data,
  skipFieldCodes
}
```

此时主进程再通过模板接口拉模板并渲染。

### 4.3 隐藏打印窗口二次处理 HTML

Electron 包内有本地打印窗口：

- `dist/resources/print.html`

它监听：

- `load-print-content`
- `clear-print-content`

收到 HTML 后：

1. 写入 `#print-content.innerHTML`。
2. 等待所有图片加载完成或失败。
3. 执行 `applyAutoFontSize(printContent)`。
4. 发回 `print-content-loaded`。

`applyAutoFontSize` 逻辑：

- 查找 `[data-text-overflow="autoFontSize"]`。
- 如果 `scrollWidth > clientWidth`，每次减少 `0.5px` 字号。
- 最小字号约等于 `3pt`。
- 如果字段有前缀 `<span class="tpl-prefix">`，前缀字号按比例同步缩小。
- 如果外层到底后仍溢出，再单独缩前缀。

这对热敏标签很重要：昵称、扣号、编号等字段可能过长，直接裁掉会影响拣货。

### 4.4 本地打印参数文件

本地打印参数文件：

```text
/Users/zcc/Library/Application Support/@danmaku-catcher/electron/print-settings.json
```

当前设置：

```json
{
  "silent": true,
  "printBackground": true,
  "color": true,
  "landscape": false,
  "scaleFactor": 100,
  "copies": 1,
  "pagesPerSheet": 1,
  "collate": false,
  "dpi": {
    "horizontal": 203,
    "vertical": 203
  },
  "margins": {
    "marginType": "template",
    "top": 0,
    "bottom": 0,
    "right": 0,
    "left": 0
  },
  "pageSize": {
    "width": 80,
    "height": 200
  },
  "verboseLogging": false,
  "printerStatusCheckRetries": 3,
  "printerStatusCheckInterval": 100
}
```

默认设置也基本一致：

- 静默打印：开启
- 打印背景：开启
- 彩色打印：开启
- 横向打印：关闭
- 缩放：100
- DPI：203 x 203
- 边距类型：`template`
- 默认 pageSize：`80 x 200`
- 打印机状态检测重试：3 次
- 检测间隔：100ms

### 4.5 “打印设置”窗口

菜单栏/托盘里的“打印设置”打开的是本地 HTML：

```text
dist/resources/print-settings.html
```

窗口参数：

- `width: 400`
- `height: 600`
- `nodeIntegration: true`
- `contextIsolation: false`

设置项：

- 静默打印
- 打印背景
- 彩色打印
- 横向打印
- 详细日志
- 状态检测重试次数
- 状态检测间隔
- 缩放比例
- DPI
- 边距类型
  - 无
  - 默认
  - 打印区域
  - 自定义
  - 使用模板配置
- 自定义上下左右边距，单位 mm
- 每页纸张数
- 分页/逐份打印

保存 IPC：

```text
print:settings:save
```

加载 IPC：

```text
print:settings:load
```

恢复默认 IPC：

```text
print:settings:reset
```

打开设置目录 IPC：

```text
print:settings:openDir
```

细节：

- 设置页表单保存时构造了 `pageSize: { width: 80, height: 200 }`。
- 主进程保存设置时会删除传入的 `pageSize` 和 `copies`。
- 因此实际打印的纸张尺寸主要来自当前模板/打印任务传入的 `document.pageSize`。
- reset 默认值仍会写入默认 `pageSize`。

### 4.6 主进程传给 Electron 的打印参数

最终调用：

```js
printWindow.webContents.print(printOptions, callback)
```

核心 printOptions：

```js
{
  silent,
  printBackground,
  deviceName: printerName,
  color,
  margins,
  landscape,
  scaleFactor,
  pagesPerSheet,
  collate,
  copies,
  dpi,
  pageSize
}
```

`pageSize` 处理：

- 前端 HTML 文档传入 `{ width, height }`，单位 mm。
- 主进程转换为 `{ width: 1000 * mmWidth, height: 1000 * mmHeight }`。
- Electron 自定义纸张尺寸使用微米级数值。

`margins` 处理：

- 如果设置是 `template`：
  - 优先使用打印任务传入的 `margins`。
  - 否则用模板的 `paddingH` 算左边距。
- 如果设置是 `custom`：
  - 把 mm 转换为像素：`96 * mm / 25.4`。
- 其他类型直接传 Electron。

## 5. 可借鉴到 fast-sort-client 的实现建议

### 5.1 添加直播间

建议采用“直播店铺绑定 + 平台授权窗口 + 后端保存 Cookie”的模式，而不是要求用户手工输入直播房间号。

推荐结构：

- 前端维护 `liveShop` 列表。
- 后端维护用户与直播店铺绑定关系。
- 桌面客户端提供 `platform.connect()` 能力。
- 平台配置从服务端下发，包含登录 URL、Cookie 域名、成功 URL 匹配规则。
- 授权窗口使用独立 session partition，避免污染主窗口登录态。
- 成功后把 Cookie/店铺信息交给后端保存。
- 自动打印启动时再用 `liveShopData` 获取 Cookie 并连接弹幕。

关键收益：

- 用户不用理解房间号。
- 平台登录态可复用。
- 平台规则可灰度/远程更新。
- 支持多个平台统一接入。

### 5.2 打印机连接

建议优先复用系统打印机，而不是第一阶段就做 USB/蓝牙/ESC 指令直连。

推荐结构：

- Electron/原生层：枚举系统打印机。
- 前端：打印机下拉 + 自动选默认打印机 + 刷新按钮。
- 打印前：校验打印机是否仍存在。
- 打印任务：串行队列。
- 打印内容：HTML 模板。
- 打印执行：隐藏窗口 + 系统 `print()`。
- 打印结果：记录本地日志，可重打。

这种方案对 Windows/Mac 更稳，也更容易兼容不同热敏标签机。

### 5.3 热敏标签纸设置

建议把“标签纸尺寸”放到业务模板，而不是只放到本地打印机设置。

推荐模型：

```ts
type LabelTemplate = {
  id: string;
  name: string;
  size: `${number}x${number}`; // mm
  margin: `${number}x${number}`; // left x top
  attribute: {
    header: {
      width: number;
      height: number;
      style: string;
      attrs: TemplateField[];
    };
    cargoPaddingH?: number;
  };
};
```

字段建议：

```ts
type TemplateField = {
  code: string;
  name?: string;
  type: "text" | "image" | "custom";
  top: number;
  left: number;
  width: number;
  height: number;
  style?: string;
  prefix?: string;
  prefixStyle?: string;
  showPrefix?: boolean;
  textOverflow?: "wrap" | "hidden" | "autoFontSize";
};
```

本地打印设置只保存通用参数：

- silent
- printBackground
- dpi
- margins mode
- scaleFactor
- status check retry
- verbose logging

具体标签纸尺寸应由模板控制：

- `50x30`
- `40x30`
- `60x40`
- `50x40`
- `76x130`
- 自定义尺寸

## 6. 证据索引

本地 Electron 代码是从 `app.asar` 解包并格式化后查看，临时路径如下：

- `/tmp/danmaku-catcher-readable/main.js`
- `/tmp/danmaku-catcher-readable/preload.js`
- `/tmp/danmaku-catcher-asar/dist/resources/print.html`
- `/tmp/danmaku-catcher-asar/dist/resources/print-settings.html`

远程业务代码下载并格式化到：

- `/tmp/dmbushou-remote/bootstrap.pretty.js`
- `/tmp/dmbushou-remote/saas-index.pretty.js`
- `/tmp/dmbushou-remote/143.pretty.js`
- `/tmp/dmbushou-remote/common.pretty.js`

关键位置：

| 主题 | 文件 | 行号 |
| --- | --- | --- |
| Electron 入口远程 URL/API base | `/tmp/danmaku-catcher-readable/main.js` | 35321-35332 |
| preload 暴露 `platform`/`print` API | `/tmp/danmaku-catcher-readable/preload.js` | 230-346 |
| 平台枚举和业务 key | `/tmp/dmbushou-remote/saas-index.pretty.js` | 3104-3131 |
| 远程平台配置表 | `/tmp/dmbushou-remote/143.pretty.js` | 9-82 |
| 平台配置注册到 Electron | `/tmp/dmbushou-remote/143.pretty.js` | 4535-4573 |
| 添加直播店铺弹窗和微信小店过滤 | `/tmp/dmbushou-remote/common.pretty.js` | 4472-4527 |
| 前端调用平台连接 | `/tmp/dmbushou-remote/common.pretty.js` | 2347-2504 |
| Electron 平台连接入口 | `/tmp/danmaku-catcher-readable/main.js` | 44130-44134 |
| 平台连接主流程 | `/tmp/danmaku-catcher-readable/main.js` | 42491-42790 |
| 平台 session 创建/迁移 | `/tmp/danmaku-catcher-readable/main.js` | 42020-42079 |
| 授权窗口打开 `loginUrl` 和导航白名单 | `/tmp/danmaku-catcher-readable/main.js` | 42080-42235 |
| Cookie 采集、加密上传 `checkV2` | `/tmp/danmaku-catcher-readable/main.js` | 42844-42962 |
| TikTok 上传前店铺信息采集 | `/tmp/danmaku-catcher-readable/main.js` | 42963-43020 |
| localAuth 支持平台和本地店铺解析 | `/tmp/danmaku-catcher-readable/main.js` | 42466-42469, 43022-43191 |
| Cookie 串汇总和同步到主用户 session | `/tmp/danmaku-catcher-readable/main.js` | 43199-43266 |
| 保存商家后台 Cookie | `/tmp/danmaku-catcher-readable/main.js` | 43267-43316 |
| 直播店铺绑定数据 | `/tmp/dmbushou-remote/saas-index.pretty.js` | 1427-1475 |
| `queryUserShopBindsV2` 接口 | `/tmp/dmbushou-remote/saas-index.pretty.js` | 2703 |
| `liveShopData` 接口 | `/tmp/dmbushou-remote/saas-index.pretty.js` | 3091-3098 |
| 自动打印获取 Cookie/房间号/WebSocket | `/tmp/dmbushou-remote/common.pretty.js` | 2650-2745 |
| 打印机选择组件 | `/tmp/dmbushou-remote/common.pretty.js` | 69-169 |
| 获取系统打印机 hook | `/tmp/dmbushou-remote/common.pretty.js` | 4402-4450 |
| Electron 获取打印机 | `/tmp/danmaku-catcher-readable/main.js` | 36902-36905 |
| 默认打印设置 | `/tmp/danmaku-catcher-readable/main.js` | 36831-36852 |
| 主进程打印任务 | `/tmp/danmaku-catcher-readable/main.js` | 36932-37276 |
| 前端模板转 HTML | `/tmp/dmbushou-remote/143.pretty.js` | 1447-1481 |
| prepare print document | `/tmp/dmbushou-remote/143.pretty.js` | 6979-7031 |
| 测试打印 payload | `/tmp/dmbushou-remote/143.pretty.js` | 7681-7714 |
| 支持 HTML 打印检测 | `/tmp/dmbushou-remote/143.pretty.js` | 7952-7968 |
| 本地打印窗口自动缩字 | `/tmp/danmaku-catcher-asar/dist/resources/print.html` | 52-110 |
| 打印设置页面表单 | `/tmp/danmaku-catcher-asar/dist/resources/print-settings.html` | 161-297 |
| 打印设置保存 | `/tmp/danmaku-catcher-asar/dist/resources/print-settings.html` | 321-355 |
| 打印设置 IPC 保存/加载/重置 | `/tmp/danmaku-catcher-readable/main.js` | 44386-44410 |
| 打印设置菜单入口 | `/tmp/danmaku-catcher-readable/main.js` | 37785-38012 |
