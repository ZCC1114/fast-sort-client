# 直播授权测试交接文档

更新日期：2026-07-08

本文档用于换 Codex 窗口继续工作。它只描述当前“直播授权测试页”已经跑通的内容、踩坑和后续工作，不替代整体 native adapter 计划。

## 当前结论

macOS 客户端的 `直播授权测试` 页面当前已经完成一个可验证闭环：

1. 客户端打开平台工作台登录页。
2. 用户在工作台扫码/登录。
3. 客户端从本机 WebKit 会话采集 Cookie。
4. 客户端用 Cookie 和工作台接口/捕获响应解析当前直播。
5. 客户端本机 native adapter 拉取弹幕并展示。
6. 测试页默认不会自动上传 Cookie 到后端。

已由用户实机验证能在直播授权测试页拿到弹幕的平台：

| 平台 | 平台 key | 当前状态 | 当前主要链路 |
| --- | --- | --- | --- |
| 抖音工作台 | `fxg` | 可用 | 登录抖店工作台，进入直播中控后通过工作台评论接口轮询弹幕 |
| 小红书工作台 | `xhs` | 可用 | 登录 ark 工作台，优先捕获/解析新直播中控接口和弹幕响应，不再依赖 redlive 旧页面作为主路径 |
| 视频号工作台 | `ec` | 可用 | 登录视频号助手，使用 `sessionid/wxuin`、`auth_data/finderUsername` 和视频号助手 native 请求链路拉取弹幕 |

存在但未充分验收的平台：

| 平台 | 平台 key | 当前说明 |
| --- | --- | --- |
| 抖音达人工作台 | `fxg_kol` | 配置和 adapter 入口存在，和抖音同属 `douyin` adapter；仍需要达人账号单独验证 |
| 千牛工作台 | `tb` | 有 native adapter 迁移基础，但本轮未作为已跑通平台确认 |
| 快手工作台 | `ks` | 有 native adapter 迁移基础，但本轮未作为已跑通平台确认 |

## 代码入口

macOS 直播授权测试主文件：

```text
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/DanmakuCookieTestView.swift
```

平台配置：

```text
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/DanmakuPlatformRegistry.swift
```

Cookie/liveSession 解析：

```text
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/DanmakuCookieSessionParser.swift
```

native adapter 入口：

```text
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/Danmaku/NativeDanmakuAdapterFactory.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/Danmaku/NativeDanmakuSessionCoordinator.swift
```

平台 adapter 重点文件：

```text
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/Danmaku/Douyin/DouyinNativeDanmakuAdapter.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/Danmaku/Xiaohongshu/XiaohongshuNativeDanmakuAdapter.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/Danmaku/Wechat/WechatNativeDanmakuAdapter.swift
```

Windows 对应页面和 ViewModel：

```text
clients/windows/FastSort.Client.Windows/Views/DanmakuCookieTestView.xaml
clients/windows/FastSort.Client.Windows/Views/DanmakuCookieTestView.xaml.cs
clients/windows/FastSort.Client.Windows/ViewModels/DanmakuCookieTestViewModel.cs
clients/windows/FastSort.Client.Windows/Core/Danmaku
```

## 当前页面行为

### Cookie 采集

- 按平台配置打开登录页。
- URL 命中平台成功页后会延迟自动采集 Cookie。
- 也可以手动点击“立即采集 Cookie”。
- Cookie 默认脱敏展示。
- “显示完整 Cookie 值”只用于本机测试，不要提交、截图或发聊天。
- 测试页不会自动上传 Cookie。

### 平台登录窗口

- macOS 当前支持平台登录独立窗口。
- 主页面保留一个占位区，提示“平台登录页将在独立窗口打开”。
- 关闭平台窗口不能影响主客户端；这是 Windows 复刻时必须重点回归的点。
- 之前视频号测试阶段出现过“关闭平台后台弹窗导致主客户端闪退”的问题，Windows 侧尤其要确认独立 WebView2 窗口生命周期不会带崩主窗口。

### 工作台响应捕获

`DanmakuCookieTestView.swift` 会注入脚本，捕获工作台页面中的 XHR/fetch 响应，过滤直播、评论、中控相关 payload。

当前捕获缓存要点：

- `capturedWorkbenchPayloads` 只保留近期 payload。
- `capturedWorkbenchPayloadSignatures` 防止重复。
- `capturedDouyinRoomInput` 缓存抖音中控解析出的直播标识。
- `capturedXiaohongshuRoomInput` 缓存小红书 ark 中控解析出的直播标识。

重要：诊断复制功能必须限制 payload 数量和大小，且不要在主线程拼接巨大文本。之前点击“复制抖音捕获诊断”出现过客户端卡死，后续如果继续保留诊断按钮，需要做：

- payload 数量上限。
- 单条 payload 长度上限。
- 总文本大小上限。
- 后台线程组装文本。
- 剪贴板写入前脱敏 Cookie/token。

## 平台细节

### 抖音工作台

当前可用路径：

