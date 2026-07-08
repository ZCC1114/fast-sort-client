# 平台 Cookie 获取步骤和登录页

本文按当前 macOS 客户端 `直播授权测试` 模块的配置整理。登录地址主要参考弹幕捕手打开的各平台后台工作台登录地址，不代表平台永久不变；如果平台改版，需要同步更新这里和客户端平台注册表。

本文也作为 Windows 客户端实现平台注册表的输入。Windows 电脑不需要安装弹幕捕手，直接按下面的“弹幕捕手添加直播间登录地址清单”和“Cookie 域名与页面匹配规则”实现即可。

## 通用采集流程

1. 在客户端内创建独立 `WKWebView`，使用统一的持久化 `DanmakuWebAuthSessionStore` 保存平台登录会话。
2. 按平台打开对应 `loginURL`。
3. WebView 导航只允许当前平台域名和白名单域名；跳到非白名单外部域时阻止内嵌窗口跳转，交给外部浏览器。
4. 用户在内嵌 WebView 完成登录。
5. 当当前 URL 同时命中 `contentScriptMatch` 和 `pageHandlerMatch`，等待 2.5 秒后自动调用 Cookie 采集。
6. 也可以点击“手动采集 Cookie”。
7. 调用 `websiteDataStore.httpCookieStore.getAllCookies` 读取当前 WebView 会话 Cookie。
8. 按平台 `cookieDomain`、登录页 host、`cookieURLs` host、`allowedDomains` 过滤 Cookie。
9. 输出完整 Cookie header：`name=value; name2=value2`。
10. 保存 Cookie 到迅拣后台房间 `liveSession`。
11. 后续 native adapter 使用这个 Cookie header 直连平台弹幕源。
12. 最终添加直播间流程不再要求用户手动输入 Cookie、抖音号、roomId、unique_id、session_id、短链或分享链接。

## 弹幕捕手添加直播间登录地址清单

来源说明：

- Chrome 扩展包读取自 `/Users/zcc/Documents/git-workspace-zcc/dmbs/danmaku-catcher-1.24.0-chrome/reverse-engineered-danmaku-catcher/src/shared/platforms.js`，该文件包含抖音工作台、小红书、千牛、抖音达人、TikTok、Shopee。
- 桌面端补充读取自 `docs/danmaku-catcher-implementation-research.md`，该文档已整理视频号、快手和微信小店配置。
- `/Users/zcc/Documents/git-workspace-zcc/BarrageGrab` 不参与本次分析。

| 弹幕捕手平台 ID | key | 展示名 | 添加弹窗展示 | 弹幕捕手打开地址 | 迅拣建议默认地址 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | `fxg` | 抖音工作台 | 是 | `https://fxg.jinritemai.com/`（Chrome 扩展 v1.24.0）；`https://fxg.jinritemai.com/login/common`（桌面端研究记录） | `https://fxg.jinritemai.com/login/common` | 两个地址都进入抖店工作台；迅拣默认用显式登录页，若平台跳转异常再回退到工作台首页。 |
| `4` | `fxg_kol` | 抖音达人工作台 | 是 | `https://buyin.jinritemai.com/mpa/account/login` | `https://buyin.jinritemai.com/mpa/account/login` | 百应/达人工作台入口。 |
| `2` | `xhs` | 小红书工作台 | 是 | `https://customer.xiaohongshu.com/login?service=https://ark.xiaohongshu.com/app-system/home` | `https://customer.xiaohongshu.com/login?service=https://ark.xiaohongshu.com/app-system/home` | 登录后进入 ark 工作台。 |
| `3` | `tb` | 千牛工作台 | 是 | `https://loginmyseller.taobao.com/?from=&f=top&style=&sub=true&redirect_url=https%3A%2F%2Fmyseller.taobao.com%2Fhome.htm%2Flive-dashboard-qn%2F` | `https://loginmyseller.taobao.com/?from=&f=top&style=&sub=true&redirect_url=https%3A%2F%2Fmyseller.taobao.com%2Fhome.htm%2Flive-dashboard-qn%2F` | 登录后进入直播看板。 |
| `5` | `tiktok` | TikTok 工作台 | 是，弹幕捕手要求客户端版本不低于 `1.20.0` | `https://seller.tiktokshopglobalselling.com/account/login` | `https://seller.tiktokshopglobalselling.com/account/login` | 后续是否接入正式页取决于迅拣后端 `liveType`。 |
| `6` | `shopee` | Shopee/虾皮工作台 | 是 | `https://seller.shopee.cn/account/signin` | `https://seller.shopee.cn/account/signin` | 登录后进入 Shopee seller。 |
| `7` | `ec` | 视频号工作台 | 是 | `https://channels.weixin.qq.com/login.html` | `https://channels.weixin.qq.com/login.html` | 来自桌面端研究记录。 |
| `8` | `ks` | 快手工作台 | 是 | `https://login.kwaixiaodian.com/?biz=zone&redirect_url=https%3A%2F%2Fs.kwaixiaodian.com%2Fzone%2Forder%2Flist` | `https://login.kwaixiaodian.com/?biz=zone&redirect_url=https%3A%2F%2Fs.kwaixiaodian.com%2Fzone%2Forder%2Flist` | 来自桌面端研究记录，登录后进入快手小店订单页。 |
| `99` | `wx_store` | 微信小店工作台 | 否，配置存在但弹幕捕手添加弹窗过滤掉 | `https://store.weixin.qq.com/shop?redirect_url=%2Forder%2Flist` | 暂不作为迅拣当前添加入口 | 如果未来接微信小店，可按该配置单独放开。 |

