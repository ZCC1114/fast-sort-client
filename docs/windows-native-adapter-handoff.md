# Windows native adapter handoff

更新日期：2026-07-07

本文档给 Windows 侧 Codex 作为长期执行依据。最终目标是：

1. 客户端负责打开各平台后台工作台并采集 Cookie。
2. Cookie 保存到迅拣后台房间 `liveSession`。
3. 正式开播时客户端只从 `queryRoomsByUserId` 返回的房间 `liveSession` 取 Cookie。
4. 客户端内置 native adapter 直接连接平台弹幕源。
5. 不启动、不打包、不连接 `/taobao_live`、`/kuaishou_live`、`/wx_live`、`/xhs_live`、`/DouyinLiveWebFetcher-mainPython` 这类外部 Python 服务。
6. 不分析或依赖 `/Users/zcc/Documents/git-workspace-zcc/BarrageGrab`。

## 当前我能提供的资料

已从当前 macOS 客户端和迅拣后端确认：

- 正式平台 `liveType` 枚举。
- 各平台后台工作台登录地址。
- 当前后端保存 Cookie 到房间的接口、请求体和返回口径。
- `queryRoomsByUserId` 返回房间字段与空值风险。
- macOS native adapter 代码骨架和部分真实 adapter 迁移结果。
- 抖音 `sign.js` 已随 macOS 客户端资源提交，可作为 Windows 嵌入 JS 执行参考。
- 协议抓包目录约定和每个平台仍缺的真实协议样本清单。

当前不能直接提供：

- 平台账号、密码、Cookie。
- 已登录账号的 HAR、WSS 二进制帧、protobuf 帧样本。
- 正在直播的测试房间。

这些资料必须由账号持有人在客户端 WebView 或本地抓包工具中扫码登录后生成，放到 `local-captures/`，不要提交到 git，也不要发到聊天里。

## 正式 liveType 合同

后端枚举来源：`fast-sort/src/main/java/io/geekidea/boot/common/enums/fs/LiveTypeEnum.java`。

| 授权平台 key | 平台名称 | 正式 `liveType` | 客户端 adapter key | 说明 |
| --- | --- | --- | --- | --- |
| `fxg` | 抖音工作台 | `0` | `douyin` | 抖店工作台 Cookie，最终必须支持只靠工作台 Cookie 自动解析当前直播 |
| `fxg_kol` | 抖音达人工作台 | `0` | `douyin` | 达人工作台 Cookie，和 `fxg` 同属抖音房间类型 |
| `tb` | 千牛工作台 | `1` | `taobao` | 千牛/淘宝工作台 Cookie |
| `xhs` | 小红书工作台 | `2` | `xiaohongshu` | ark/客服工作台 Cookie |
| `ec` | 视频号工作台 | `3` | `wechat` | 视频号助手 Cookie |
| `ks` | 快手工作台 | `4` | `kuaishou` | 快手小店/工作台 Cookie |

后端还有 `liveType=5` 孔网，不属于本轮 `fxg/fxg_kol/tb/xhs/ec/ks` native adapter 目标。

TikTok/Shopee 当前不属于迅拣正式业务范围：

- macOS 代码中只有 `PendingNativeDanmakuAdapter` 占位。
- 后端当前没有对应正式 `liveType` 和保存房间接口。
- Windows 不要把 TikTok/Shopee 接入正式直播页，除非后端先补正式枚举和保存接口。

## 工作台登录地址

这些地址来自当前 macOS 客户端 `DanmakuPlatformRegistry`，用于 WebView/WebView2 打开后扫码登录并采集 Cookie。

