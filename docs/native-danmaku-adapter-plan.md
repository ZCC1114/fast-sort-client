# 迅拣 Native 弹幕 Adapter 改造计划

更新日期：2026-07-07

## 最终目标

迅拣桌面客户端的弹幕链路最终统一为 native adapter：

1. 客户端内置平台登录页，负责采集平台 Cookie。
2. Cookie 保存到迅拣后台房间 `liveSession`。
3. 正式开播时，客户端从后台房间 `liveSession` 取 Cookie。
4. 客户端内置 adapter 直接连接平台弹幕源，解析协议并输出统一弹幕事件。
5. 正式链路不依赖外部 Python 服务、不启动本地 helper、不连接迅拣云端弹幕中转。
6. 所有平台添加直播间都通过客户端打开平台后台工作台登录页，用户扫码或账号登录后采集 Cookie 并保存；不再要求用户手动输入 Cookie、抖音号、roomId、unique_id、session_id、短链或分享链接。

最终用户体验必须是：安装并启动迅拣客户端后，即可完成登录授权、Cookie 保存、添加直播间、开播、收弹幕、打印。用户不需要安装 Python、Node、uvicorn、venv，也不需要手动启动 `/taobao_live`、`/kuaishou_live`、`/wx_live`、`/xhs_live`、`/DouyinLiveWebFetcher-mainPython`。

## 不变的业务边界

- 后台继续负责迅拣账号登录、会员、房间、模板、打印策略、直播记录、打印记录和日志。
- Cookie 继续通过现有房间接口保存和返回，字段仍是 `liveSession`。
- 正式开播必须使用后台房间数据，不依赖授权测试页临时状态。
- 平台枚举只使用迅拣后端 `liveType`，不能套用弹幕捕手 `platformId`。
- 平台后台工作台登录地址以弹幕捕手打开的各平台登录地址为主要参考，当前整理在 `docs/platform-cookie-collection-steps.md` 和 `docs/danmaku-catcher-implementation-research.md`。
- Windows 侧不需要安装弹幕捕手；直接按 `docs/platform-cookie-collection-steps.md` 的“弹幕捕手添加直播间登录地址清单”和“Cookie 域名与页面匹配规则”实现 `DanmakuPlatformRegistry.cs`。
- `/Users/zcc/Documents/git-workspace-zcc/BarrageGrab` 不参与分析和实现。

## 统一添加直播间流程

最终版本中，所有平台的“添加直播间”都走同一类交互：

1. 用户在客户端选择平台。
2. 客户端打开该平台后台工作台登录页，地址以 `docs/platform-cookie-collection-steps.md` 的“迅拣建议默认地址”为准。
3. 用户在内置 WebView 中扫码或账号登录。
4. 登录成功页命中平台匹配规则后，客户端自动采集 Cookie。
5. 客户端把 Cookie 保存到迅拣后台房间 `liveSession`，同时保存平台类型、店铺/账号展示名称等可读信息。
6. 正式开播时，native adapter 用 `liveSession` Cookie 调平台工作台或直播接口，自动解析当前直播间、真实 roomId、sessionId、liveStreamId、token 等技术字段。
7. 用户不需要手动输入 Cookie，也不需要输入抖音号、淘宝 roomId、快手房间号、TikTok unique_id、Shopee session_id、短链或分享链接。

允许保留的输入：

- 平台选择。
- 可选的房间备注名或店铺别名，仅用于迅拣 UI 展示。
- 可选的封面、打印模板等迅拣业务配置。

不应作为最终必填项的输入：

- Cookie 文本。
- 抖音号、抖音 live_id。
- 淘宝 roomId 或直播分享链接。
- 快手房间号或 `live.kuaishou.com/u/{id}`。
- TikTok unique_id。
- Shopee session_id、短链或分享链接。
- 小红书 room_id。

## 当前代码状态

macOS 当前已经完成以下基础层：