## Cookie 域名与页面匹配规则

| key | Cookie 主域 | contentScriptMatch | pageHandlerMatch | cookieUrls/allowedDomains |
| --- | --- | --- | --- | --- |
| `fxg` | `jinritemai.com` | `*://fxg.jinritemai.com/*` | `*://fxg.jinritemai.com/ffa/mshop/homepage/index` | 弹幕捕手无额外项；迅拣可额外允许 `douyin.com` 供直播页接口扩展。 |
| `fxg_kol` | `jinritemai.com` | `*://buyin.jinritemai.com/*` | `*://buyin.jinritemai.com/dashboard*` | 弹幕捕手无额外项；迅拣可额外允许 `douyin.com` 供直播页接口扩展。 |
| `xhs` | `xiaohongshu.com` | `*://ark.xiaohongshu.com/*` | `*://ark.xiaohongshu.com/app-system/home` | 无。 |
| `tb` | `taobao.com` | `*://*.taobao.com/*` | `*://*.taobao.com/home.htm/*live*` | 兼容旧 `myseller.taobao.com/home.htm/live-dashboard-qn/` 和新版 `qn.taobao.com/home.htm/qn-live-container/live/control?liveId=...`；迅拣可额外允许 `tmall.com`；授权窗口额外允许 `alicdn.com` 作为导航白名单，不纳入 Cookie 采集域。 |
| `tiktok` | `tiktokshopglobalselling.com` | `*://seller.us.tiktokshopglobalselling.com/*` | `*://seller.us.tiktokshopglobalselling.com/homepage*` | 迅拣可额外允许 `tiktok.com`。 |
| `shopee` | `shopee.cn` | `*://seller.shopee.cn/?cnsc_shop_id=*` | `*://seller.shopee.cn/*` | 无。 |
| `ec` | `weixin.qq.com` | `*://channels.weixin.qq.com/platform/*` | `*://channels.weixin.qq.com/platform/*` | 无。 |
| `ks` | `kwaixiaodian.com` | `*://*.kwaixiaodian.com/*` | `*://s.kwaixiaodian.com/zone/order/list*` | `cookieUrls = ["https://s.kwaixiaodian.com/zone/order/list"]`。 |
| `wx_store` | `weixin.qq.com` | `*://store.weixin.qq.com/*` | `*://store.weixin.qq.com/shop/order/list*` | `cookieUrls = ["https://store.weixin.qq.com/shop/order/list"]`，`allowedDomains = ["store.weixin.qq.com"]`。 |

## 平台明细

