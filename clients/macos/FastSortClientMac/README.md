# FastSortClientMac

macOS 客户端。

当前默认启动的是全原生模式：登录、左侧菜单、顶部/底部关联入口全部进入
SwiftUI/AppKit 原生页面，不再使用 WebView 页面回退。

运行：

```bash
cd clients/macos/FastSortClientMac
swift build
swift run FastSortClientMac
```

当前状态：

- 原生首页已接入统计、趋势、直播间、最新理货批次、黑名单模块，并按模块独立加载接口。
- 直播端、娱乐模式、理货端、订单备注、黑名单、充值记录、设置、个人中心、支付、打印测试均走原生页面。
- 直播端已接入开播/结束、弹幕 WebSocket、房间新增删除、平台表单和弹幕设置；娱乐模式已接入事件 WebSocket；理货端已接入批次分页、标签分页、重置编号和加入黑名单；订单备注已接入 remarkMap 导出；打印测试已接入 macOS 系统打印队列和 raw 指令发送。
- 登录 Token 使用 Keychain 保存和恢复。
- macOS 打包脚本已允许本地网络访问，用于弹幕 WebSocket、生产 API 和本机打印链路。
- SwiftUI 原生窗口、登录、侧边栏、主题 Token 和 API Client 基础类仍保留。
