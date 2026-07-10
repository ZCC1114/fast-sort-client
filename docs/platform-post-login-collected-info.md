# 弹幕捕手登录后采集和派生信息整理

本文按已调查到的弹幕捕手平台注册表、添加直播间流程，以及迅拣客户端当前复刻实现整理。这里的“获取信息”分两层：

- 直接采集：登录成功后从内嵌浏览器会话拿到的 Cookie 和页面匹配状态。
- 派生信息：后续连接弹幕时，用 Cookie、直播链接或房间号进一步解析出来的 roomId、userId、WebSocket token 等。

## 通用直接采集信息

每个平台登录完成后，弹幕捕手通用会拿这些信息：

| 信息 | 说明 |
| --- | --- |
| 弹幕捕手授权配置 ID / key | 例如 `1/fxg`、`2/xhs`、`3/tb`、`8/ks`。只用于研究弹幕捕手授权窗口，不作为迅拣正式 `liveType`。 |
| 平台名称 | 例如 `抖音工作台`、`小红书工作台`、`千牛工作台` |
| 登录页 URL | 平台授权窗口打开的地址 |
| 成功页匹配规则 | `contentScriptMatch` + `pageHandlerMatch`，命中后延迟采集 Cookie |
| Cookie 域 | 例如 `jinritemai.com`、`xiaohongshu.com`、`taobao.com` |
| Cookie 明细 | `name`、`value`、`domain`、`path`、`secure`、`httpOnly`、`expires` |
| 完整 Cookie header | 拼成 `name=value; name2=value2`，后续弹幕 adapter 使用 |
| 店铺绑定信息 | 添加成功后业务侧会形成 `livePlatform`、`liveShopId`、`liveShopName` 这类绑定数据 |

观察到的逻辑不是采集账号密码，而是让平台登录页自己完成登录，应用只在成功页后读取当前浏览器会话 Cookie。

## 平台明细

### 抖音工作台 `fxg`

直接采集：

- 弹幕捕手授权配置 ID：`1`
- 业务 key：`fxg`
- 登录页：`https://fxg.jinritemai.com/login/common`
- 成功页：`fxg.jinritemai.com/ffa/mshop/homepage/index`
- Cookie 主域：`jinritemai.com`
- 可能补充域：抖音相关域，迅拣测试页已允许 `douyin.com`
- 保存形态：完整 Cookie header
- 业务绑定：店铺平台、店铺 ID、店铺名称

后续派生：

- 需要直播间 `live_id` 或直播链接。
- Cookie 可通过 `cookie_b64` 传给本机抖音 adapter。
- adapter 再生成/获取抖音弹幕 WebSocket 签名参数。
- 弹幕消息统一输出用户昵称、用户 ID、消息 ID、弹幕内容、房间 ID。

### 抖音达人工作台 `fxg_kol`

直接采集：

- 弹幕捕手授权配置 ID：`4`
- 业务 key：`fxg_kol`
- 登录页：`https://buyin.jinritemai.com/mpa/account/login`
- 成功页：`buyin.jinritemai.com/dashboard*`
- Cookie 主域：`jinritemai.com`
- 可能补充域：抖音相关域，迅拣测试页已允许 `douyin.com`
- 保存形态：完整 Cookie header
- 业务绑定：达人/百应账号对应的平台、账号 ID、名称

后续派生：

- 和抖音工作台一致，仍然需要直播间 `live_id` 或直播链接。
- adapter 负责签名、WebSocket、protobuf 解码。

### 小红书工作台 `xhs`

直接采集：

- 弹幕捕手授权配置 ID：`2`
- 业务 key：`xhs`
- 登录页：`https://customer.xiaohongshu.com/login?service=https://ark.xiaohongshu.com/app-system/home`
- 成功页：`ark.xiaohongshu.com/app-system/home`
- Cookie 主域：`xiaohongshu.com`
- 保存形态：完整 Cookie header

关键 Cookie / 登录态：