| 平台 | 登录页 | 登录成功匹配页 | Cookie 主域 | 额外白名单域 | 最终添加方式 |
| --- | --- | --- | --- | --- | --- |
| 抖音工作台 | `https://fxg.jinritemai.com/login/common` | `*://fxg.jinritemai.com/ffa/mshop/homepage/index` | `jinritemai.com` | `douyin.com` | 扫码/账号登录后保存 Cookie，adapter 自动解析当前直播 |
| 抖音达人工作台 | `https://buyin.jinritemai.com/mpa/account/login` | `*://buyin.jinritemai.com/dashboard*` | `jinritemai.com` | `douyin.com` | 扫码/账号登录后保存 Cookie，adapter 自动解析当前直播 |
| 小红书工作台 | `https://customer.xiaohongshu.com/login?service=https://ark.xiaohongshu.com/app-system/home` | `*://ark.xiaohongshu.com/app-system/home*` | `xiaohongshu.com` | 无 | 扫码/账号登录后保存 ark Cookie，adapter 自动解析当前直播 |
| 千牛/淘宝工作台 | `https://loginmyseller.taobao.com/?from=&f=top&style=&sub=true&redirect_url=https%3A%2F%2Fmyseller.taobao.com%2Fhome.htm%2Flive-dashboard-qn%2F` | `*://*.taobao.com/home.htm/*live*` | `taobao.com` | `tmall.com`；导航额外允许 `alicdn.com` | 扫码/账号登录后保存 Cookie，adapter 自动解析当前直播 |
| TikTok 工作台 | `https://seller.tiktokshopglobalselling.com/account/login` | `*://seller.us.tiktokshopglobalselling.com/homepage*` | `tiktokshopglobalselling.com` | `tiktok.com` | 扫码/账号登录后保存 Cookie，adapter 自动解析当前直播 |
| Shopee/虾皮工作台 | `https://seller.shopee.cn/account/signin` | `*://seller.shopee.cn/*` | `shopee.cn` | 无 | 扫码/账号登录后保存 Cookie，adapter 自动解析当前直播 |
| 视频号工作台 | `https://channels.weixin.qq.com/login.html` | `*://channels.weixin.qq.com/platform/*` | `weixin.qq.com` | 无 | 扫码登录后保存 Cookie，adapter 自动解析当前直播 |
| 快手工作台 | `https://login.kwaixiaodian.com/?biz=zone&redirect_url=https%3A%2F%2Fs.kwaixiaodian.com%2Fzone%2Forder%2Flist` | `*://s.kwaixiaodian.com/zone/order/list*` | `kwaixiaodian.com` | `s.kwaixiaodian.com` | 扫码/账号登录后保存 Cookie，adapter 自动解析当前直播 |
| 微信小店工作台 | `https://store.weixin.qq.com/shop?redirect_url=%2Forder%2Flist` | `*://store.weixin.qq.com/shop/order/list*` | `weixin.qq.com` | `store.weixin.qq.com` | 弹幕捕手配置存在但添加弹窗过滤，迅拣当前不作为默认入口 |

## 各平台具体步骤

### 抖音工作台

1. 打开 `https://fxg.jinritemai.com/login/common`。
2. 在内嵌 WebView 扫码或账号登录。
3. 登录完成后等待跳转到 `fxg.jinritemai.com/ffa/mshop/homepage/index`。
4. 命中成功页后自动采集 `jinritemai.com`、登录页 host 和 `douyin.com` 相关 Cookie。
5. 保存完整 Cookie 到迅拣抖音房间的 `liveSession`。
6. native adapter 用 Cookie 自动解析当前直播间并完成签名、WSS 和 protobuf 解析。

### 抖音达人工作台

1. 打开 `https://buyin.jinritemai.com/mpa/account/login`。
2. 登录达人/百应账号。
3. 等待跳转到 `buyin.jinritemai.com/dashboard*`。
4. 采集 `jinritemai.com` 和 `douyin.com` 相关 Cookie。
5. 后续弹幕链路和抖音工作台一致，不要求用户输入抖音号或 `live_id`。

### 小红书工作台

1. 打开 `https://customer.xiaohongshu.com/login?service=https://ark.xiaohongshu.com/app-system/home`。
2. 完成小红书商家/工作台登录。
3. 等待跳转到 `ark.xiaohongshu.com/app-system/home`。
4. 采集 `xiaohongshu.com` 相关 Cookie。
5. 弹幕捕手添加直播间阶段只采集 ark 工作台 Cookie，不在授权页直接解析直播间连接态。
6. Cookie 经 `checkV2` 校验后绑定店铺；开启自动打印时再通过 `liveShopData` 取回店铺 Cookie。
7. 平台 adapter 用店铺 Cookie 执行直播信息解析，解析当前直播间后再连接平台弹幕源。

### 千牛/淘宝工作台