1. 打开 `https://fxg.jinritemai.com/login/common`。
2. 登录后进入抖店工作台。
3. 进入直播中控页。
4. 页面捕获中控接口响应，尽量解析 `room_id` / `live_id`。
5. 连接弹幕时优先使用工作台评论接口轮询。
6. 成功后弹幕展示中会出现来自 `douyin-workbench` 的评论事件。

关键注意点：

- 不要要求用户输入抖音号。
- 不要要求用户输入直播间号作为测试页主路径。
- 抖音 WSS/protobuf/sign.js 仍然存在，但当前测试页验证成功的是“抖店中控评论轮询 adapter 可用版”。
- 抖音工作台有 `fxg` 和 `fxg_kol` 两个入口；`fxg_kol` 仍需达人账号单独回归。
- 如果未解析到直播标识，先等中控页刷新接口或重新采集 Cookie，不要马上改回旧手填流程。

已踩坑：

- 只看页面 DOM 很难拿到稳定直播 ID，需要捕获中控接口响应。
- 中控页看到评论不等于 adapter 已拿到接口响应；需要捕获 payload 或使用工作台评论接口兜底。
- 诊断复制可能因为 payload 过大卡死。

### 小红书工作台

当前可用路径：

1. 打开 `https://customer.xiaohongshu.com/login?service=https://ark.xiaohongshu.com/app-system/home`。
2. 登录 ark 工作台。
3. 进入新后台的“直播中控”。
4. 捕获 ark 中控直播标识和弹幕响应。
5. 连接弹幕时优先使用 ark 中控捕获流；必要时再尝试 native adapter。

关键注意点：

- 不要再把 `redlive.xiaohongshu.com/live_plan` 当主方案。
- 小红书旧直播助手会提示迁移/停服，实际还能打开，但不是最终目标。
- 当前正确方向是 ark 工作台 Cookie + 新直播中控接口。
- 如果没有捕获到 ark token 或直播标识，需要先打开直播中控并重新采集 Cookie。

已踩坑：

- 早期只用 ark 首页 Cookie 连接会提示“当前账号未开播或无法解析当前直播”。
- 旧 redlive 页面能临时收到弹幕，但方向不对，会影响后续长期稳定性。

### 视频号工作台

当前可用路径：

1. 打开 `https://channels.weixin.qq.com/login.html`。
2. 登录视频号助手。
3. Cookie 中至少要有 `sessionid` / `wxuin`。
4. 页面或接口响应中可解析 `auth_data` / `finderUsername`。
5. native adapter 通过视频号助手接口检查直播并拉取消息。

关键注意点：

- 完全体不应该要求用户必须手动点进直播管理页。
- 如果在首页没有捕获评论接口，应走 `sessionid/wxuin` native 请求链路。
- 如果接口返回 `300800` 或 `request failed`，需要看请求体、referer、finderUsername、live 信息是否正确。
- 只捕获到 `sessionid/wxuin` 不代表能拉弹幕，还要能解析当前视频号身份和直播信息。

已踩坑：

- 早期只有在后台窗口点进直播管理页才能复用捕获评论响应，不符合最终目标。
- 后来补了 native 请求链路后，首页登录态也能继续拉取。
- 独立平台窗口关闭时曾导致主客户端闪退，需要持续回归。

## 当前不要误判的地方

### 直播授权测试页可用，不等于正式直播端全部完成

当前已验证的是“直播授权测试页”：

- 登录工作台。
- 采集 Cookie。
- 连接弹幕。
- 展示弹幕。

正式直播端仍要单独确认：

- Cookie 保存到后端房间 `liveSession`。
- 正式开播只从后台房间 `liveSession` 取 Cookie。
- 不依赖授权测试页的临时 WebView 状态、捕获缓存或当前页面。
- 打印和弹幕事件联动不被破坏。

### 后端 liveSession 字段合同

当前已验证的抖音、小红书、视频号三个平台，后端原则上可以继续只用一个字段保存授权信息，建议沿用现有 `liveSession`。但不要把它长期设计成只保存裸 Cookie 字符串，而应把它当成平台无关的 opaque session JSON，由客户端负责写入和解析。

建议 `liveSession` 保存为 JSON 字符串，至少包含：

```json
{
  "version": 1,
  "platform": "xhs",
  "cookieHeader": "a=...; b=...",
  "cookies": [],
  "captured": {
    "liveId": "...",
    "roomId": "...",
    "finderUsername": "..."
  },
  "savedAt": "2026-07-08T00:00:00Z"
}
```

后续改造注意事项：

- 后端只需要保存/返回一个 `liveSession` 字段，不需要为抖音、小红书、视频号分别建不同 Cookie 字段。
- 正式连接弹幕时，客户端必须同时拿到房间的 `liveType`，用 `liveType` 选择对应 native adapter。
- `liveSession` 里至少要有 `cookieHeader`，或保存能还原成 Cookie header 的 cookie item 列表。
- Cookie 是再次连接的核心，但为了稳定，建议把当次解析到的 `roomId`、`liveId`、`finderUsername` 等辅助信息也放进同一个 `liveSession` JSON。
- adapter 不应依赖测试页 WebView 的临时内存状态；正式开播只能依赖 `queryRoomsByUserId` 返回的 `liveType` 和 `liveSession`。
- Cookie 会过期，连接失败时要能提示“授权失效，请重新登录采集”，不要静默回退到外部 Python 服务或手填直播间号。