- `DanmakuPlatformRegistry`：平台登录 URL、Cookie 域、平台 key、`liveType` 映射。
- `DanmakuWebAuthSessionStore`：WebKit 持久化授权会话。
- `DanmakuCookieSessionParser`：从 `liveSession` 解析 raw Cookie、JSON Cookie 字段、cookie map、cookie item array、视频号 `sessionid/wxuin`。
- `DanmakuSocketMessageParser`：统一解析 `pong`、`CONNECTING`、`LIVING`、`STOPPED` 等状态。
- `DanmakuWebSocketSession`：统一 WebSocket 生命周期。

macOS 当前仍存在的过渡实现：

- `LocalDanmakuHelperManager` 会启动 `taobao_live`、`kuaishou_live`、`wx_live`。
- 正式直播页仍有平台分支连接 `127.0.0.1` helper。
- 娱乐模式抖音仍连 `DouyinLiveWebFetcher-mainPython` 的 `8865` 端口。

Windows 当前状态：

- `clients/windows/FastSort.Client.Windows` 是 WPF + .NET 8 骨架。
- 已有登录、API Client、Token 存储、主窗口和基础路由。
- 还没有直播间页、授权测试页、平台 WebView Cookie 采集、native adapter 层。

## 共同架构

macOS 和 Windows 都要落到同一套逻辑分层，语言实现不同，但概念、事件字段和验收标准一致。

### 1. 平台注册表

职责：

- 平台 key、名称、登录 URL、Cookie 域、成功页匹配。
- 迅拣后端 `liveType` 到平台 key 的映射。
- 是否支持 native adapter。
- 添加直播间登录流程、Cookie 域过滤规则和可选展示信息提示文案。

macOS：

- 继续使用 `DanmakuPlatformRegistry.swift`。

Windows：

- 新增 `Core/Danmaku/DanmakuPlatformRegistry.cs`。
- `AppRoute` 增加 `DanmakuCookieTest` 和 `LiveRooms` 的完整页面入口。

### 2. Cookie 采集与保存

职责：

- 在客户端 WebView 打开平台登录页。
- 登录后从浏览器会话读取平台 Cookie。
- 展示脱敏 Cookie。
- 保存到迅拣后台房间 `liveSession`。
- 添加直播间阶段不暴露 Cookie 文本框，不要求用户填写平台房间号或分享链接。

macOS：

- 使用 `WKWebView` + `WKWebsiteDataStore.default()`。
- Cookie 读取来自 `WKHTTPCookieStore`。
- 现有 `DanmakuCookieTestView` 继续作为授权测试入口。

Windows：

- 使用 WebView2。
- 通过 `CoreWebView2.CookieManager.GetCookiesAsync(...)` 读取 Cookie。
- 新增 `Views/DanmakuCookieTestView.xaml`、`ViewModels/DanmakuCookieTestViewModel.cs`。
- 项目需要增加 WebView2 依赖，具体版本由 Windows Codex 在实现时按当前 NuGet 可用版本确认。

### 3. `liveSession` 解析

职责：

- 解析后台返回的 `liveSession`。
- 支持 raw Cookie、JSON 字符串字段、cookie map、cookie item array。
- 平台 adapter 只能依赖该 parser，不在页面中重复解析 Cookie。

macOS：

- 已有 `DanmakuCookieSessionParser.swift`，后续继续扩展平台专用解析。

Windows：

- 新增 `Core/Danmaku/DanmakuCookieSessionParser.cs`。
- 行为要和 macOS parser 保持一致。

### 4. Adapter 接口

所有平台实现统一接口。

macOS 建议：

```swift
protocol NativeDanmakuAdapter {
    var platformKey: String { get }
    func connect(
        request: NativeDanmakuConnectRequest,
        onEvent: @escaping @MainActor (NativeDanmakuEvent) -> Void
    ) async throws -> NativeDanmakuConnection
}
```

Windows 建议：

```csharp
public interface INativeDanmakuAdapter
{
    string PlatformKey { get; }
    Task<INativeDanmakuConnection> ConnectAsync(
        NativeDanmakuConnectRequest request,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken);
}
```

统一请求字段：

- `platformKey`
- `roomId`
- `roomNumber`
- `eid`
- `liveType`
- `liveSession`
- `cookieHeader`
- `displayName`

