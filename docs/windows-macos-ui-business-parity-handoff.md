# Windows macOS UI/Business Parity Handoff

更新日期：2026-07-08

本文档给 Windows 电脑上的 Codex 使用。目标不是“参考 macOS 大致改一下”，而是以当前 macOS 客户端为唯一事实来源，逐页面、逐业务流程复刻到 Windows WPF/WebView2 客户端。

## 运行 Codex 的方式

Windows 电脑上的 Codex 必须打开 Git 仓库根目录：

```text
fast-sort-client
```

不要只打开：

```text
clients/windows/FastSort.Client.Windows
```

原因：macOS 源码在同一个仓库的 `clients/macos/FastSortClientMac` 下。如果 Codex workspace 只指向 Windows 子目录，它看不到 macOS SwiftUI 代码，只能按旧 Windows 代码猜 UI 和业务。

Windows 侧先执行：

```powershell
git pull origin main
dotnet build clients/windows/FastSort.Client.Windows/FastSort.Client.Windows.csproj
dotnet run --project clients/windows/FastSort.Client.Windows/FastSort.Client.Windows.csproj
```

## macOS 参照源文件

Windows Codex 开始改代码前，必须先读取这些 macOS 文件，并把页面结构、状态、按钮、文案、业务动作整理成对照表。

主题和壳层：

```text
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Theme/FastSortTheme.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/RootView.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/AppShellView.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/AppState.swift
```

登录和首页：

```text
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/LoginView.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/DashboardView.swift
```

核心直播业务：

```text
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/DanmakuCookieTestView.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/LiveRoomsView.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/DanmakuPlatformRegistry.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/DanmakuWebAuthSessionStore.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/DanmakuCookieSessionParser.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/Danmaku/NativeDanmakuSessionCoordinator.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/Danmaku/NativeDanmakuAdapterFactory.swift
```

业务页面：

```text
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/FeatureViews.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/PickView.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/FeatureServices.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/PickService.swift
clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/LiveRoomsService.swift
```

## Windows 目标文件

Windows 侧主要改这些文件：

```text
clients/windows/FastSort.Client.Windows/App.xaml
clients/windows/FastSort.Client.Windows/MainWindow.xaml
clients/windows/FastSort.Client.Windows/MainWindow.xaml.cs
clients/windows/FastSort.Client.Windows/ViewModels/MainViewModel.cs
clients/windows/FastSort.Client.Windows/ViewModels/DashboardViewModel.cs
clients/windows/FastSort.Client.Windows/ViewModels/DanmakuCookieTestViewModel.cs
clients/windows/FastSort.Client.Windows/ViewModels/LiveRoomsViewModel.cs
clients/windows/FastSort.Client.Windows/ViewModels/BusinessPageViewModel.cs
clients/windows/FastSort.Client.Windows/Views/DanmakuCookieTestView.xaml
clients/windows/FastSort.Client.Windows/Views/DanmakuCookieTestView.xaml.cs
clients/windows/FastSort.Client.Windows/Views/LiveRoomsView.xaml
clients/windows/FastSort.Client.Windows/Views/LiveRoomsView.xaml.cs
clients/windows/FastSort.Client.Windows/Views/BusinessPageView.xaml
clients/windows/FastSort.Client.Windows/Views/BusinessPageView.xaml.cs
```

业务协议、Cookie 和 adapter 已有 Windows 迁移基础。除非页面复刻需要，不要先大改服务层：

```text
clients/windows/FastSort.Client.Windows/Core/Api
clients/windows/FastSort.Client.Windows/Core/Danmaku
```

## 必须先产出的对照表

Windows Codex 不要直接开始写 XAML。先在自己的回复或临时笔记里列出以下对照表，再改代码：

| macOS 页面 | macOS 文件 | Windows 当前文件 | 差异 | 本轮动作 |
| --- | --- | --- | --- | --- |
| 登录页 | `LoginView.swift` | `MainWindow.xaml` | 视觉、按钮、输入布局 | 逐项复刻 |
| 应用壳层 | `AppShellView.swift` | `MainWindow.xaml` | 侧栏、顶部栏、路由、会员入口 | 逐项复刻 |
| 首页 | `DashboardView.swift` | `MainWindow.xaml` / `DashboardViewModel.cs` | 卡片、指标、列表 | 逐项复刻 |
| 直播授权测试 | `DanmakuCookieTestView.swift` | `DanmakuCookieTestView.xaml` | 三栏布局、弹窗、Cookie 表、弹幕列表 | 逐项复刻 |
| 直播端 | `LiveRoomsView.swift` | `LiveRoomsView.xaml` | 房间列表、授权区、弹幕区、打印状态 | 逐项复刻 |
| 娱乐模式 | `FeatureViews.swift` | `BusinessPageView.xaml` | 当前 Windows 过于通用 | 拆成接近 mac 的专用 UI |
| 理货端 | `PickView.swift` | `BusinessPageView.xaml` | 当前 Windows 过于通用 | 拆成接近 mac 的专用 UI |
| 黑名单/充值/设置/个人中心 | `FeatureViews.swift` | `BusinessPageView.xaml` | 当前 Windows 过于通用 | 按 mac 模块拆专用区块 |