三个已验证平台的字段建议：

| 平台 | 只存 Cookie 是否够 | 建议保存内容 |
| --- | --- | --- |
| 抖音工作台 | 基本够，但不够稳 | `cookieHeader` + 中控解析到的 `room_id` / `live_id` |
| 小红书工作台 | Cookie 是核心，但 ark 中控信息更稳 | `cookieHeader` + ark 捕获到的直播标识/token 摘要 |
| 视频号工作台 | 不建议只存 Cookie | `cookieHeader` + `sessionid` / `wxuin` 可还原 Cookie + `finderUsername` / `auth_data` 解析结果 |

### 测试页不应该承担生产保存逻辑

为了先跑通平台弹幕，测试页已经弱化/去掉“保存到迅拣直播间”这类测试入口。后续正式保存应在 `直播端` 或专门授权保存流程里做，不要把测试页临时状态当生产合同。

### 不要引入旧 Python 服务

目标仍然是 native adapter：

- 不启动 `/taobao_live`。
- 不启动 `/kuaishou_live`。
- 不启动 `/wx_live`。
- 不启动 `/xhs_live`。
- 不启动 `/DouyinLiveWebFetcher-mainPython`。

Python 服务只能作为协议参考，不作为运行依赖。

### 不要提交敏感数据

不要提交：

- Cookie。
- token。
- HAR 原始文件。
- 登录账号。
- 工作台接口完整响应中包含的敏感字段。

需要抓包时放到未提交目录，例如：

```text
local-captures/douyin/
local-captures/wechat/
local-captures/xiaohongshu/
```

## 接下来要做

### 1. Windows 复刻直播授权测试页

Windows 侧要以 macOS 当前页面和截图为准：

```text
docs/windows-macos-ui-business-parity-handoff.md
docs/parity-screenshots/macos/danmaku-auth.png
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/DanmakuCookieTestView.swift
```

必须复刻：

- 平台列表。
- 当前配置。
- 独立登录窗口占位和状态。
- Cookie 采集结果表。
- 弹幕展示区。
- 连接/断开弹幕流程。
- 抖音、小红书、视频号已跑通的 native adapter 行为。

重点验收：

- 关闭 WebView2 独立登录窗口，主客户端不闪退。
- 抖音工作台登录后能收到评论。
- 小红书 ark 直播中控登录后能收到评论。
- 视频号助手首页登录态能拉到直播评论，不强制要求点进直播管理页。

### 2. 正式直播端接入 liveSession

后续要把测试页已验证的能力迁入正式流程：

1. 直播端打开平台工作台登录窗口。
2. 采集 Cookie。
3. 将 Cookie 和平台辅助信息打包成 `liveSession` JSON，保存到后台房间。
4. 断开测试页临时 WebView 状态依赖。
5. 正式开播时从 `queryRoomsByUserId` 返回的房间 `liveType` + `liveSession` 恢复 adapter 输入。
6. 使用 native adapter 连接弹幕。

### 3. 统一重连和生命周期机制

目前测试页优先证明“能连上、能收到弹幕”。重连机制还需要后续统一补：

- 网络错误重试。
- 平台登录过期提示。
- 定时心跳或轮询错误恢复。
- 弹幕连接停止时清理 task/timer/WebSocket。
- 页面切换或窗口关闭时释放 WebView/adapter。
- 去重重复弹幕。

### 4. 继续平台覆盖

下一批平台：

- 淘宝千牛：确认当前直播 roomId 解析和弹幕轮询接口。
- 快手工作台：确认 Cookie、websocketinfo、protobuf/二进制帧。
- 抖音达人 `fxg_kol`：用达人账号单独验证中控轮询接口。

## 新窗口继续指令

换新 Codex 窗口后，可以直接发：

```text
你现在在 fast-sort-client 仓库根目录工作。先阅读 docs/live-auth-test-handoff.md，再阅读 docs/windows-macos-ui-business-parity-handoff.md。

当前已知：macOS 直播授权测试页的抖音工作台、小红书 ark、视频号助手已经能登录后台、采集 Cookie，并在测试页连接弹幕。不要回退到外部 Python 服务，不要恢复手填抖音号/直播间号作为主路径。

接下来优先做 Windows 直播授权测试页复刻：
1. 对照 docs/parity-screenshots/macos/danmaku-auth.png 和 macOS DanmakuCookieTestView.swift。
2. 保留 Windows WebView2 Cookie 采集。
3. 复刻独立登录窗口，关闭窗口不能导致主应用闪退。
4. 确保抖音、小红书、视频号 native adapter 行为和 macOS 测试页一致。
5. 每完成一阶段运行 dotnet build clients/windows/FastSort.Client.Windows/FastSort.Client.Windows.csproj。

先输出差异对照表，然后直接开始实现。
```