| key | 名称 | 登录地址 | Cookie 域 | 成功页匹配 |
| --- | --- | --- | --- | --- |
| `fxg` | 抖音工作台 | `https://fxg.jinritemai.com/login/common` | `jinritemai.com` | `https://fxg.jinritemai.com/ffa/mshop/homepage/index` |
| `fxg_kol` | 抖音达人工作台 | `https://buyin.jinritemai.com/mpa/account/login` | `jinritemai.com` | `https://buyin.jinritemai.com/dashboard*` |
| `xhs` | 小红书工作台 | `https://customer.xiaohongshu.com/login?service=https://ark.xiaohongshu.com/app-system/home` | `xiaohongshu.com` | `https://ark.xiaohongshu.com/app-system/home*` |
| `tb` | 千牛工作台 | `https://loginmyseller.taobao.com/?from=&f=top&style=&sub=true&redirect_url=https%3A%2F%2Fmyseller.taobao.com%2Fhome.htm%2Flive-dashboard-qn%2F` | `taobao.com` | `https://myseller.taobao.com/home.htm/live-dashboard-qn/` |
| `ec` | 视频号工作台 | `https://channels.weixin.qq.com/login.html` | `weixin.qq.com` | `https://channels.weixin.qq.com/platform/*` |
| `ks` | 快手工作台 | `https://login.kwaixiaodian.com/?biz=zone&redirect_url=https%3A%2F%2Fs.kwaixiaodian.com%2Fzone%2Forder%2Flist` | `kwaixiaodian.com` | `https://s.kwaixiaodian.com/zone/order/list*` |

Windows 实现要求：

- 使用 WebView2 打开上述地址。
- 登录成功后从 WebView2 CookieManager 采集该平台域及必要关联域 Cookie。
- 保存为标准 Cookie header 字符串，或按后端已支持 JSON 格式写入 `liveSession`。
- UI 不提供手动输入 Cookie、抖音号、直播间号、分享链接、短链作为新增直播间主路径。

## 后端房间查询合同

接口：

```http
POST /app/fsUserRoom/queryRoomsByUserId/{userId}
Authorization: Bearer <token>
Accept: application/json
```

返回：

- Controller 返回 `ApiResult.success(userRoomVoList)`。
- Client 侧按 `APIEnvelope<[RoomListItem]>` 解包，即业务数据在 `data` 字段。
- Mapper 使用 `select * from FS_USER_ROOM where DELETION = 0 and USER_ID = #{userId} order by CREATED_TIME desc`。

`FsUserRoomVo` 已有字段：

- `id`
- `userId`
- `roomNumber`
- `eid`
- `roomUrl`
- `roomName`
- `liveType`
- `liveSession`
- 打印模板、标签、时间等业务字段

注意：

- 字段会随记录返回，但值不保证非空。
- `liveSession` 只有保存 Cookie 后才有值。
- `roomNumber` 是历史兼容字段，最终新增流程不要求用户填写。
- `eid` 当前主要给快手使用，可能为空。
- 抖音 `liveSession` 在数据库中加密保存，`queryRoomsByUserId` 返回前后端会解密。
- 其他平台 `liveSession` 当前按保存格式原样返回，通常是 raw Cookie 或 JSON。

## 保存 Cookie 到房间接口

所有接口都走：

```http
Authorization: Bearer <token>
Accept: application/json
Content-Type: application/json
```

### 抖音

当前已有两个接口，但还不满足最终“只通过工作台 Cookie 添加直播间”的目标。

旧添加房间：

```http
POST /app/fsUserRoom/addFsUserRoom/{roomNumber}
```

行为：

- 创建 `liveType=0` 房间。
- 依赖 `roomNumber` 抓取 `https://live.douyin.com/{roomNumber}` 填房间信息。
- 不保存 Cookie。
- 这是旧手填房间号流程，最终新增入口不能依赖它。

绑定 Cookie：

```http
POST /app/fsUserRoom/bindDouyinRoomCookie
```

请求体：

```json
{
  "id": "room-id",
  "cookies": "raw cookie header"
}
```

行为：

- 只允许更新 `liveType=0` 的已有房间。
- 后端加密 Cookie 后写入 `LIVE_SESSION`。
- 返回 `ApiResult.success(encryptedCookies)`，但客户端正式开播应以后续 `queryRoomsByUserId` 返回的已解密 `liveSession` 为准。

必须补齐或确认：