说明：

- `roomId`、`roomNumber`、`eid` 是兼容现有后台和历史数据的可选字段，native adapter 不能把它们作为新添加直播间的必填输入。
- 新添加的房间应优先只依赖平台类型和 `liveSession` Cookie。
- adapter 在开播预检阶段负责自动解析真实平台直播间标识。

统一事件字段：

- `eventId`
- `platform`
- `event`: `status`、`chat`、`gift`、`member`、`like`、`control`、`error`
- `status`: `connecting`、`living`、`stopped`、`disconnected`、`loginExpired`、`notStarted`
- `roomId`
- `platformRoomId`
- `messageId`
- `userId`
- `userName`
- `content`
- `giftName`
- `giftCount`
- `rawPayload`
- `createdAt`

正式直播页和娱乐模式只消费 `NativeDanmakuEvent`，不再知道平台协议细节。

### 5. Adapter 工厂与会话协调

新增统一协调层：

- `NativeDanmakuAdapterFactory`
- `NativeDanmakuSessionCoordinator`

职责：

- 根据 `RoomListItem.liveType` 找 adapter。
- 从 `liveSession` 解析 Cookie。
- 执行平台预检。
- 建立连接、重连、取消、心跳。
- 将平台事件转为正式直播页和娱乐模式需要的数据。

移除目标：

- 正式链路不再调用 `LocalDanmakuHelperManager.ensureRunning(...)`。
- 正式链路不再调用 `DanmakuLocalConnectionBuilder` 构造 `127.0.0.1` helper URL。
- `LiveRoomsView`、`FeatureViews`、`DanmakuCookieTestView` 不再出现平台协议解析代码。

## macOS 与 Windows 技术差异

| 能力 | macOS | Windows |
| --- | --- | --- |
| UI | SwiftUI/AppKit | WPF |
| 登录 WebView | `WKWebView` | WebView2 |
| Cookie 读取 | `WKHTTPCookieStore` | `CoreWebView2.CookieManager` |
| HTTP | `URLSession` | `HttpClient` |
| WebSocket | `URLSessionWebSocketTask` | `ClientWebSocket` |
| 安全存储 | Keychain | DPAPI / Windows Credential Locker |
| JS 签名执行 | JavaScriptCore | WebView2 hidden page 或纯 .NET JS engine |
| Protobuf | SwiftProtobuf | Google.Protobuf |
| gzip | zlib/Compression 封装 | `System.IO.Compression.GZipStream` |
| 打包资源 | SwiftPM resources / App bundle resources | WPF Resource / Content |

Windows Codex 注意：

- 不要照抄 macOS Swift 文件结构；按 `.NET 8 + WPF` 分层建目录。
- 优先补齐 `Core/Danmaku` 基础层，再补页面。
- WebView2 是 Cookie 采集的核心依赖，不是外部弹幕服务。
- 可以参考 macOS parser 和 adapter 行为，但事件字段和验收标准必须和本文档一致。

## 推荐目录结构

macOS：

```text
clients/macos/FastSortClientMac/Sources/FastSortClientMac/
  Services/Danmaku/
    NativeDanmakuAdapter.swift
    NativeDanmakuEvent.swift
    NativeDanmakuSessionCoordinator.swift
    NativeDanmakuAdapterFactory.swift
    Shared/
      GzipInflator.swift
      ProtobufFrameDecoder.swift
      SignatureProvider.swift
    Douyin/
      DouyinNativeDanmakuAdapter.swift
      DouyinRoomResolver.swift
      DouyinSignatureProvider.swift
      DouyinMessageMapper.swift
    Taobao/
      TaobaoNativeDanmakuAdapter.swift
      TaobaoRoomResolver.swift
      TaobaoMessageMapper.swift
    Kuaishou/
      KuaishouNativeDanmakuAdapter.swift
      KuaishouRoomResolver.swift
      KuaishouMessageMapper.swift
    WeChat/
      WeChatNativeDanmakuAdapter.swift
      WeChatMessageMapper.swift
    Xiaohongshu/
      XiaohongshuNativeDanmakuAdapter.swift
      XiaohongshuRoomResolver.swift
      XiaohongshuMessageMapper.swift
  Resources/Danmaku/
    douyin/sign.js
    douyin/douyin.proto
```

