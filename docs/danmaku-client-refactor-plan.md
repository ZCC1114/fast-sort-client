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
- 旧 `DanmakuLocalConnectionBuilder`、`LocalDanmakuHelperManager`、`DanmakuLocalLivePrepareModels` 已从 macOS 正式源码删除，不再提供本地 Python helper 启动和 `127.0.0.1` helper URL 构造能力。
- `DanmakuWebSocketSession` 已抽到服务层，只作为 native adapter 内部可复用 WebSocket 生命周期工具，不作为页面层直连本地 helper 的入口。
- `DanmakuSocketMessageParser` 已抽到服务层，正式直播页、授权测试页、娱乐弹幕页已复用统一平台状态文本解析。
- `DanmakuCookieSessionParser` 已抽到服务层，正式直播页和娱乐弹幕页已复用统一 `liveSession` Cookie 解析。
- macOS 已新增 native adapter 基础层：`NativeDanmakuEvent`、`NativeDanmakuConnectRequest`、`NativeDanmakuAdapter`、`NativeDanmakuConnection`、`NativeDanmakuAdapterFactory`、`NativeDanmakuSessionCoordinator`。
- `LiveRoomsView`、`DanmakuCookieTestView`、`FeatureViews` 已统一通过 native adapter factory/coordinator 发起弹幕连接，不再直接创建本地 helper WebSocket。
- `LiveRoomsView` 正式开播前已切到 native coordinator 预检；Cookie 缺失、adapter 未实现、登录失效、未开播时会在创建后台直播记录前阻断。
- `LiveRoomsView` 已移除正式页内的 helper 启动、本机 helper URL 构造和淘宝 roomId/分享链接兜底弹窗；正式页只从后台房间 `liveSession` 取 Cookie。
- `LiveRoomsView` 的“添加直播间”按钮已改为跳转“直播授权测试”，不再展示手填 Cookie、抖音直播间号、快手直播间号等旧弹窗字段。
- `DanmakuCookieTestView` 已移除页面内淘宝/快手重复协议代码，测试连接统一走 native adapter；未实现平台由 `PendingNativeDanmakuAdapter` 明确阻断。
- `FeatureViews` 娱乐模式已迁移到 native adapter 生命周期，不再连接抖音 `8865` 本地 helper。
- macOS 已落地抖音 native adapter：随包 `sign.js` + JavaScriptCore 签名、WSS、gzip/protobuf、ack/heartbeat、聊天/礼物/进场/点赞/互动/关播事件解析。
- macOS 已落地淘宝 native adapter：千牛工作台 Cookie -> 当前直播 roomId -> impaas 轮询弹幕。
- macOS 已落地快手 native adapter：快手工作台 Cookie -> owner id/liveStreamId/token -> 平台 WebSocket/protobuf 弹幕。
- macOS 已落地视频号 native adapter：`sessionid/wxuin` -> 视频号助手接口 -> `join_live` -> `msg` polling 弹幕。
- macOS 已落地小红书 native adapter：ark/客服工作台 Cookie -> 本机补齐直播登录态 -> living_room -> 平台 WebSocket 文本弹幕。后续仍需继续调研 ark 工作台直连，当前不启动外部服务。
- `swift build` 已通过。

当前主要问题：

- 消息去重和具体业务响应仍留在各页面内：正式页负责打印队列，测试页负责测试输出，娱乐页负责互动统计；协议连接已收敛到 adapter 层。
- 抖音、小红书、视频号、淘宝、快手均已有 macOS native adapter 基础实现，但仍需真实开播账号逐平台验证协议边界。
- TikTok、Shopee 仍是 pending adapter，当前不会回退启动外部 Python helper。
- 抖音新增直播间仍需继续加固“工作台 Cookie 自动解析当前直播间”接口；当前 adapter 已兼容后端历史字段和工作台页面可提取字段，解析不到时会阻断而不是要求用户手填。
- 小红书当前 adapter 是 ark Cookie 本机补齐直播登录态后的 WebSocket 兼容实现，后续仍要补齐纯 ark 工作台接口路径。
- Windows 侧仍需按本文档补齐同构页面和 adapter 基础层。

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

状态：已完成，随后已被阶段 8 的 native adapter 目标取代并从 macOS 正式源码删除旧本地 helper URL 构造。

目标：

- 新增统一的本机连接 builder。
- 集中处理本机端口读取、HTTP URL、WebSocket URL、外部 wsPath 映射回本机、抖音/TikTok/Shopee/视频号桥接 URL。
- 修正 Shopee 测试连接默认端口，避免和视频号 `8000` 冲突。

验收：

- 历史 helper 过渡期曾统一过本地 URL 构造。
- 当前 macOS 正式源码已删除 `DanmakuLocalConnectionBuilder`，不再保留 helper 端口构造能力。
- `swift build` 通过。