- 新增一个抖音 cookie-only add/update 接口，或扩展现有接口，让 `fxg/fxg_kol` 登录成功后无需手填 `roomNumber` 也能创建/更新房间。
- 该接口应保存工作台 Cookie，并尽量由后端或客户端 adapter 从工作台接口解析当前直播标识、房间名、封面。

### 淘宝

接口：

```http
POST /app/fsUserRoom/addFsUserTBRoom
```

请求体：

```json
{
  "roomName": "千牛直播间",
  "roomNumber": "",
  "liveSession": "raw cookie header or JSON",
  "cookies": "raw cookie header, legacy compatible"
}
```

行为：

- 创建 `liveType=1` 房间。
- `roomName` 必填。
- `roomNumber` 可为空。
- 后端优先取 `liveSession`，为空时兼容 `cookies`。
- raw Cookie 会被标准化为 `{"cookies":{...}}` JSON 后保存。
- 返回 `ApiResult.result(flag)`。

Windows 侧新增房间时：

- 不要求用户填淘宝 roomId。
- 登录千牛工作台后传 `roomName` 和 Cookie。
- 开播时 adapter 用 `liveSession` 解析当前直播 roomId。

### 小红书

接口：

```http
POST /app/fsUserRoom/addUpdateFsUserXhsRoom
```

请求体：

```json
{
  "id": "",
  "cookies": "raw cookie header"
}
```

行为：

- `id` 为空则新增，非空则更新。
- 新增时创建 `liveType=2` 房间。
- 默认 `roomName=小红书直播间`。
- 后端解析 raw Cookie，只保存白名单 Cookie：
  - `a1`
  - `web_session`
  - `access-token-ark.xiaohongshu.com`
  - `customer-sso-sid`
  - `x-user-id-ark.xiaohongshu.com`
- `liveSession` 保存为 `{"cookies":{...},"user_id":"..."}`。
- 如果能解析 `x-user-id-ark.xiaohongshu.com`，会写入 `roomNumber`。
- 返回 `ApiResult.result(flag)`。

Windows 侧新增房间时：

- 只打开小红书 ark/客服工作台登录页。
- 不要求用户手填 roomId。
- 开播时 adapter 必须从 `liveSession` 取 ark Cookie 后解析当前直播；不要再跳转或依赖 `redlive.xiaohongshu.com/live_plan`。

### 视频号

接口：

```http
POST /app/fsUserRoom/addFsUserWXRoom
```

请求体：

```json
{
  "id": "",
  "roomName": "视频号直播间",
  "cookies": "raw cookie header",
  "roomUrl": ""
}
```

行为：

- `id` 为空则新增，非空则更新。
- 新增时创建 `liveType=3` 房间。
- `roomName` 为空时默认 `视频号直播间`。
- `liveSession` 原样保存为 `cookies`。
- 返回 `ApiResult.result(flag)`。

Windows 侧 adapter 要求：

- 从 `liveSession` 解析 `sessionid` 和 `wxuin`。
- 用视频号助手接口检查直播状态并拉取消息。

### 快手

接口：

```http
POST /app/fsUserRoom/addUpdateFsUserKuaishouRoom
```

请求体：

```json
{
  "id": "",
  "roomNumber": "",
  "eid": "",
  "cookies": "raw cookie header"
}
```

行为：

- `id` 为空则新增，非空则更新。
- 新增时创建 `liveType=4` 房间。
- 默认 `roomName=快手直播间`。
- `liveSession` 保存为 `{"cookies":{...},"user_id":"..."}`。
- 如果请求体带 `eid`，优先把 `eid` 同步写入 `eid` 和 `roomNumber`。
- 如果没有 `eid` 但带 `roomNumber`，写入 `eid` 和 `roomNumber`。
- 如果两者都没有，但 Cookie 中有 `userId/userid/user_id`，会把该值写入 `roomNumber`。
- 返回 `ApiResult.result(flag)`。

最终目标：

- 新增房间不要求用户填快手房间号。
- 如果当前后端没有能力从 Cookie 得到当前直播 `eid/liveStreamId`，Windows adapter 应在开播时用工作台 Cookie 自行解析。

