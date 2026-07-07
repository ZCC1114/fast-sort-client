# 迅拣客户端本机弹幕链路落地说明

> 本文档记录的是 helper 过渡链路现状，用于理解当前代码和迁移来源。最终目标已经调整为客户端内置 native adapter，不依赖外部 Python 服务。新的实施方案见 `docs/native-danmaku-adapter-plan.md`。

## 目标边界

- 弹幕获取、平台 WebSocket、签名、protobuf/协议解析当前仍有一部分通过本机 helper 过渡；最终必须迁入 macOS/Windows 客户端 native adapter。
- 后台仍可用于登录、会员、房间列表、模板、开播记录、打印记录等业务数据。
- 客户端不再连接 `wss://xunjian.org.cn/*-ws` 或 `wss://xunjian.org.cn/ws/events/*` 获取弹幕。
- 最终正式链路也不再连接 `127.0.0.1` helper 端口。
- Cookie 可先沿用现有房间接口保存/返回；如果后续要求 Cookie 也不进后台，需要再做本地加密存储。

## 已落地到客户端的改动

- `LiveRoomsView` 正式直播页的弹幕连接改为本机 `127.0.0.1` helper。
- `LiveRoomsView` 不再在小红书、快手开播前调用远程 `/xhs/api/live/check_and_start`、`/ks/api/live/check_and_start`。
- `LiveRoomsView` 支持从 `room.liveSession` 读取 raw Cookie、JSON Cookie 字段、Cookie map、Cookie item 数组。
- 快手本机 WS 会通过 header 传 `x-kuaishou-cookie`。
- 淘宝开播前会先调用本机 `taobao_live` 的 `/api/live/check_and_start`，用 `liveSession` 中的千牛 Cookie 解析当前直播 roomId。
- 小红书当前只完成 ark 工作台 Cookie 采集和保存；后续需要补一个基于 ark Cookie 的本机 adapter。
- `FeatureViews` 中娱乐弹幕的抖音 WS 也改为本机抖音 helper。
- `直播授权测试` 菜单已经包含平台登录、Cookie 采集、Cookie 展示、弹幕测试入口。

## 当前本机 helper 端口约定

端口可通过 `UserDefaults` 覆盖，键名为 `LocalDanmaku.<platform>.port`。

| 平台 | 默认端口 | 客户端连接 | 房间输入 | Cookie 使用 |
| --- | ---: | --- | --- | --- |
| 抖音 | `8865` | `ws://127.0.0.1:8865/ws/events/{live_id}` | `roomNumber` 为 live_id | 可选，`cookie_b64` query |
| 淘宝 | `8201` | 先 `POST http://127.0.0.1:8201/api/live/check_and_start`，再连返回的 `/tb-ws-room/{room_id}` | 默认由千牛 Cookie 解析当前直播 roomId | `liveSession` 千牛 Cookie |
| 小红书 | `8101` | `ws://127.0.0.1:8101/xhs-ws/{room_id}` | `roomNumber` 为 room_id | `x-xhs-cookie` header |
| 视频号 | `8000` | `ws://127.0.0.1:8000/wx-ws` | 无需 roomNumber | query 传 `sessionid`、`wxuin` |
| 快手 | `8301` | `ws://127.0.0.1:8301/ks-ws/{room_id}` | `eid` 或 `roomNumber` | `x-kuaishou-cookie` header |
| TikTok | `8765` | `ws://127.0.0.1:8765/ws/{unique_id}` | 以迅拣后端正式枚举为准 | 由 helper 自己处理 |
| Shopee | `8001` | `ws://127.0.0.1:8001/shopee/ws` | 以迅拣后端正式枚举为准 | 由 helper 自己处理 |

## 本机弹幕服务源码目录

以下目录是当前本地工作区的 helper 服务源码位置，后续打包、启动脚本和端口检查都以这里为准。

| 平台 | 弹幕服务 | 本地路径 | 对应默认端口 |
| --- | --- | --- | ---: |
| 抖音 | `DouyinLiveWebFetcher-mainPython` | `/Users/zcc/Documents/git-workspace-zcc/DouyinLiveWebFetcher-mainPython` | `8865` |
| 淘宝 | `taobao_live` | `/Users/zcc/Documents/git-workspace-zcc/taobao_live` | `8201` |
| 小红书 | `xhs_live` | `/Users/zcc/Documents/git-workspace-zcc/xhs_live` | `8101` |
| 视频号 | `wx_live` | `/Users/zcc/Documents/git-workspace-zcc/wx_live` | `8000` |
| 快手 | `kuaishou_live` | `/Users/zcc/Documents/git-workspace-zcc/kuaishou_live` | `8301` |

## 后台房间接口必须返回的数据

正式直播页依赖 `queryRoomsByUserId` 的 `RoomListItem`：