- 工作台登录完成后通常能拿到 `webId`、`websectiga`、`xsecappid`、多个域下的 `acw_tc`、`access-token-ark.xiaohongshu.com` 等 `xiaohongshu.com` 主域/子域 Cookie。
- 弹幕捕手添加直播间阶段只把这些工作台 Cookie 组成完整 Cookie header，并加密上传到 `checkV2` 校验绑定店铺。
- `x-user-id-redlive.xiaohongshu.com`、`access-token-redlive.xiaohongshu.com` 属于另一条 redlive 直连假设，不是弹幕捕手小红书添加直播间配置要求的 Cookie。

后续派生：

- `shopId/shopName`：由 `checkV2` 根据工作台 Cookie 校验后返回。
- `cookie`：开启自动打印时通过 `liveShopData` 按 `platform=xhs + shopId` 取回。
- `roomId`：由小红书平台 adapter 的 `getRoomId(cookie, shopId)` 解析，而不是在授权页直接解析。
- WebSocket：adapter 获取 `roomId` 后再构建平台弹幕连接，并把消息统一输出为昵称、消息 ID、弹幕内容、房间 ID。

### 千牛/淘宝工作台 `tb`

直接采集：

- 弹幕捕手授权配置 ID：`3`
- 业务 key：`tb`
- 登录页：`https://qn.taobao.com/home.htm/QnworkbenchHome/`（未登录时由千牛自动跳转登录页）
- 成功页：任意 `*.taobao.com/home.htm/*` 千牛工作台页，不要求进入直播管理
- Cookie 主域：`taobao.com`
- 可能补充域：`tmall.com`
- 保存形态：完整 Cookie header
- 业务绑定：店铺平台、店铺 ID、店铺名称

后续派生：

- 默认不再要求手填淘宝直播链接。
- 运行时不读取千牛页面 URL、DOM 或抓包结果，也不打开直播管理页。
- 用千牛 Cookie 调用 `mtop.taobao.dreamweb.room.list` 获取直播房间，再调用 `mtop.taobao.dreamweb.live.list.query`（`roomStatus=1`）查询当前开播场次。
- 当前场次的 `topic` 就是 impaas 评论轮询 UUID；若列表未直接返回 `topic`，再用 `mtop.taobao.dreamweb.live.detail` 补取。
- 生成稳定 `deviceId`：`sha1(roomId)` 前 24 位。
- 轮询淘宝 `impaas` / `impaasgw` 弹幕源。
- 弹幕 payload 解码后提取 `content/text/msg`、`tbNick/snsNick/publisherNick`、`tbUserIdEncode/userId`、`msgId/messageId`、`liveId`。

### TikTok 工作台 `tiktok`

直接采集：

- 弹幕捕手授权配置 ID：`5`
- 业务 key：`tiktok`
- 登录页：`https://seller.tiktokshopglobalselling.com/account/login`
- 成功页：`seller.us.tiktokshopglobalselling.com/homepage*`
- Cookie 主域：`tiktokshopglobalselling.com`
- 可能补充域：`tiktok.com`
- 保存形态：完整 Cookie header

后续派生：

- 需要 TikTok `unique_id`。
- 本机 TikTok adapter 根据 `unique_id` 连接 TikTokLive 协议。
- 如果 adapter 签名方案需要登录态，会使用采集到的 Cookie；当前迅拣测试页主要把 Cookie 作为可用会话保存。
- 弹幕消息统一输出用户、内容、消息 ID、房间 ID。

### Shopee / 虾皮工作台 `shopee`

直接采集：

- 弹幕捕手授权配置 ID：`6`
- 业务 key：`shopee`
- 登录页：`https://seller.shopee.cn/account/signin`
- 成功页：`seller.shopee.cn/*`
- Cookie 主域：`shopee.cn`
- 保存形态：完整 Cookie header

后续派生：

- 需要 `session_id`、短链或分享链接。
- 本机 Shopee adapter 解析直播 `session_id`、market、chatroom/live session。
- 再连接 Shopee Live 弹幕通道。
- 弹幕消息统一输出用户、内容、消息 ID、房间 ID。

### 视频号工作台 `ec`

直接采集：

