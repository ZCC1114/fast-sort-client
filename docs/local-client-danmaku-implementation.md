# 迅拣客户端本机弹幕链路落地说明

更新日期：2026-07-07

> 本文档只记录当前客户端落地状态和迁移边界。旧 Python helper 链路已经降级为协议参考资料，不再是 macOS 客户端运行路径。最终实施计划见 `docs/native-danmaku-adapter-plan.md`。

## 当前运行目标

1. 客户端打开平台后台工作台登录页。
2. 用户在客户端 WebView 中扫码或账号登录。
3. 客户端采集平台 Cookie。
4. Cookie 保存到迅拣后台房间 `liveSession`。
5. 正式开播时客户端从后台房间 `liveSession` 取 Cookie。
6. 客户端内置 native adapter 直接连接平台弹幕源。
7. 弹幕事件进入现有展示、匹配、打印、娱乐统计流程。

客户端不启动外部 Python 服务，不要求用户启动外部项目，也不把本地端口作为正式弹幕入口。

## macOS 当前状态

已完成：

- `LiveRoomsView` 正式直播页已通过 `NativeDanmakuSessionCoordinator` 做开播前 Cookie 和 adapter 预检。
- `LiveRoomsView` 的“添加直播间”入口已跳转到授权测试页，不再提供手填 Cookie 或技术房间号的正式添加弹窗。
- `DanmakuCookieTestView` 授权测试页已统一走 native adapter，不再保留页面内淘宝/快手重复协议代码。
- `FeatureViews` 娱乐模式已统一走 native adapter 生命周期，不再连接外部抖音服务。
- `DanmakuCookieSessionParser` 统一解析 `liveSession`，兼容 raw Cookie、JSON Cookie 字段、cookie map、cookie item array。
- `LocalDanmakuHelperManager`、`DanmakuLocalConnectionBuilder`、`DanmakuLocalLivePrepareModels` 已从 macOS 正式源码删除。
- 抖音 native adapter 已完成基础链路：工作台/历史字段解析直播标识 -> 随包 `sign.js` 签名 -> WSS/protobuf/ack/heartbeat -> 统一事件。
- 淘宝 macOS/Windows native adapter 已完成无页面依赖链路：千牛 Cookie -> MTop 当前直播 `topic` -> impaas 弹幕轮询。
- 快手 native adapter 已完成基础链路：快手工作台 Cookie -> owner/liveStreamId/token -> 平台 WebSocket/protobuf 弹幕。
- 视频号 native adapter 已完成基础链路：`sessionid/wxuin` -> 视频号助手接口 -> `join_live` -> `msg` polling。
- 小红书 macOS 已完成 Cookie 原生主链路：千帆 Cookie -> ark 当前直播接口 -> `redlive-ark` RWP 鉴权 -> `room` 注册/进房 -> 本机解析评论；运行时不打开或依赖直播中控页面。

未完成：

- 抖音、小红书、视频号、快手仍需用真实开播账号做实播验证和协议边界加固；淘宝已用真实千牛登录态验证 Cookie 查询链路与页面捕获的 impaas UUID 一致，仍需补一次“持续开播并发送评论”的端到端回归。
- 抖音仍需继续加固“仅通过工作台 Cookie 自动解析当前直播间”的接口路径；解析不到时阻断，不要求用户手填。
- 小红书仍需用真实开播账号完成评论实播回归和断线重连加固；当前链路不启动外部服务，也不依赖 WebView 页面捕获。
- TikTok、Shopee 需要等迅拣后端正式平台枚举和保存接口确认后再接入正式直播页。

未实现平台必须明确提示 native adapter 未实现，不允许回退到外部 Python 服务。

## 后台房间接口依赖

正式直播页依赖 `queryRoomsByUserId` 的 `RoomListItem`：

- `liveType`：只使用迅拣后端枚举。当前客户端映射为 `0` 抖音、`1` 淘宝、`2` 小红书、`3` 视频号、`4` 快手。
- `liveSession`：必须返回对应平台工作台 Cookie。native adapter 只从这里取登录态。
- `roomNumber`、`eid`：只作为历史数据和兼容字段，最终新增直播间流程不要求用户手动填写这些技术字段。

`liveSession` 支持格式：

- raw Cookie header，例如 `a=1; b=2`。
- JSON 字段，例如 `{"cookie":"a=1; b=2"}` 或 `{"cookies":"a=1; b=2"}`。
- JSON map，例如 `{"cookies":{"a":"1","b":"2"}}`。
- cookie item array，例如 `[{"name":"a","value":"1"}]`。

## 添加直播间口径

所有平台最终都应通过后台工作台登录页添加：

- 抖音：抖店/达人工作台 Cookie。
- 淘宝：千牛工作台 Cookie。
- 小红书：ark/客服工作台 Cookie。
- 视频号：视频号助手工作台 Cookie。
- 快手：快手小店/工作台 Cookie。

不再把 Cookie 文本、抖音号、淘宝 roomId、快手房间号、TikTok unique_id、Shopee session_id、短链或分享链接作为新增直播间必填项。

## 旧 helper 资料的使用边界

旧外部项目只能作为协议迁移参考：

- 参考平台登录后 Cookie 如何被使用。
- 参考平台 roomId、liveStreamId、token、session 字段的解析入口。
- 参考签名、protobuf、heartbeat、ack、消息字段映射。

禁止把这些项目作为 macOS/Windows 客户端运行依赖，也禁止在正式源码中新增启动、打包或连接这些服务的逻辑。
