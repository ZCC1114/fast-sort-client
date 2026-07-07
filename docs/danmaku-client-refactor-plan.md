# 迅拣客户端本机弹幕改造执行计划

更新日期：2026-07-07

## 目标

把迅拣 macOS 客户端的弹幕链路改成清晰、可维护、可逐平台落地的客户端架构。最终正式目标已调整为 native adapter，详见 `docs/native-danmaku-adapter-plan.md`：

1. 平台登录和 Cookie 获取在客户端完成。
2. Cookie 保存到迅拣后台，正式开播时再从房间 `liveSession` 取回。
3. 弹幕连接在客户端内置 native adapter 中完成。
4. 后台只负责账号、房间、Cookie、模板、策略、直播记录和日志，不作为默认弹幕中转服务。
5. 外部 Python helper 只作为协议迁移参考，不作为最终运行依赖。
6. 所有平台添加直播间都通过客户端打开平台后台工作台登录页扫码/账号登录后保存 Cookie，不要求用户手动输入 Cookie、抖音号、roomId、unique_id、session_id、短链或分享链接。

## 不纳入范围

- 不再分析或依赖 `/Users/zcc/Documents/git-workspace-zcc/BarrageGrab`。
- 不把弹幕捕手远程 SaaS 页面嵌入迅拣客户端。
- 不把弹幕捕手的 `platformId` 当作迅拣后端 `liveType` 使用。
- 不在没有后端正式枚举的情况下，把 TikTok、Shopee 等平台强行接入正式直播页。
- 不把 `/taobao_live`、`/kuaishou_live`、`/wx_live`、`/xhs_live`、`/DouyinLiveWebFetcher-mainPython` 作为正式客户端运行依赖。

## 当前状态

已完成：

- `DanmakuPlatformRegistry` 已抽到服务层，集中维护平台登录 URL、Cookie 域、成功页匹配、本地 adapter 类型和默认本机端口。
- `DanmakuWebAuthSessionStore` 已抽到服务层，授权测试页已从临时 `WKWebsiteDataStore.nonPersistent()` 切到持久化 `.default()`。
- `LiveRoomsView` 的平台识别已改为调用 `DanmakuPlatformRegistry.clientPlatformKey(forLiveType:)`。
- `DanmakuLocalConnectionBuilder` 已抽到服务层，正式直播页和授权测试页已开始复用本机 URL/端口构造。
- `DanmakuWebSocketSession` 已抽到服务层，正式直播页和授权测试页的本机桥接连接已复用统一 WebSocket 会话循环。
- `DanmakuSocketMessageParser` 已抽到服务层，正式直播页、授权测试页、娱乐弹幕页已复用统一平台状态文本解析。
- `DanmakuCookieSessionParser` 已抽到服务层，正式直播页和娱乐弹幕页已复用统一 `liveSession` Cookie 解析。
- `FeatureViews` 的娱乐弹幕连接已迁移到 `DanmakuWebSocketSession`。
- Shopee 授权测试桥接 URL 默认端口已统一到 `8001`，避免和视频号 `8000` 冲突。
- 小红书说明已统一为“当前缺少本机 adapter，需要用 ark 工作台 Cookie 补齐客户端侧解析直播和拉取弹幕链路”。
- `swift build` 已通过。

当前主要问题：

- 消息去重和具体业务响应仍留在各页面内：正式页负责打印队列，测试页负责测试输出，娱乐页负责互动统计。
- `DanmakuCookieTestView` 仍包含淘宝、快手等平台 adapter 试验代码，后续可以继续按平台下沉。
- 小红书本机 adapter 尚未实现，当前只能完成 ark 工作台 Cookie 采集和保存。
- 现有本机 helper 连接只是过渡实现；下一阶段要按 `docs/native-danmaku-adapter-plan.md` 迁移为 macOS/Windows native adapter。

## 改造顺序

### 阶段 1：平台和授权边界

状态：已完成。

目标：

- 把弹幕捕手平台注册表抽成迅拣自己的 `DanmakuPlatformRegistry`。
- 把 WebKit 授权会话抽成 `DanmakuWebAuthSessionStore`。
- 修正小红书架构假设。

验收：

- 授权测试页和正式直播页不再各自定义平台基础信息。
- 关闭再打开客户端后，平台登录态可以通过默认 WebKit store 延续。
- `swift build` 通过。

### 阶段 2：本机连接配置和 URL 构造

状态：已完成。

目标：

- 新增统一的本机连接 builder。
- 集中处理本机端口读取、HTTP URL、WebSocket URL、外部 wsPath 映射回本机、抖音/TikTok/Shopee/视频号桥接 URL。
- 修正 Shopee 测试连接默认端口，避免和视频号 `8000` 冲突。

验收：

- `LiveRoomsView` 不再自己实现端口读取和通用 URL 构造。
- `DanmakuCookieTestView` 的本机桥接 URL 复用同一套 builder。
- `swift build` 通过。

### 阶段 3：本机连接管理器

状态：已完成。

目标：

- 新增 `DanmakuWebSocketSession`，统一管理 `URLSessionWebSocketTask`、接收循环、ping 和取消。
- 新增 `DanmakuSocketMessageParser`，统一处理平台状态文本。
- 正式直播页和授权测试页只提供平台、房间、Cookie 和输入参数，不直接管理 socket 生命周期。

验收：