Windows：

```text
clients/windows/FastSort.Client.Windows/
  Core/Danmaku/
    NativeDanmakuAdapter.cs
    NativeDanmakuEvent.cs
    NativeDanmakuSessionCoordinator.cs
    NativeDanmakuAdapterFactory.cs
    Cookie/
      DanmakuCookieSessionParser.cs
      WebView2CookieCollector.cs
    Shared/
      GzipInflator.cs
      SignatureProvider.cs
    Douyin/
      DouyinNativeDanmakuAdapter.cs
      DouyinRoomResolver.cs
      DouyinSignatureProvider.cs
      DouyinMessageMapper.cs
    Taobao/
      TaobaoNativeDanmakuAdapter.cs
      TaobaoRoomResolver.cs
      TaobaoMessageMapper.cs
    Kuaishou/
      KuaishouNativeDanmakuAdapter.cs
      KuaishouRoomResolver.cs
      KuaishouMessageMapper.cs
    WeChat/
      WeChatNativeDanmakuAdapter.cs
      WeChatMessageMapper.cs
    Xiaohongshu/
      XiaohongshuNativeDanmakuAdapter.cs
      XiaohongshuRoomResolver.cs
      XiaohongshuMessageMapper.cs
  Views/
    DanmakuCookieTestView.xaml
    LiveRoomsView.xaml
  Resources/Danmaku/
    douyin/sign.js
    douyin/douyin.proto
```

## 平台改造方案

### 抖音 native adapter

优先级：P0。

原因：

- 抖音是当前最重要的直播链路。
- 娱乐模式也依赖抖音全量互动事件。
- `DouyinLiveWebFetcher-mainPython` 已有完整协议参考。

参考文件，仅作迁移参考，不作为运行依赖：

- `/Users/zcc/Documents/git-workspace-zcc/DouyinLiveWebFetcher-mainPython/liveMan.py`
- `/Users/zcc/Documents/git-workspace-zcc/DouyinLiveWebFetcher-mainPython/main.py`
- `/Users/zcc/Documents/git-workspace-zcc/DouyinLiveWebFetcher-mainPython/sign.js`
- `/Users/zcc/Documents/git-workspace-zcc/DouyinLiveWebFetcher-mainPython/protobuf/douyin.proto`

技术步骤：

1. 资源迁移
   - 把 `sign.js` 复制进客户端资源目录。
   - 把 `douyin.proto` 纳入客户端 proto 生成流程。
   - macOS 使用 SwiftProtobuf 生成 Swift 类型。
   - Windows 使用 Google.Protobuf 生成 C# 类型。

2. Cookie 和 room 解析
   - 从 `liveSession` 得到抖音 Cookie。
   - 如果 Cookie 缺 `msToken`，客户端生成临时 `msToken`。
   - 如果 Cookie 缺 `ttwid`，请求抖音工作台或直播相关入口时从响应 Cookie 补齐。
   - 不要求用户输入抖音号或 `live_id`；adapter 必须通过工作台 Cookie 解析当前账号正在直播的房间。如果平台工作台无法直接给出直播房间，再记录需要补充的工作台接口，而不是退回手填 live_id 作为正式方案。

3. 签名
   - 按 Python `generateSignature(wss)` 的参数顺序生成 MD5。
   - macOS 用 JavaScriptCore 调 `get_sign(md5)`。
   - Windows 优先用 WebView2 hidden page 或可用的 .NET JS engine 调 `get_sign(md5)`。
   - 不调用 Node，不启动 Python。

4. WSS 连接
   - 按 Python `_build_wss_url()` 构建 `wss://webcast5-ws-web-hl.douyin.com/webcast/im/push/v2/`。
   - 追加 `signature`。
   - Header 设置 `Cookie`、`User-Agent`、`Origin`、`Referer`。