## 复刻原则

1. macOS 是唯一目标。不要按 Windows 当前页面继续微调。
2. 保留 Windows 必需技术差异：SwiftUI 对应 WPF，WKWebView 对应 WebView2，Keychain 对应 Windows token store。
3. 页面信息架构必须一致：侧栏顺序、顶部栏、按钮位置、状态提示、空态、列表字段、弹幕事件展示都要对齐。
4. 中文文案以 macOS 为准。Windows 不要出现旧英文按钮或临时调试文案。
5. 不要把所有业务都塞进一个通用 DataGrid。macOS 有专用页面结构的，Windows 也要拆出专用布局。
6. 不改变已跑通的 native adapter 业务路径：抖音、小红书、视频号授权测试页已能登录、采集 Cookie、连接弹幕。
7. 不恢复外部 Python 服务依赖。
8. 不依赖或分析 `BarrageGrab` 仓库。

## 分阶段执行

### 阶段 1：壳层和主题

目标：Windows 打开后第一眼应与 macOS 结构一致。

- 读取 `FastSortTheme.swift`，把颜色、字号、圆角、间距迁到 `App.xaml`。
- 读取 `AppShellView.swift`，重做 `MainWindow.xaml` 的侧栏、顶部栏、路由、个人中心、退出登录。
- 保证窗口缩放时文本不溢出，不出现横向乱滚。

验收：

- 路由顺序和 macOS 一致。
- 顶部栏标题、副标题、Manual、Upgrade VIP、会员状态一致。
- 侧栏不再是旧 Windows 风格。

### 阶段 2：登录页和首页

目标：登录流程和首页信息密度对齐 macOS。

- 对照 `LoginView.swift` 重做登录卡片、验证码/账号登录、错误提示。
- 对照 `DashboardView.swift` 重做首页指标卡、直播间概览、业务入口。
- 后端接口不变，只改展示和 ViewModel 状态。

验收：

- 登录成功后进入同样的业务壳层。
- 首页字段、空态、加载态和 macOS 接近。

### 阶段 3：直播授权测试页

目标：这是当前最重要页面，Windows 必须与 macOS 体验一致。

- 对照 `DanmakuCookieTestView.swift` 重做平台列表、当前配置、登录窗口、Cookie 采集结果、弹幕展示。
- 平台登录页必须是独立窗口或与 macOS 当前策略一致；关闭平台窗口不能导致主客户端闪退。
- 保留 WebView2 Cookie 采集能力。
- 保留抖音、小红书、视频号已跑通的 native adapter 连接。
- 不显示“保存到迅拣直播间”这类当前测试阶段不需要的入口，除非 macOS 当前页面也显示。

验收：

- 抖音工作台登录后，在授权测试页连接弹幕可收到评论。
- 小红书 ark/直播中控登录后可收到评论。
- 视频号助手登录后可收到评论。
- 关闭平台独立窗口，主应用不闪退。

### 阶段 4：直播端

目标：正式直播间页对齐 macOS。

- 对照 `LiveRoomsView.swift` 还原房间列表、授权保存、连接状态、弹幕事件、打印触发。
- 正式连接只从后台房间 `liveSession` 取 Cookie。
- 不依赖授权测试页临时状态。

验收：

- 房间列表字段和状态与 macOS 一致。
- 保存 Cookie、刷新房间、连接弹幕、断开连接行为一致。

### 阶段 5：业务页拆分

目标：不要继续用一个临时通用 DataGrid 糊所有模块。

- 对照 `FeatureViews.swift` 和 `PickView.swift`，把娱乐模式、理货端、黑名单、充值记录、设置、个人中心、支付、打印测试拆成更接近 macOS 的专用 UI 区块。
- 可以共用基础控件和样式，但每个页面的信息结构必须按 macOS 复刻。

验收：

- 主要按钮、输入框、表格/列表字段与 macOS 对齐。
- 旧的“通用后台管理表格感”明显减少。

## Windows Codex 可直接使用的指令

把下面整段发给 Windows 电脑上的 Codex：