1. 打开 `https://loginmyseller.taobao.com/?from=&f=top&style=&sub=true&redirect_url=https%3A%2F%2Fmyseller.taobao.com%2Fhome.htm%2Flive-dashboard-qn%2F`。
2. 完成淘宝/千牛商家账号登录。
3. 等待跳转到 `myseller.taobao.com/home.htm/live-dashboard-qn/`。
4. 采集 `taobao.com`、登录页 host 和 `tmall.com` 相关 Cookie。
5. 保存完整 Cookie 到迅拣淘宝房间的 `liveSession`。
6. native adapter 用千牛 Cookie 打开直播看板或工作台接口并解析当前 `roomId`，再轮询淘宝 `impaas` 弹幕源。
7. 新版千牛直播管理页的 URL 可能只有数字 `liveId`，真实弹幕轮询 roomId 需要从工作台请求 `//impaas.alicdn.com/live/message/{uuid}/{start}/{end}` 中解析，例如 `69297687-d197-4781-b71a-4d3ba1dc7acf`；轮询时间窗口是 Unix 秒，不是毫秒。

### TikTok 工作台

1. 打开 `https://seller.tiktokshopglobalselling.com/account/login`。
2. 完成 TikTok Shop 商家账号登录。
3. 等待跳转到 `seller.us.tiktokshopglobalselling.com/homepage*`。
4. 采集 `tiktokshopglobalselling.com` 和 `tiktok.com` 相关 Cookie。
5. 保存完整 Cookie 到迅拣 TikTok 房间的 `liveSession`。
6. native adapter 负责从工作台 Cookie 解析当前直播，并完成 TikTokLive 协议和签名。

### Shopee/虾皮工作台

1. 打开 `https://seller.shopee.cn/account/signin`。
2. 完成虾皮商家账号登录。
3. 登录后只要在 `seller.shopee.cn/*` 范围内即可命中成功页。
4. 采集 `shopee.cn` 相关 Cookie。
5. 保存完整 Cookie 到迅拣 Shopee 房间的 `liveSession`。
6. native adapter 负责从工作台 Cookie 解析直播 session/chatroom 并连接 Shopee Live 弹幕。

### 视频号工作台

1. 打开 `https://channels.weixin.qq.com/login.html`。
2. 使用微信扫码登录视频号助手。
3. 等待进入 `channels.weixin.qq.com/platform/*`。
4. 采集 `weixin.qq.com` 相关 Cookie。
5. Cookie 中必须有 `sessionid` 和 `wxuin`。
6. native adapter 从 Cookie 解析 `sessionid/wxuin`，再解析当前直播状态并连接消息源。

### 快手工作台

1. 打开 `https://login.kwaixiaodian.com/?biz=zone&redirect_url=https%3A%2F%2Fs.kwaixiaodian.com%2Fzone%2Forder%2Flist`。
2. 完成快手小店账号登录。
3. 等待跳转到 `s.kwaixiaodian.com/zone/order/list*`。
4. 采集 `kwaixiaodian.com` 和 `s.kwaixiaodian.com` 相关 Cookie。
5. 保存完整 Cookie 到迅拣快手房间的 `liveSession`。
6. native adapter 用 Cookie 请求工作台、直播页和 `websocketinfo`，自动拿到 `liveStreamId`、token 和平台 WebSocket 地址，再解析 protobuf 弹幕。

## 实现注意点

- Cookie 采集一定要从内嵌 WebView 的 `httpCookieStore` 读取，不要从系统浏览器拿。
- 采集结果应保存为完整 Cookie header，正式房间接口的 `liveSession` 也应能返回这个格式。
- 视频号必须保留 `sessionid`、`wxuin`。
- 快手 native adapter 需要保留 `kwfv1` -> `Kww` header 的兼容逻辑。
- Windows note 2026-07-07: `DanmakuPlatformRegistry.cs` now keeps these login URLs, cookie domains, match rules, cookie URLs, and allowed domains aligned with this document. It also maps authorization keys to formal native adapter keys: `fxg/fxg_kol -> douyin`, `tb -> taobao`, `xhs -> xiaohongshu`, `ec -> wechat`, `ks -> kuaishou`, `tiktok -> tiktok`, `shopee -> shopee`.
- 小红书最终以 ark 工作台 Cookie native adapter 为准，客户端内完成必要登录态补齐、直播解析和弹幕连接。
- 对于跳到非平台白名单域名的导航，内嵌窗口要阻止并交给外部浏览器，避免授权窗口被第三方页面污染会话。