5. 消息解析
   - 收二进制 frame。
   - 解析 `PushFrame`。
   - 如果 payload 是 gzip，先解压。
   - 解析 `Response`。
   - `needAck` 时回发 `PushFrame(payload_type: "ack", payload: internal_ext)`。
   - 解析 `WebcastChatMessage`、`WebcastGiftMessage`、`WebcastMemberMessage`、`WebcastLikeMessage`、`WebcastSocialMessage`、`WebcastControlMessage`。

6. 输出事件
   - `chat` 用于正式弹幕打印。
   - `gift`、`member`、`like`、`social` 用于娱乐模式。
   - `control.status == 3` 输出直播结束。

macOS 验收：

- 不启动 `DouyinLiveWebFetcher-mainPython`。
- `rg "8865|ws/events|DouyinLiveWebFetcher" clients/macos/FastSortClientMac/Sources` 不应命中正式链路。
- 抖音正式直播页可开播收弹幕。
- 娱乐模式可收礼物、进房、点赞。
- `swift build` 通过。

Windows 验收：

- 不依赖 Python、Node、uvicorn。
- `dotnet build clients/windows/FastSort.Client.Windows/FastSort.Client.Windows.csproj` 通过。
- WebView2 登录采集 Cookie 后，抖音 adapter 可连接并输出同一事件 schema。

### 淘宝 native adapter

优先级：P1。

原因：

- 当前 macOS 授权测试页已经存在部分 Swift 直连逻辑，可复用。
- 淘宝弹幕链路可以先用 HTTP polling 跑通，不一定需要平台 WebSocket。

参考文件，仅作迁移参考：

- `/Users/zcc/Documents/git-workspace-zcc/taobao_live/main.py`
- `/Users/zcc/Documents/git-workspace-zcc/taobao_live/poller.py`
- macOS `DanmakuCookieTestView` 中现有淘宝直连函数。

技术步骤：

1. Cookie
   - 从千牛工作台 WebView 采集 Cookie。
   - 保存到后台 `liveSession`。
   - 正式开播只从房间 `liveSession` 读取。

2. roomId 解析
   - 不要求用户提供 roomId 或直播分享链接。
   - 用千牛 Cookie 请求工作台接口或直播页，解析当前开播 roomId。
   - 支持 `wh_cid`、`liveplatform/{roomId}`、UUID roomId。

3. 弹幕获取
   - 以当前 Swift 直连逻辑为第一版：请求 `live/message/{roomId}/{start}/{end}?deviceId=...`。
   - 解析返回 JSON `payloads`。
   - base64 解 payload 后提取用户、内容、消息 ID。
   - 用 `endTime` 推进 polling 游标。

4. 输出事件
   - 输出 `chat`。
   - 淘宝礼物/互动如后续接口可解析，再补 `gift`、`member`。

macOS 验收：

- `LiveRoomsView` 不再调用 `LocalDanmakuHelperManager.shared.ensureRunning(.taobao)`。
- 不再请求 `http://127.0.0.1:8201/api/live/check_and_start`。
- 授权测试页和正式直播页都走 `TaobaoNativeDanmakuAdapter`。

Windows 验收：

- 新增千牛 WebView 登录和 Cookie 采集。
- 新增淘宝直播间添加/保存入口。
- 淘宝 adapter 可通过 `liveSession` Cookie 自动解析当前直播并输出弹幕。

### 快手 native adapter

优先级：P2。

原因：

- 当前 macOS 授权测试页已经有一部分快手直连逻辑。
- 快手需要 WebSocket token、enter room 二进制包、heartbeat，复杂度高于淘宝。

参考文件，仅作迁移参考：

- `/Users/zcc/Documents/git-workspace-zcc/kuaishou_live/server.py`
- `/Users/zcc/Documents/git-workspace-zcc/kuaishou_live/kuaishou_api.py`
- macOS `DanmakuCookieTestView` 中现有快手直连函数。

技术步骤：

1. Cookie
   - 从快手工作台 WebView 采集 Cookie。
   - 保存到后台 `liveSession`。
   - Web 请求必须带 `Cookie`，必要时从 Cookie 中提取 `kwfv1` 设置 `Kww` header。

