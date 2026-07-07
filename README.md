# 迅拣原生客户端

本目录用于开发迅拣 Windows 和 macOS 原生客户端。

参考文档：

- `docs/client-rebuild-context.md`：现有后端、Web、App 项目基线。
- `docs/native-client-development-plan.md`：原生客户端页面功能和阶段计划。

目录：

```text
shared/                  # 两端共享的接口契约、设计 Token、业务规则文档
clients/windows/          # Windows 原生客户端
clients/macos/            # macOS 原生客户端
```

当前进度：

- macOS 当前测试包已切换为全原生运行路径：登录、左侧菜单、顶部/底部关联入口全部进入 SwiftUI/AppKit 原生页面，不再使用 WebView 页面回退。
- Phase 0 已完成：工程骨架和共享契约目录已建立。
- Phase 1 已开始：macOS 已接入真实登录、Keychain Token、Profile/VIP 恢复、退出登录；`swift build` 已通过。
- Phase 2 已开始：首页 Dashboard 已接入统计、趋势、直播间、最新批次、黑名单摘要的 API 驱动骨架；macOS `swift build` 已通过。
- 左侧菜单全量纳入范围：首页、直播端、娱乐模式、理货端、订单一键备注、黑名单、充值记录、设置，以及侧边栏底部个人中心/退出、顶部 VIP 支付/手册、模板编辑、打印测试等关联路由。目标是功能和页面按 Web 端完整复刻，不只做首页。
- macOS 直播端已接入平台房间列表、新增/删除房间、开播/结束、弹幕 WebSocket、自动打印配置、弹幕设置和房间打印配置读取。
- macOS 娱乐模式已接入抖音房间列表、事件 WebSocket、礼物统计、事件筛选和互动输出开关。
- macOS 理货端已接入当前/历史批次、历史分页、标签明细分页、搜索、重置编号、加入黑名单。
- macOS 订单备注已接入批次/标签读取、备注字段选择、预览、全量 remarkMap 导出和商家后台打开。
- macOS 黑名单、充值记录、设置、个人中心、支付、打印测试均为原生页面；个人中心已接入昵称/密码/手机号/注销，打印测试已接入 macOS 系统打印队列枚举和 raw 指令发送。
- Windows 已补齐全菜单路由容器和顶部/底部关联入口，选中不同菜单会展示对应功能模块；后续逐个替换为真实 API ViewModel 和完整页面。
- Windows 已接入 WPF 登录/主框架、AuthService、DPAPI Token、MVVM 基础；当前 macOS 环境 restore 卡在 `Microsoft.Windows.SDK.NET.Ref.10.0.19041.56` 下载，完整编译需 Windows + Windows SDK 或可完成 NuGet restore 的网络环境。