```text
你现在在 fast-sort-client 仓库根目录工作，不要只打开 clients/windows 子目录。

最终目标：以 macOS 客户端为唯一参照，把 Windows WPF/WebView2 客户端的 UI 和业务流程逐页面复刻到接近 macOS 当前实现。不要只做局部美化，不要继续沿用旧 Windows 通用 DataGrid 页面。

必须先完整阅读：
- docs/windows-macos-ui-business-parity-handoff.md
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Theme/FastSortTheme.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/RootView.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/AppShellView.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/LoginView.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/DashboardView.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/DanmakuCookieTestView.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/LiveRoomsView.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/FeatureViews.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Views/PickView.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/DanmakuPlatformRegistry.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/DanmakuWebAuthSessionStore.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/DanmakuCookieSessionParser.swift
- clients/macos/FastSortClientMac/Sources/FastSortClientMac/Services/Danmaku/NativeDanmakuSessionCoordinator.swift

然后读取 Windows 当前实现：
- clients/windows/FastSort.Client.Windows/App.xaml
- clients/windows/FastSort.Client.Windows/MainWindow.xaml
- clients/windows/FastSort.Client.Windows/ViewModels/MainViewModel.cs
- clients/windows/FastSort.Client.Windows/Views/DanmakuCookieTestView.xaml
- clients/windows/FastSort.Client.Windows/ViewModels/DanmakuCookieTestViewModel.cs
- clients/windows/FastSort.Client.Windows/Views/LiveRoomsView.xaml
- clients/windows/FastSort.Client.Windows/ViewModels/LiveRoomsViewModel.cs
- clients/windows/FastSort.Client.Windows/Views/BusinessPageView.xaml
- clients/windows/FastSort.Client.Windows/ViewModels/BusinessPageViewModel.cs

先输出 macOS 页面到 Windows 文件的差异对照表和执行顺序，然后按阶段持续实现直到验收清单满足：
1. 壳层/主题/侧栏/顶部栏复刻 macOS。
2. 登录页和首页复刻 macOS。
3. 直播授权测试页复刻 macOS，且抖音、小红书、视频号能继续登录采集 Cookie 并连接弹幕。
4. 直播端复刻 macOS，正式连接只从后台房间 liveSession 取 Cookie。
5. 娱乐模式、理货端、订单备注、黑名单、充值记录、设置、个人中心、支付、打印测试按 macOS 页面拆分，不再依赖一个通用临时 DataGrid。

约束：
- 不改后端接口。
- 不引入外部 Python 弹幕服务。
- 不分析 BarrageGrab。
- 不破坏已经跑通的抖音、小红书、视频号 native adapter。
- 每完成一个阶段运行 dotnet build clients/windows/FastSort.Client.Windows/FastSort.Client.Windows.csproj。
- 最终提交并 push，说明 Windows 实机需要验证的入口。
```

## macOS 截图参照

已提交 macOS 当前界面截图到：

```text
docs/parity-screenshots/macos/
```

Windows Codex 应先阅读：

```text
docs/parity-screenshots/macos/README.md
```

当前截图覆盖：

```text
dashboard.png
live-rooms.png
entertainment.png
pick.png
order-remark.png
blacklist.png
vip-orders.png
danmaku-auth.png
```

Windows Codex 应把截图、macOS 源码、Windows 当前页面三者放在一起对照改。截图用于视觉和信息架构参照；具体业务状态、接口字段和事件流仍以 macOS 源码为准。

当前缺口：

- `settings.png` 未提交。
- `profile.png` 未提交。
- 登录页截图未提交，避免影响当前已登录生产会话；登录页仍以 `LoginView.swift` 为准。

## Windows 进度记录

### 2026-07-08

- 已执行 `git pull origin main`，当前 main 已是最新。
- Windows 壳层继续使用 macOS 主题色、224px 侧栏、64px 顶部栏、Manual/Upgrade VIP/会员状态结构。
- `MainWindow.xaml` 的内容区已切到专用页面控件，不再把正式业务路由挂到 `BusinessPageView.xaml`。
- 已新增 `DashboardView.xaml`，首页按 macOS 的五个指标卡、报表、最新批次、直播间、黑名单区块拆分。
- 已重排 `LiveRoomsView.xaml`，直播端按房间列表、当前直播间、弹幕面板、打印机、添加直播间授权区域组织；WebView2 Cookie 采集、保存 liveSession、native adapter 连接命令保持原路径。
- `DanmakuCookieTestView.xaml` 保留 WebView2 Cookie 采集和 native adapter 连接能力，弹幕展示改为 macOS 风格卡片流。
- 已新增专用业务页面：
  - `EntertainmentView.xaml`
  - `PickView.xaml`
  - `OrderRemarkView.xaml`
  - `BlacklistView.xaml`
  - `VipOrdersView.xaml`
  - `SettingsView.xaml`
  - `ProfileView.xaml`
  - `PaymentView.xaml`
  - `PrinterTestView.xaml`
- `BusinessPageView.xaml` / `BusinessPageView.xaml.cs` 已删除；`BusinessPageViewModel.cs` 暂作为共享业务数据和命令层保留，避免改动后端 API 和 native adapter。
- 已运行多轮 `dotnet build clients/windows/FastSort.Client.Windows/FastSort.Client.Windows.csproj`，当前通过。