2. 房间解析
   - 不要求用户输入快手房间号或 `live.kuaishou.com/u/{id}`。
   - 用快手工作台 Cookie 请求工作台或直播相关接口，自动定位当前账号直播间；必要时再请求直播页提取 `playList`。
   - 解析 `liveStreamId`、主播名称、开播状态。

3. WebSocket 信息
   - 请求 `live_api/liveroom/websocketinfo?caver=2&liveStreamId=...`。
   - 解析 token 和 WebSocket URL 列表。

4. WebSocket 协议
   - 建立平台 WebSocket。
   - 发送 enter room 二进制消息。
   - 定时发送 heartbeat。
   - 解析服务端二进制消息。
   - 当前 Swift 里已有手写 protobuf/varint 逻辑可作为第一版；后续建议固化 proto。

5. 输出事件
   - 输出 `chat`、`gift`、`member`、`like`、`control`。

macOS 验收：

- `LiveRoomsView` 不再调用 `LocalDanmakuHelperManager.shared.ensureRunning(.kuaishou)`。
- 不再连接 `127.0.0.1:8301/ks-ws/...`。
- 快手正式直播页从 `liveSession` Cookie 直接解析 token 并连平台 WebSocket。

Windows 验收：

- 实现相同 headers、room 解析、websocketinfo 请求、二进制协议解析。
- 不依赖 `kuaishou_live`。

### 视频号 native adapter

优先级：P3。

原因：

- 当前已明确 `liveSession` 中关键字段是 `sessionid`、`wxuin`。
- 需要把 `wx_live` 中的连接和消息解析迁入客户端。

参考文件，仅作迁移参考：

- `/Users/zcc/Documents/git-workspace-zcc/wx_live/wx_live.py`
- `/Users/zcc/Documents/git-workspace-zcc/wx_live/live_fetcher.py`

技术步骤：

1. Cookie/会话
   - WebView 登录视频号工作台。
   - 采集并保存包含 `sessionid`、`wxuin` 的 `liveSession`。
   - `DanmakuCookieSessionParser` 必须能从 raw Cookie、JSON 或 map 中解析两者。

2. 直播状态
   - 迁移 `wx_live` 中检查直播状态的 HTTP 请求。
   - 不要求用户输入视频号房间 ID；adapter 通过 `sessionid/wxuin` 和工作台接口解析当前直播状态。
   - 需要确认是否必须携带额外 token、finder id 或设备参数。

3. 消息获取
   - 迁移 `wx_live` 当前使用的消息拉取或 WebSocket 逻辑。
   - 如果协议不是标准 WebSocket，需要单独封装为 polling adapter。

4. 输出事件
   - 先保证 `chat`。
   - 再补礼物、进入、点赞等扩展事件。

macOS 验收：

- 不再调用 `LocalDanmakuHelperManager.shared.ensureRunning(.wechat)`。
- 不再连接 `127.0.0.1:8000/wx-ws`。
- 视频号正式直播页用 `liveSession` 的 `sessionid/wxuin` 直接收弹幕。

Windows 验收：

- WebView2 可扫码登录并采集必要 Cookie。
- adapter 直接连接视频号消息源。

### 小红书 native adapter

优先级：P4，但需要先做协议调研 spike。

原因：

- 当前正确方向是 ark 工作台 Cookie。
- 旧登录态方案不能作为主方案。
- 现有 helper 不能直接证明 ark Cookie 到弹幕链路完整可用。

参考边界：

- 可以参考 `/Users/zcc/Documents/git-workspace-zcc/xhs_live` 的历史实现，但不能沿用旧登录态假设。
- 不能回到 redlive/旧登录态主链路。

技术步骤：

1. Cookie
   - 从 `ark.xiaohongshu.com` 工作台登录页采集 Cookie。
   - 必须识别 `access-token-ark.xiaohongshu.com` 等 ark 登录态字段。
   - 保存到后台 `liveSession`。

2. 协议调研
   - 用 ark Cookie 请求工作台直播相关接口。
   - 找到当前直播信息：直播状态、roomId/sessionId、主播/店铺标识。
   - 找到弹幕消息来源：WebSocket、SSE 或 polling。
   - 记录必要 headers、csrf/token、签名字段。