## liveSession 解析标准

Windows 和 macOS 必须保持同一解析口径：

- raw Cookie header：`a=1; b=2`
- JSON 字段：`{"cookie":"a=1; b=2"}` 或 `{"cookies":"a=1; b=2"}`
- JSON map：`{"cookies":{"a":"1","b":"2"}}`
- cookie item array：`[{"name":"a","value":"1"},{"name":"b","value":"2"}]`
- 嵌套 cookie item array：`{"cookies":[{"name":"a","value":"1"}]}`

解析结果统一输出：

- Cookie header 字符串。
- Cookie map。
- 平台特定字段，例如视频号 `sessionid/wxuin`。

正式直播页只能读取后台房间 `liveSession`，不能依赖授权测试页的临时状态。

## macOS 当前可参考代码

macOS 客户端路径：

```text
clients/macos/FastSortClientMac/
```

核心文件：

```text
Sources/FastSortClientMac/Services/Danmaku/NativeDanmakuModels.swift
Sources/FastSortClientMac/Services/Danmaku/NativeDanmakuAdapter.swift
Sources/FastSortClientMac/Services/Danmaku/NativeDanmakuAdapterFactory.swift
Sources/FastSortClientMac/Services/Danmaku/NativeDanmakuSessionCoordinator.swift
Sources/FastSortClientMac/Services/Danmaku/Shared/NativeDanmakuSupport.swift
Sources/FastSortClientMac/Services/Danmaku/Douyin/DouyinNativeDanmakuAdapter.swift
Sources/FastSortClientMac/Services/Danmaku/Taobao/TaobaoNativeDanmakuAdapter.swift
Sources/FastSortClientMac/Services/Danmaku/Kuaishou/KuaishouNativeDanmakuAdapter.swift
Sources/FastSortClientMac/Services/Danmaku/Wechat/WechatNativeDanmakuAdapter.swift
Sources/FastSortClientMac/Services/Danmaku/Xiaohongshu/XiaohongshuNativeDanmakuAdapter.swift
Sources/FastSortClientMac/Resources/Danmaku/Douyin/sign.js
```

macOS 已删除旧 helper 入口：

```text
Sources/FastSortClientMac/Services/LocalDanmakuHelperManager.swift
Sources/FastSortClientMac/Services/DanmakuLocalConnectionBuilder.swift
```

Windows 实现时不要恢复等价的 helper manager、端口配置或 `127.0.0.1` URL builder。

## 抓包和参考文件目录

本仓库 `.gitignore` 已忽略：

```text
local-captures/
```

账号持有人可以在本地创建：

```text
local-captures/douyin/
local-captures/kuaishou/
local-captures/taobao/
local-captures/wechat/
local-captures/xhs/
```

不要提交这些文件。不要把 Cookie、token、账号密码发到聊天里。

建议文件命名：

```text
local-captures/<platform>/README.md
local-captures/<platform>/login-success.har
local-captures/<platform>/live-open.har
local-captures/<platform>/wss-url-and-headers.txt
local-captures/<platform>/ws-frame-001.bin
local-captures/<platform>/ws-frame-002.bin
local-captures/<platform>/message-samples.jsonl
```

`README.md` 只写不含敏感值的说明：

- 测试日期。
- 平台。
- 登录入口。
- 是否正在直播。
- 哪个请求对应当前直播解析。
- 哪个请求或 WSS 对应弹幕源。
- 样本文件说明。

## 各平台仍需资料

### 抖音

当前可提供：

- `sign.js` 已在 macOS 客户端资源中。
- 可参考本地协议项目中的 `douyin.proto`，但 Windows 仓库应通过生成代码或等价 parser 纳入自身源码，不运行 Python 项目。
- macOS adapter 已实现 JS 签名、WSS、gzip/protobuf、ack、heartbeat、聊天/礼物/进场/点赞/互动事件解析。

仍需要账号侧提供：

