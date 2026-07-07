# Web API Baseline

来源：`/Users/zcc/Documents/git-workspace-zcc/fast-sort-web/src/api/services.js`

默认接口基址：`https://xunjian.org.cn/api`

| 服务 | 方法 | 路径 |
| --- | --- | --- |
| auth | accountLogin | `/app/accountLogin` |
| auth | captchaLogin | `/app/captchaLogin` |
| auth | logout | `/app/logout` |
| auth | generateCaptcha | `/app/user/generateCaptcha` |
| auth | verifyCaptcha | `/app/user/verifyCaptcha` |
| auth | getProfile | `/app/user/getProfile` |
| auth | updateAppUserInfo | `/app/user/updateAppUserInfo` |
| auth | accountCancel | `/app/accountCancel` |
| stats | getCurrentUserStats | `/app/fsUserStats/getCurrentUserStats` |
| stats | getUserTagTrend | `/app/fsUserStats/getUserTagTrend` |
| rooms | getUserRoomPage | `/app/fsUserRoom/getFsUserRoomPage` |
| rooms | queryRoomsByUserId | `/app/fsUserRoom/queryRoomsByUserId/{userId}` |
| rooms | getUserRoom | `/app/fsUserRoom/getFsUserRoom/{id}` |
| rooms | getUserRoomStatus | `/app/fsUserRoom/getFsUserRoomStatus/{id}` |
| rooms | updateUserRoom | `/app/fsUserRoom/updateFsUserRoom` |
| rooms | updateUserRoomInfo | `/app/fsUserRoom/updateFsUserRoomInfo` |
| rooms | updateUserRoomPostage | `/app/fsUserRoom/updateFsUserRoomPostage` |
| rooms | updateUserRoomPriceTags | `/app/fsUserRoom/updateFsUserRoomPriceTags` |
| rooms | addUserRoom | `/app/fsUserRoom/addFsUserRoom/{roomNumber}` |
| rooms | addUserRoomTb | `/app/fsUserRoom/addFsUserTBRoom` |
| rooms | addUserRoomWx | `/app/fsUserRoom/addFsUserWXRoom` |
| rooms | addUpdateUserRoomXhs | `/app/fsUserRoom/addUpdateFsUserXhsRoom` |
| rooms | addUpdateUserRoomKuaishou | `/app/fsUserRoom/addUpdateFsUserKuaishouRoom` |
| rooms | cacheXhsCookies | `/app/fsUserRoom/cacheXhsCookies/{id}` |
| rooms | cacheKuaishouCookies | `/app/fsUserRoom/cacheKuaishouCookies/{id}` |
| rooms | updateUserRoomXhs | `/app/fsUserRoom/updateFsUserXhsRoom` |
| rooms | deleteUserRoom | `/app/fsUserRoom/deleteFsUserRoom/{id}` |
| live | getLiveTags | `/app/fsLiveTag/getFsLiveTagPage` |
| live | getLiveTagList | `/app/fsLiveTag/getFsLiveTagList` |
| live | getUserRoomPostage | `/app/fsLiveTag/getUserRoomPostage/{userRoomId}` |
| live | startLive | `/app/fsLiveRecord/startLive` |
| live | finishLive | `/app/fsLiveRecord/finishLive/{id}` |
| live | getLiveDanmu | `/app/fsLiveRecord/getLiveDanmu/{userRoomId}/{token}` |
| live | printLiveTagV2 | `/app/fsLiveTag/printLiveTagV2` |
| live | textPrintLiveTagV2 | `/app/fsLiveTag/textPrintLiveTagV2` |
| sort | getSortBatchList | `/app/fsSortBatch/getFsSortBatchList` |
| sort | getAllSortBatchList | `/app/fsSortBatch/getAllFsSortBatchList` |
| sort | completeSortBatch | `/app/fsSortBatch/completeSortBatch` |
| sort | getSortSetting | `/app/fsSortSetting/getFsSortSetting` |
| sort | updateSortSetting | `/app/fsSortSetting/updateFsSortSetting` |
| black | getBlackPage | `/app/fsBlack/getFsBlackPage` |
| black | getBlackDetailPage | `/app/fsBlackDetail/getFsBlackDetailPage` |
| black | getBlackDetail | `/app/fsBlackDetail/getFsBlackDetail/{id}` |
| black | deleteBlackDetail | `/app/fsBlackDetail/deleteFsBlackDetail/{id}` |
| black | addBlack | `/app/fsBlack/addFsBlack` |
| black | searchTagForBlack | `/app/fsBlack/searchTagForBlack` |
| black | getBlackByOrderNameId | `/app/fsBlack/getFsBlackByOrderNameId/{orderNameId}` |
| black | getBlackById | `/app/fsBlack/getFsBlack/{id}` |
| black | getBlackUserSetting | `/app/fsBlackUserSetting/getFsBlackUserSetting/{userId}` |
| black | updateBlackUserSetting | `/app/fsBlackUserSetting/updateFsBlackUserSetting` |
| template | getTagTemplatePage | `/app/fsTagTemplate/getFsTagTemplatePage` |
| template | getTagTemplateById | `/app/fsTagTemplate/getFsTagTemplate/{id}` |
| template | addTagTemplate | `/app/fsTagTemplate/addFsTagTemplate` |
| template | updateTagTemplate | `/app/fsTagTemplate/updateFsTagTemplate` |
| template | deleteTagTemplate | `/app/fsTagTemplate/deleteFsTagTemplate/{id}` |
| template | getTagElements | `/common/enum/tagElement` |
| template | getDanmuTemplates | `/app/danmuTemplate/getFsDanmuTemplate` |
| template | getDanmuTemplateById | `/app/danmuTemplate/getFsDanmuTemplateById/{id}` |
| template | addDanmuTemplate | `/app/danmuTemplate/addFsDanmuTemplate` |
| template | updateDanmuTemplate | `/app/danmuTemplate/updateFsDanmuTemplate` |
| template | deleteDanmuTemplate | `/app/danmuTemplate/deleteFsDanmuTemplate/{id}` |
| template | getDanmuElements | `/common/enum/danmuElement` |