### 阶段 3：本机连接管理器

状态：已完成，页面层已进一步迁移到 native adapter 生命周期。

目标：

- 新增 `DanmakuWebSocketSession`，统一管理 `URLSessionWebSocketTask`、接收循环、ping 和取消。
- 新增 `DanmakuSocketMessageParser`，统一处理平台状态文本。
- 正式直播页和授权测试页只提供平台、房间、Cookie 和输入参数，不直接管理 socket 生命周期。

验收：

- 平台返回的 `LIVING`、`CONNECTING`、`STOPPED`、`pong` 等状态由 `DanmakuSocketMessageParser` 统一解析。
- `LiveRoomsView`、`DanmakuCookieTestView`、`FeatureViews` 不再直接创建或持有裸 `URLSessionWebSocketTask`。
- 页面层连接入口已收敛到 native adapter/coordinator。
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

状态：macOS 页面层基础接入完成，Windows 待执行。

目标：

- 建立 macOS/Windows 共用概念模型：`NativeDanmakuAdapter`、`NativeDanmakuEvent`、`NativeDanmakuSessionCoordinator`、`NativeDanmakuAdapterFactory`。
- 正式直播页、授权测试页、娱乐模式只依赖 coordinator，不再直接连接 helper 或解析平台协议。
- 添加直播间统一为平台工作台登录和 Cookie 保存流程，技术房间标识由 adapter 在开播预检阶段解析。
- Windows 补齐 `Core/Danmaku`、授权测试页和直播间页的 native adapter 接入口。

验收：

- 页面层不再新增平台协议代码。
- macOS 事件 schema 已落到代码。
- `LiveRoomsView`、`DanmakuCookieTestView`、`FeatureViews` 均已走 native adapter factory/coordinator。
- `swift build` 已通过；Windows `dotnet build` 待 Windows 侧执行。

### 阶段 6：逐平台 native adapter 落地

状态：macOS 抖音、淘宝、快手、视频号、小红书已完成基础 adapter；TikTok、Shopee 待后端正式平台枚举和保存接口确认。

优先级：

1. 抖音：`sign.js` + protobuf + WSS + ack/heartbeat 已迁入 macOS 客户端，后续做实播验证和工作台当前直播解析加固。
2. 淘宝：千牛 Cookie -> 当前直播 roomId -> impaas/polling 弹幕，macOS 已完成基础 adapter，后续需实播账号验证和协议边界加固。
3. 快手：Cookie -> liveStreamId/token -> 平台 WebSocket，macOS 已完成基础 adapter，后续需实播账号验证和协议边界加固。
4. 视频号：sessionid/wxuin -> 平台消息源已迁入 macOS 客户端，后续做实播验证。
5. 小红书：ark 工作台 Cookie -> 当前直播信息 -> 弹幕拉取已迁入 macOS 客户端兼容链路，后续继续补纯 ark 工作台接口。
6. TikTok/Shopee：等迅拣后端正式平台枚举确认后再规划 native adapter。

验收：

- 每个平台至少有一个可复现的测试账号和直播间。
- 每个平台的 adapter 输出统一消息字段：用户、内容、消息 ID、房间 ID、平台状态。
- 弹幕消息不经过迅拣云端 WebSocket 中转，也不经过本机 Python helper。

### 阶段 7：正式直播页接入

状态：macOS 已完成基础接入。

目标：

- 正式开播按钮按平台执行本机预检。
- Cookie 缺失、登录过期、房间未开播、平台协议失败时给出明确错误。
- 弹幕展示、自动打印、手动打印继续复用现有业务逻辑。

验收：

- 开播失败不创建无效直播记录，或能在失败后自动回滚/结束。
- 弹幕连接成功后才进入自动打印队列。
- 断线和直播结束状态能回到 UI。

### 阶段 8：删除 helper 过渡层

状态：macOS 已完成；Windows 不应新增 helper 过渡层。

目标：

- 删除正式链路对 `LocalDanmakuHelperManager`、`DanmakuLocalConnectionBuilder`、`127.0.0.1` helper 端口的依赖。
- 打包产物不包含 Python、venv、uvicorn、Node 运行时依赖。
- 文档中只保留 helper 作为协议迁移参考的历史说明。

验收：

- 静态扫描正式源码不再命中 helper 启动和 helper 端口。
- macOS 已删除 `LocalDanmakuHelperManager`、`DanmakuLocalConnectionBuilder`、`DanmakuLocalLivePrepareModels`。
- 用户只启动一个客户端 App 即可完成登录、保存 Cookie、开播、收弹幕、打印。

### 阶段 9：验证和发布

状态：macOS 基础验证已开始，仍需真实账号逐平台实播验收；Windows 待执行。

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