3. adapter
   - 实现 `XiaohongshuRoomResolver`。
   - 实现弹幕连接和消息解析。
   - 输出统一 `chat`、`gift`、`member`、`like`、`control`。

验收：

- 使用 ark 工作台 Cookie 可从客户端直接解析当前直播并收弹幕。
- 正式直播页不调用任何旧小红书 helper。
- 小红书失败提示只说明 ark adapter 缺失或登录态失效，不出现旧方案文案。

### TikTok / Shopee 后续 adapter

优先级：P5。

前置条件：

- 迅拣后端必须先确认正式 `liveType`。
- 房间接口必须明确 `liveSession` 格式；`roomNumber` 只能作为历史兼容字段，不能作为新增直播间必填参数。
- 不能用弹幕捕手 `platformId` 代替迅拣后端枚举。

实现原则：

- 仍然使用 native adapter。
- 不新增外部 Python helper。
- TikTok 如果依赖第三方签名服务或 API key，必须在产品层确认是否允许。
- TikTok/Shopee 也必须通过工作台扫码登录采集 Cookie 后由 adapter 自动解析直播间，不把 `unique_id`、`session_id`、短链或分享链接作为最终用户必填项。

## 分阶段实施计划

### 阶段 A：共用 native adapter 基础层

状态：待开始。

macOS 任务：

- 新增 `NativeDanmakuEvent`、`NativeDanmakuConnectRequest`、`NativeDanmakuAdapter`、`NativeDanmakuConnection`。
- 新增 `NativeDanmakuAdapterFactory` 和 `NativeDanmakuSessionCoordinator`。
- 把 `LiveRoomsView` 和 `FeatureViews` 的平台连接入口改成调用 coordinator。
- 暂时允许 adapter 内部调用旧 helper，但页面层不能再知道 helper。

Windows 任务：

- 新增 `Core/Danmaku` 基础类型。
- 新增直播间服务 DTO：房间、`liveType`、`roomNumber`、`eid`、`liveSession`，其中 `roomNumber/eid` 只用于兼容历史数据。
- 新增 `LiveRooms` 路由和基础页面。
- 新增授权测试页路由和 WebView2 骨架。

验收：

- 页面层只依赖 coordinator。
- 平台事件 schema 在 macOS/Windows 文档和代码中一致。

### 阶段 B：抖音 native adapter

状态：待开始。

任务：

- 迁移 `sign.js` 和 `douyin.proto`。
- 实现抖音 room resolver、signature provider、WSS client、protobuf decoder、event mapper。
- 正式直播页和娱乐模式切到抖音 native adapter。
- 移除抖音正式链路对 `8865` 的依赖。

验收：

- 不启动 `DouyinLiveWebFetcher-mainPython` 也能收抖音弹幕。
- 娱乐模式能展示礼物/互动事件。

### 阶段 C：淘宝 native adapter

状态：待开始。

任务：

- 把 macOS 授权测试页中的淘宝直连逻辑下沉到 adapter。
- Windows 实现同等逻辑。
- 正式直播页切到 `TaobaoNativeDanmakuAdapter`。
- 移除 `taobao_live` 启动和 `8201` 连接。

验收：

- 淘宝 Cookie 保存后，正式开播从 `liveSession` 取 Cookie 并收弹幕。

### 阶段 D：快手 native adapter

状态：待开始。

任务：

- 把快手 room/liveStreamId/token 解析下沉。
- 把 enter room、heartbeat、二进制消息解析下沉。
- Windows 实现同等协议。
- 移除 `kuaishou_live` 启动和 `8301` 连接。

验收：

- 快手正式直播页不启动 helper 也能收弹幕。

### 阶段 E：视频号 native adapter

状态：待开始。

任务：

- 从 `wx_live` 提取协议。
- 实现 sessionid/wxuin 直连消息源。
- Windows 实现 WebView2 Cookie 采集和同等 adapter。
- 移除 `wx_live` 启动和 `8000` 连接。

验收：