- `liveType`：只以迅拣后端枚举为准。当前接口实测已确认 `0` 抖音、`1` 淘宝、`3` 视频号、`4` 快手；`2` 按现有客户端逻辑为小红书。其它平台必须等迅拣后端给出正式 `liveType` 后再接入正式直播页。
- `roomNumber`：
  - 最终 native adapter 方案中，新增直播间不应要求用户手动输入 `roomNumber`；该字段只作为历史数据和后台兼容字段。
  - 抖音：live_id。
  - 淘宝：可为空；开播前由 `liveSession` 中的千牛 Cookie 解析当前直播 roomId。历史数据中如果已有 roomId/直播链接，仅作为兜底。
  - 小红书：当前直播 room_id。
  - 视频号：可为空。
  - 快手：快手房间号。
  - TikTok：等迅拣后端正式枚举确认后接入；最终不把 `unique_id` 作为新增直播间必填项。
  - Shopee：等迅拣后端正式枚举确认后接入；最终不把 `session_id`、短链或分享链接作为新增直播间必填项。
- `eid`：快手优先使用，可等于快手房间号。
- `liveSession`：
  - raw Cookie header 字符串，例如 `a=1; b=2`。
  - 或 JSON：`{"cookie":"a=1; b=2"}`、`{"cookies":"a=1; b=2"}`。
  - 或 JSON map：`{"cookies":{"a":"1","b":"2"}}`。
  - 淘宝必须能解析出千牛/淘宝工作台 Cookie。
  - 视频号必须能解析出 `sessionid` 和 `wxuin`。

## helper 过渡链路还缺什么

以下问题只描述旧 helper 过渡链路。如果按最终 native adapter 方案继续推进，不应再投入“打包 Python helper”作为正式方案。

1. 本机 helper 打包方案：这是旧过渡链路问题，最终 native adapter 方案不需要把 Python helper 或编译后的二进制放进 macOS App。
2. 小红书 helper 还缺基于 ark 工作台 Cookie 的本机 adapter：现有旧 helper 不能直接使用 `ark/customer.xiaohongshu.com` 工作台 Cookie 跑通弹幕。
3. Cookie 回传确认：正式房间列表必须把 TB/XHS/KS/WX 的 `liveSession` 返回给客户端，否则 native adapter 没有登录态。
4. 端口冲突确认：视频号默认 `8000`，Shopee 本地源码默认也可能是 `8000`，客户端已把 Shopee 默认设为 `8001`，helper 启动参数也要同步。
5. 抖音/TikTok 签名依赖：抖音 helper 需要 `sign.js`/Node 或 MiniRacer；TikTok helper 如走 EulerStream 需要对应 API key 或可用签名方案。
6. 实测账号和直播间：每个平台至少准备一个正在直播的账号、可用 Cookie、可进入的房间号/链接，用来验证 Cookie 到弹幕展示全链路。
7. 后端平台枚举确认：后续新增 TikTok、Shopee、微信小店等正式平台时，必须使用迅拣后端定义的 `liveType`，不能使用弹幕捕手的 `platformId`。当前实际 `queryRoomsByUserId` 中已经存在 `liveType=5`，但 `liveSession` Cookie key 是 `kfz_uuid/PHPSESSID`，不能按弹幕捕手 `platformId=5` 识别成 TikTok。

## 和弹幕捕手逻辑的对应关系

弹幕捕手的核心不是“后台代抓弹幕”，而是：

1. 平台工作台登录页在内置 WebView 打开。
2. 登录成功后从 Chromium/WebKit session 中采集平台 Cookie。
3. Cookie 和房间配置进入当前客户端会话。
4. 平台 adapter 用 Cookie 和自动解析出的平台直播标识直连平台弹幕源。
5. adapter 把平台消息统一成 `danmuContent`、`danmuUserName`、`msgId/平台MsgId`、`roomId` 等字段。
6. UI 展示弹幕，自动打印逻辑继续复用现有匹配、去重、队列规则。

迅拣客户端现在的最终调整目标就是复刻第 3-6 步，把第 4 步从后台 WS 或本机 helper 过渡链路迁入客户端 native adapter。

## 本机 helper adapter 对接

当前客户端已按本机 helper 路由做了过渡对接，下面表格只作为迁移 native adapter 时的协议参考：

| 平台 | 迅拣 `liveType` | 本机 helper | 客户端连接方式 |
| --- | --- | --- | --- |
| 抖音 | `0` | `DouyinLiveWebFetcher-mainPython` | `ws://127.0.0.1:8865/ws/events/{live_id}`，可通过 `cookie_b64` query 传 Cookie |
| 淘宝 | `1` | `taobao_live` | 先 `POST http://127.0.0.1:8201/api/live/check_and_start` 用千牛 Cookie 解析 roomId，再连 `/tb-ws-room/{room_id}` |
| 小红书 | `2` | `xhs_live` | 先 `POST http://127.0.0.1:8101/api/live/check_and_start`，再连返回的 `/xhs-ws/{room_id}` |
| 视频号 | `3` | `wx_live` | `ws://127.0.0.1:8000/wx-ws?sessionid=...&wxuin=...` |
| 快手 | `4` | `kuaishou_live` | 已有房间号时连 `ws://127.0.0.1:8301/ks-ws/{room_id}` 并带 `x-kuaishou-cookie`；缺房间号时先 `check_and_start` |

注意：弹幕捕手小红书添加直播间阶段采集的是 `ark/customer.xiaohongshu.com` 工作台 Cookie。客户端现在能把工作台 Cookie 保存到迅拣直播间；要用这套工作台 Cookie 直接跑通小红书弹幕，还需要补一个能从工作台 Cookie 派生直播信息并拉取弹幕的本机 adapter。