- `LiveRoomsView.connectSocket` 和 `DanmakuCookieTestView.runBridgeWebSocket` 的底层接收循环已收敛到 `DanmakuWebSocketSession`。
- `FeatureViews` 娱乐弹幕连接已收敛到 `DanmakuWebSocketSession`。
- 平台返回的 `LIVING`、`CONNECTING`、`STOPPED`、`pong` 等状态由 `DanmakuSocketMessageParser` 统一解析。
- 正式直播页、授权测试页、娱乐弹幕页都不再直接创建或持有裸 `URLSessionWebSocketTask`。
- `swift build` 通过。

### 阶段 4：Cookie 保存和读取闭环

状态：基础完成。

目标：

- 授权测试页采集到 Cookie 后，按平台保存到迅拣后台。
- 正式开播时只从后台房间 `liveSession` 取 Cookie，不依赖测试页临时状态。
- 统一 `liveSession` 的解析逻辑，兼容原始 Cookie 字符串、JSON 字符串、cookie map、cookie item array。

验收：

- `DanmakuCookieSessionParser` 已统一解析原始 Cookie 字符串、JSON Cookie 字段、cookie map、cookie item array。
- 淘宝、小红书、快手、视频号可从 `liveSession` 解析出 native adapter 所需 Cookie。
- 保存成功后的提示只说明迅拣自己的后续链路，不再引用弹幕捕手 SaaS。
- `swift build` 通过。

### 阶段 5：native adapter 基础层

状态：待开始。

目标：

- 建立 macOS/Windows 共用概念模型：`NativeDanmakuAdapter`、`NativeDanmakuEvent`、`NativeDanmakuSessionCoordinator`、`NativeDanmakuAdapterFactory`。
- 正式直播页、授权测试页、娱乐模式只依赖 coordinator，不再直接连接 helper 或解析平台协议。
- 添加直播间统一为平台工作台登录和 Cookie 保存流程，技术房间标识由 adapter 在开播预检阶段解析。
- Windows 补齐 `Core/Danmaku`、授权测试页和直播间页的 native adapter 接入口。

验收：

- 页面层不再新增平台协议代码。
- macOS/Windows 事件 schema 一致。
- `swift build` 和 Windows `dotnet build` 通过。

### 阶段 6：逐平台 native adapter 落地

状态：待开始。

优先级：

1. 抖音：`sign.js` + protobuf + WSS + ack/heartbeat，替换 `DouyinLiveWebFetcher-mainPython`。
2. 淘宝：千牛 Cookie -> 当前直播 roomId -> impaas/polling 弹幕，替换 `taobao_live`。
3. 快手：Cookie -> liveStreamId/token -> 平台 WebSocket，替换 `kuaishou_live`。
4. 视频号：sessionid/wxuin -> 平台消息源，替换 `wx_live`。
5. 小红书：ark 工作台 Cookie -> 当前直播信息 -> 弹幕拉取，不能继续依赖旧登录态 Cookie 假设。
6. TikTok/Shopee：等迅拣后端正式平台枚举确认后再规划 native adapter。

验收：

- 每个平台至少有一个可复现的测试账号和直播间。
- 每个平台的 adapter 输出统一消息字段：用户、内容、消息 ID、房间 ID、平台状态。
- 弹幕消息不经过迅拣云端 WebSocket 中转，也不经过本机 Python helper。

### 阶段 7：正式直播页接入

状态：待开始。

目标：

- 正式开播按钮按平台执行本机预检。
- Cookie 缺失、登录过期、房间未开播、平台协议失败时给出明确错误。
- 弹幕展示、自动打印、手动打印继续复用现有业务逻辑。

验收：

- 开播失败不创建无效直播记录，或能在失败后自动回滚/结束。
- 弹幕连接成功后才进入自动打印队列。
- 断线和直播结束状态能回到 UI。

### 阶段 8：删除 helper 过渡层

状态：待开始。

目标：

- 删除正式链路对 `LocalDanmakuHelperManager`、`DanmakuLocalConnectionBuilder`、`127.0.0.1` helper 端口的依赖。
- 打包产物不包含 Python、venv、uvicorn、Node 运行时依赖。
- 文档中只保留 helper 作为协议迁移参考的历史说明。

验收：

- 静态扫描正式源码不再命中 helper 启动和 helper 端口。
- 用户只启动一个客户端 App 即可完成登录、保存 Cookie、开播、收弹幕、打印。

### 阶段 9：验证和发布

状态：待开始。

目标：

- 为每个平台补一份手动验证脚本。
- 打包前跑 `swift build`。
- 记录各平台账号、Cookie、工作台登录状态、native adapter 自动解析出的直播间标识和预期消息格式。

验收：

- macOS/Windows 本机完整跑通：登录 -> 保存 Cookie -> 添加/选择直播间 -> 开播 -> native adapter 收弹幕 -> 打印。
- 文档中的状态和代码实际一致。

## 每步执行规则

1. 每完成一个阶段，先更新本文档状态，再继续下一阶段。
2. 任何平台新增正式直播页支持前，先确认迅拣后端 `liveType`。
3. 任何平台新增正式链路前，优先实现 native adapter；helper 只能作为协议参考或临时实验。
4. 不能把测试页能连通当作正式页已完成，正式页必须从后台房间数据走完整链路。
5. 小红书后续只围绕 ark 工作台 Cookie 补 adapter，不继续沿用旧登录态 Cookie 作为主方案。