- 视频号正式直播页不启动 helper 也能收弹幕。

### 阶段 F：小红书 ark native adapter

状态：待开始。

任务：

- 完成 ark Cookie 到直播信息和弹幕源的协议调研。
- 实现 XHS native adapter。
- 接入正式直播页。

验收：

- 小红书使用 ark 工作台 Cookie 完成 native 弹幕连接。

### 阶段 G：删除 helper 过渡层

状态：待开始。

任务：

- 删除或隔离 `LocalDanmakuHelperManager` 的正式链路调用。
- 删除正式链路中的 `DanmakuLocalConnectionBuilder` 依赖。
- 删除所有 `127.0.0.1` helper 端口说明和测试入口。
- 打包时不包含 Python、venv、uvicorn、Node。

验收：

- `rg "LocalDanmakuHelperManager|DanmakuLocalConnectionBuilder|127.0.0.1|8201|8301|8000|8865" clients/macos/FastSortClientMac/Sources` 不命中正式链路。
- Windows 项目不包含 Python helper 启动代码。
- 用户只启动一个 App 即可使用。

## Windows Codex 实施顺序

另一台 Windows 电脑上的 Codex 应按以下顺序执行：

1. 先读本文档，确认最终目标是不依赖外部 Python 服务。
2. 读 `clients/windows/FastSort.Client.Windows/README.md`，确认 WPF + .NET 8 环境。
3. 补 `AppRoute.DanmakuCookieTest` 和 `AppRoute.LiveRooms`。
4. 增加 WebView2 依赖，创建授权测试页。
5. 创建 `Core/Danmaku` 基础类型和 `DanmakuCookieSessionParser.cs`。
6. 先实现抖音 native adapter，因为抖音有 `sign.js` 和 `douyin.proto` 可迁移。
7. 再实现淘宝、快手、视频号。
8. 小红书先做 ark 协议调研，不要沿用旧登录态主方案。
9. 每个平台完成后运行 `dotnet build`，并用同一事件 schema 验证 UI。

Windows 不应做的事：

- 不要新增 Python 进程启动器。
- 不要把 macOS 的 `LocalDanmakuHelperManager` 思路复制到 Windows。
- 不要依赖 `/taobao_live`、`/kuaishou_live`、`/wx_live`、`/xhs_live`、`/DouyinLiveWebFetcher-mainPython` 的运行时服务。
- 不要把 TikTok/Shopee 接入正式页，除非后端 `liveType` 已明确。

## 验证清单

每个平台 native adapter 完成后都必须验证：

- Cookie 采集：登录后能采集平台 Cookie。
- Cookie 保存：保存到后台后，重新打开客户端仍能从房间 `liveSession` 读取。
- 添加直播间：所有平台都通过工作台扫码/账号登录采集 Cookie 完成，不出现手填 Cookie、抖音号、roomId、unique_id、session_id、短链或分享链接的必填流程。
- 开播预检：Cookie 缺失、登录过期、房间未开播有明确错误。
- 弹幕连接：不启动任何外部 helper，客户端直接连接平台消息源。
- 消息解析：至少输出 `chat`，平台支持时输出 `gift`、`member`、`like`、`control`。
- 断线处理：断线能回到 UI，必要时可重连。
- 直播结束：平台结束状态能停止连接。
- 正式页：弹幕进入现有打印队列。
- 测试页：弹幕显示测试消息。
- 娱乐页：抖音互动事件统计正常。

构建验收：

- macOS：`swift build`。
- Windows：`dotnet build clients/windows/FastSort.Client.Windows/FastSort.Client.Windows.csproj`。

静态扫描验收：

```bash
rg -n "LocalDanmakuHelperManager|DanmakuLocalConnectionBuilder|127\\.0\\.0\\.1|8201|8301|8000|8865|uvicorn|python|\\.venv" clients/macos/FastSortClientMac/Sources clients/windows/FastSort.Client.Windows
```

最终正式链路不应命中 helper 启动、helper 端口和 Python 运行时依赖。测试文档中可以保留历史参考说明，但必须标记为“迁移参考，不是运行依赖”。