- `fxg` 和/或 `fxg_kol` 登录后解析当前直播的接口 HAR。
- 成功连接 WSS 的请求 URL 和 headers。
- 几帧 WSS 二进制消息样本。
- 工作台 Cookie 到 live_id/room_id 的稳定解析路径。

### 淘宝

当前可提供：

- 后端保存接口已支持 `liveSession/cookies`。
- macOS adapter 已有千牛 Cookie 解析当前直播 roomId 和 impaas 轮询参考。

仍需要账号侧提供：

- 千牛直播工作台打开当前直播的 HAR。
- 当前直播 roomId 解析接口样本。
- 弹幕轮询接口请求/响应样本。
- 关键 headers、token、csrf 字段说明。

### 小红书

当前可提供：

- 后端保存接口已支持 ark/客服工作台 Cookie。
- macOS adapter 有从工作台 Cookie 补齐直播登录态并连接弹幕的参考实现。

仍需要账号侧提供：

- ark 工作台直播相关接口 HAR。
- 当前直播 roomId/liveId 解析接口样本。
- 弹幕源类型和连接请求。
- 必要 headers、csrf、token、签名字段。

### 视频号

当前可提供：

- 后端保存接口已支持 raw Cookie。
- macOS adapter 已按 `sessionid/wxuin`、视频号助手接口、`join_live`、`msg` polling 做了 native 参考实现。

仍需要账号侧提供：

- 视频号助手登录后 Cookie 样本的字段名清单，不要提交值。
- 检查直播状态接口 HAR。
- `join_live` 和拉取消息接口 HAR。
- 弹幕、礼物、点赞、进场等响应样本。

### 快手

当前可提供：

- 后端保存接口已支持 `cookies/eid/roomNumber`，但最终不要求用户手填。
- macOS adapter 有 owner/liveStreamId/token 解析和 WebSocket/protobuf 弹幕参考。

仍需要账号侧提供：

- 快手工作台解析当前直播的 HAR。
- `websocketinfo` 或等价请求/响应样本。
- enter room、heartbeat 二进制样本。
- 弹幕帧样本。
- protobuf 或字段结构。

### TikTok/Shopee

当前不接正式直播页。

只有在后端确认正式业务范围后才继续：

- 增加正式 `liveType`。
- 增加保存 Cookie 到房间接口。
- 增加工作台登录地址。
- 增加 native adapter。

## Windows 开发顺序

1. 对齐基础 schema：`NativeDanmakuEvent`、`NativeDanmakuConnectRequest`、`NativeDanmakuAdapter`、`NativeDanmakuConnection`。
2. 实现 `DanmakuCookieSessionParser`，测试 raw Cookie、JSON 字段、map、item array。
3. 实现 `NativeDanmakuAdapterFactory`，只注册已实现平台；未实现平台明确报错。
4. 用 WebView2 实现工作台登录、Cookie 采集和保存房间，不提供手填主路径。
5. 正式直播页开播前从 `queryRoomsByUserId` 房间读取 `liveSession`，通过 coordinator 做 adapter 预检。
6. 先接抖音，因为已有 `sign.js/protobuf/WSS` 迁移参考，但要补工作台 Cookie 到当前直播的稳定解析。
7. 再接淘宝、快手、视频号、小红书，顺序以可测试账号和抓包资料齐全程度决定。
8. 每接一个平台都补 adapter 单测、协议样本解析测试、UI 错误流和真实账号验收记录。

## Windows 验收清单

- 客户端启动后不要求启动任何外部 Python 服务。
- 正式源码中没有 helper manager、端口配置、`127.0.0.1` 弹幕连接、`/tb-ws`、`/ks-ws`、`/wx-ws`、`/xhs-ws` 运行路径。
- 添加直播间只通过平台工作台扫码登录和 Cookie 保存。
- 正式开播只从后台房间 `liveSession` 取 Cookie。
- 未实现平台报 native adapter 未实现，不回退旧链路。
- `queryRoomsByUserId` 返回缺少 `liveSession` 时，UI 明确提示重新授权，不创建直播记录。
- TikTok/Shopee 不进入正式直播页，除非后端合同已补齐。