- 弹幕捕手授权配置 ID：`7`
- 业务 key：`ec`
- 登录页：`https://channels.weixin.qq.com/login.html`
- 成功页：`channels.weixin.qq.com/platform/*`
- Cookie 主域：`weixin.qq.com`
- 保存形态：完整 Cookie header

关键 Cookie / 登录态：

- `sessionid`：视频号助手会话 ID。
- `wxuin`：微信 UIN。

后续派生：

- 客户端从 Cookie header 解析 `sessionid` 和 `wxuin`。
- 本机视频号 adapter 用这两个值连接视频号弹幕。
- 弹幕消息统一输出用户、内容、消息 ID、房间 ID。

### 快手工作台 `ks`

直接采集：

- 弹幕捕手授权配置 ID：`8`
- 业务 key：`ks`
- 登录页：`https://login.kwaixiaodian.com/?biz=zone&redirect_url=https%3A%2F%2Fs.kwaixiaodian.com%2Fzone%2Forder%2Flist`
- 成功页：`s.kwaixiaodian.com/zone/order/list*`
- Cookie 主域：`kwaixiaodian.com`
- 补充 Cookie URL：`https://s.kwaixiaodian.com/zone/order/list`
- 保存形态：完整 Cookie header

关键 Cookie / 登录态：

- `kwfv1`：如果存在，会作为请求头 `Kww` 传给快手接口。
- 其他快手小店登录态 Cookie 会整体作为 `Cookie` header 使用。

后续派生：

- 需要快手房间号或 `live.kuaishou.com/u/{id}`。
- 请求 `https://live.kuaishou.com/u/{roomId}` 解析直播页。
- 从页面 `playList`/直播详情里取 `liveStreamId`、主播名称、直播状态。
- 请求 `https://live.kuaishou.com/live_api/liveroom/websocketinfo?caver=2&liveStreamId={liveStreamId}`。
- 从返回里取 `token`、`websocketUrls` / `webSocketAddresses`。
- 连接快手平台 WebSocket，发送 `CSWebEnterRoom` 和心跳。
- 弹幕 protobuf 解码后提取用户 ID、昵称、评论内容、消息 ID、房间 ID。

### 微信小店工作台 `wx_store`

直接采集：

- 弹幕捕手授权配置 ID：`99`
- 业务 key：`wx_store`
- 登录页：`https://store.weixin.qq.com/shop?redirect_url=%2Forder%2Flist`
- 成功页：`store.weixin.qq.com/shop/order/list*`
- Cookie 主域：`weixin.qq.com`
- 补充 Cookie URL：`https://store.weixin.qq.com/shop/order/list`
- allowed domain：`store.weixin.qq.com`

状态：

- 弹幕捕手平台注册表里存在该配置。
- 当前添加直播间弹窗会过滤掉微信小店，所以用户界面里通常看不到这个入口。

## 汇总表

| 平台 | 登录后直接拿到 | 后续连弹幕派生 |
| --- | --- | --- |
| 抖音工作台 | `jinritemai.com` Cookie、店铺绑定 | `live_id`、签名参数、弹幕 WS、用户/内容/msgId |
| 抖音达人 | `jinritemai.com` Cookie、达人账号绑定 | `live_id`、签名参数、弹幕 WS、用户/内容/msgId |
| 小红书 | `xiaohongshu.com` Cookie | `userId`、`sid`、`roomId`、apppush-rws 连接参数 |
| 淘宝/千牛 | `taobao.com` Cookie、店铺绑定 | `roomId`、`deviceId`、impaas 弹幕轮询参数 |
| TikTok | `tiktokshopglobalselling.com` Cookie | `unique_id`、TikTokLive 连接参数 |
| Shopee | `shopee.cn` Cookie | `session_id`、market、chatroom/live session |
| 视频号 | `weixin.qq.com` Cookie | `sessionid`、`wxuin` |
| 快手 | `kwaixiaodian.com` Cookie | `kwfv1/Kww`、`liveStreamId`、`token`、`websocketUrls` |
| 微信小店 | `weixin.qq.com` / `store.weixin.qq.com` Cookie | 当前入口隐藏，未进入直播弹幕链路 |