## Rooms Contract Notes

- `addUserRoomTb` request body now accepts `roomName`, optional `roomNumber`, and `liveSession`.
- `queryRoomsByUserId` room items must include `liveSession` for Taobao/XHS/KS/WX local helper danmu connection.
| template | getDanmuMappingPage | `/app/fsDanmuMapping/getFsDanmuMappingPage` |
| template | addDanmuMapping | `/app/fsDanmuMapping/addFsDanmuMapping` |
| template | updateDanmuMapping | `/app/fsDanmuMapping/updateFsDanmuMapping` |
| template | deleteDanmuMapping | `/app/fsDanmuMapping/deleteFsDanmuMapping/{id}` |
| vip | getVipInfoList | `/app/fsVipInfo/getFsVipInfoList` |
| vip | getVipPaymentOrders | `/app/fsVipUserPaymentOrder/getFsVipUserPaymentOrderPage` |
| vip | hasToPaidOrder | `/app/fsVipUserPaymentOrder/hasToPaidOrder/{userId}` |
| vip | cancelOrder | `/app/fsVipUserPaymentOrder/cancelOrder/{id}` |
| vip | getOrderStatusByNumber | `/app/fsVipUserPaymentOrder/getOrderStatusByOrderNumber/{orderNumber}` |
| vip | getOrderResultForApple | `/app/fsVipUserPaymentOrder/getOrderResultForApple` |
| vip | fillInvitationCode | `/app/fsVipUser/fillInvitationCode` |
| payment | createOrder | `/app/order/createOrder/{vipInfoId}` |
| payment | createOrderApple | `/app/order/createOrderApple/{vipInfoId}` |
| payment | createOrderPc | `/app/order/alipayTradePagePayForPC/{vipInfoId}` |
| payment | createOrderWeb | `/app/order/alipayTradePagePay/{vipInfoId}` |
| payment | createOrderH5 | `/app/order/alipayTradeWapPay/{vipInfoId}` |
