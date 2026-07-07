import AppKit
import OSLog
import SwiftUI

private let routePerformanceLogger = Logger(
    subsystem: "cn.xunjian.fast-sort-client.mac",
    category: "RoutePerformance"
)

struct AppShellView: View {
    let appState: AppState
    let navigationState: NavigationState

    var body: some View {
        HStack(spacing: 0) {
            AppSidebar(
                navigationState: navigationState,
                logout: {
                    Task { await appState.logout() }
                }
            )
            VStack(spacing: 0) {
                AppTopBar(
                    profileName: appState.profileName,
                    vipStatusText: appState.vipStatusText,
                    navigationState: navigationState
                )
                CachedRouteHost(
                    appState: appState,
                    navigationState: navigationState
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(FastSortTheme.groupedBackground)
            }
        }
        .background(FastSortTheme.background)
    }
}

private struct AppSidebar: View {
    let navigationState: NavigationState
    let logout: () -> Void
    @State private var selectedRoute: AppRoute = .dashboard
    @State private var routeListenerID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("拣")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(FastSortTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("迅拣")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FastSortTheme.text)
                    Text("弹幕标签打印")
                        .font(.system(size: 11))
                        .foregroundStyle(FastSortTheme.muted)
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 14)

            VStack(spacing: 4) {
                ForEach(AppRoute.sidebarRoutes) { route in
                    sidebarRouteButton(route)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(spacing: 4) {
                sidebarRouteButton(.profile)
                Button {
                    logout()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 22)
                        Text("退出登录")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(FastSortTheme.muted)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
        .frame(width: FastSortTheme.sidebarWidth)
        .background(FastSortTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(FastSortTheme.border).frame(width: 1)
        }
        .onAppear {
            selectedRoute = navigationState.selectedRoute
            guard routeListenerID == nil else { return }
            routeListenerID = navigationState.addRouteListener(priority: -10) { route in
                selectedRoute = route
            }
        }
        .onDisappear {
            navigationState.removeRouteListener(routeListenerID)
            routeListenerID = nil
        }
    }

    private func sidebarRouteButton(_ route: AppRoute) -> some View {
        let active = selectedRoute == route
        return Button {
            navigationState.navigate(to: route)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: route.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text(route.title)
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(active ? FastSortTheme.accent : FastSortTheme.text.opacity(0.84))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .background(active ? FastSortTheme.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                navigationState.requestPrewarm(route)
            }
        }
    }
}

private struct AppTopBar: View {
    let profileName: String
    let vipStatusText: String
    let navigationState: NavigationState
    @State private var selectedRoute: AppRoute = .dashboard
    @State private var routeListenerID: UUID?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedRoute.title)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(FastSortTheme.text)
                Text(routeSubtitle(selectedRoute))
                    .font(.system(size: 12))
                    .foregroundStyle(FastSortTheme.muted)
            }
            Spacer()
            Button("Manual") {
                openManual()
            }
            .buttonStyle(TopbarTextButtonStyle())
            Button("Upgrade VIP") {
                navigationState.navigate(to: .payment)
            }
            .buttonStyle(VipButtonStyle())
            .onHover { hovering in
                if hovering {
                    navigationState.requestPrewarm(.payment)
                }
            }
            if !profileName.isEmpty {
                Label(profileName, systemImage: "crown.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FastSortTheme.text)
            }
            Text(vipStatusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FastSortTheme.muted)
        }
        .frame(height: 64)
        .padding(.horizontal, FastSortTheme.contentPadding)
        .background(FastSortTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FastSortTheme.border).frame(height: 1)
        }
        .onAppear {
            selectedRoute = navigationState.selectedRoute
            guard routeListenerID == nil else { return }
            routeListenerID = navigationState.addRouteListener(priority: -10) { route in
                selectedRoute = route
            }
        }
        .onDisappear {
            navigationState.removeRouteListener(routeListenerID)
            routeListenerID = nil
        }
    }

    private func openManual() {
        if let url = URL(string: "https://xunjian.org.cn/preview.html") {
            NSWorkspace.shared.open(url)
        }
    }

    private func routeSubtitle(_ route: AppRoute) -> String {
        switch route {
        case .dashboard: return "经营数据、直播间、批次和黑名单概览"
        case .liveRooms: return "管理直播间、弹幕连接和标签打印"
        case .entertainment: return "直播互动事件、礼物和播报控制"
        case .pick: return "查看批次标签、分页检索和黑名单处理"
        case .douyinRemark: return "生成商家后台备注映射并执行批次"
        case .blacklist: return "查看我的/全局黑名单和行为详情"
        case .vipOrder: return "查看会员充值订单"
        case .danmakuCookieTest: return "测试平台登录页、授权状态匹配和 Cookie 采集"
        case .settings: return "配置直播间、模板、理货和黑名单规则"
        case .profile: return "维护账号资料、安全设置和注销流程"
        case .payment: return "选择会员套餐并打开支付"
        case .printerTest: return "枚举系统打印机并发送测试指令"
        }
    }
}

private struct CachedRouteHost: NSViewRepresentable {
    let appState: AppState
    let navigationState: NavigationState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState, navigationState: navigationState)
    }

    func makeNSView(context: Context) -> RouteContainerView {
        let view = RouteContainerView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: RouteContainerView, context: Context) {
        context.coordinator.update(appState: appState, navigationState: navigationState)
    }

    static func dismantleNSView(_ nsView: RouteContainerView, coordinator: Coordinator) {
        nsView.subviews.forEach { $0.removeFromSuperview() }
        coordinator.removeAll()
    }

    @MainActor
    final class Coordinator {
        private var appState: AppState
        private var navigationState: NavigationState
        private weak var container: RouteContainerView?
        private var routeListenerID: UUID?
        private var prewarmListenerID: UUID?
        private var cachedPages: [AppRoute: CachedPageController] = [:]
        private var activeRoute: AppRoute?
        private var lastRouteChangeAt = Date.distantPast
        private var prewarmReadyAt = Date.distantPast
        private var pendingPrewarmRoutes: [AppRoute] = []
        private var prewarmTask: Task<Void, Never>?
        private var activationTask: Task<Void, Never>?
        private var pageBuildTask: Task<Void, Never>?
        private var placeholderViews: [AppRoute: NSView] = [:]

        init(appState: AppState, navigationState: NavigationState) {
            self.appState = appState
            self.navigationState = navigationState
        }

        func attach(to container: RouteContainerView) {
            self.container = container
            installRouteListenerIfNeeded()
            showCurrentRoute()
        }

        func update(appState: AppState, navigationState: NavigationState) {
            self.appState = appState
            if self.navigationState !== navigationState {
                self.navigationState.removeRouteListener(routeListenerID)
                self.navigationState.removePrewarmListener(prewarmListenerID)
                self.navigationState = navigationState
                routeListenerID = nil
                prewarmListenerID = nil
                installRouteListenerIfNeeded()
            }
            showCurrentRoute()
        }

        private func installRouteListenerIfNeeded() {
            guard routeListenerID == nil else { return }
            routeListenerID = navigationState.addRouteListener(priority: 100) { [weak self] route in
                self?.show(route: route)
            }
            prewarmListenerID = navigationState.addPrewarmListener { [weak self] route in
                self?.requestPrewarm(route)
            }
        }

        private func showCurrentRoute() {
            show(route: navigationState.selectedRoute)
        }

        private func show(route: AppRoute) {
            guard let container else { return }
            show(
                route: route,
                in: container,
                appState: appState,
                navigate: navigationState.navigate(to:)
            )
        }

        func show(
            route: AppRoute,
            in container: RouteContainerView,
            appState: AppState,
            navigate: @escaping (AppRoute) -> Void
        ) {
            let routeChanged = activeRoute != route
            if !routeChanged, let activeView = cachedPages[route]?.controller.view {
                container.activeView = activeView
                activeView.frame = container.bounds
                return
            }
            if !routeChanged, cachedPages[route] == nil {
                schedulePageBuild(route: route, in: container, appState: appState, navigate: navigate)
                return
            }

            if routeChanged {
                lastRouteChangeAt = Date()
                postponePrewarm(by: 0.45)
                pendingPrewarmRoutes.removeAll()
                activationTask?.cancel()
                activationTask = nil
                pageBuildTask?.cancel()
                pageBuildTask = nil
            }

            if let page = cachedPages[route] {
                showCachedPage(page, route: route, in: container, source: "cached")
                schedulePrewarm(excluding: route, in: container, appState: appState, navigate: navigate)
                return
            }

            if container.activeView == nil {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false

                    let placeholder = placeholderView(for: route)
                    if placeholder.superview !== container {
                        placeholder.translatesAutoresizingMaskIntoConstraints = true
                        placeholder.autoresizingMask = [.width, .height]
                        container.addSubview(placeholder)
                    }
                    showActiveView(placeholder, in: container)
                    container.activeView = placeholder
                    container.needsLayout = true
                }
            }
            activeRoute = route
            schedulePageBuild(route: route, in: container, appState: appState, navigate: navigate)
        }

        func removeAll() {
            navigationState.removeRouteListener(routeListenerID)
            navigationState.removePrewarmListener(prewarmListenerID)
            routeListenerID = nil
            prewarmListenerID = nil
            pageBuildTask?.cancel()
            pageBuildTask = nil
            activationTask?.cancel()
            activationTask = nil
            prewarmTask?.cancel()
            prewarmTask = nil
            pendingPrewarmRoutes.removeAll()
            activeRoute = nil
            placeholderViews.removeAll()
            cachedPages.removeAll()
        }

        private func pageController(
            for route: AppRoute,
            appState: AppState,
            navigate: @escaping (AppRoute) -> Void
        ) -> CachedPageController {
            if let cached = cachedPages[route] {
                return cached
            }

            let activation = PageActivationState()
            let rootView = CachedRoutePage(route: route, navigate: navigate)
                .environmentObject(appState)
                .environmentObject(activation)
            let controller = NSHostingController(rootView: AnyView(rootView))
            controller.view.wantsLayer = true
            controller.view.layer?.backgroundColor = NSColor.clear.cgColor
            controller.view.layer?.actions = Self.disabledLayerActions
            let cached = CachedPageController(controller: controller, activation: activation)
            cachedPages[route] = cached
            return cached
        }

        private func showCachedPage(
            _ page: CachedPageController,
            route: AppRoute,
            in container: RouteContainerView,
            source: String
        ) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false

                if page.controller.view.superview !== container {
                    page.controller.view.translatesAutoresizingMaskIntoConstraints = true
                    page.controller.view.autoresizingMask = [.width, .height]
                    container.addSubview(page.controller.view)
                }
                if let currentView = container.activeView, currentView !== page.controller.view {
                    parkInactiveView(currentView)
                }
                showActiveView(page.controller.view, in: container)
                activeRoute = route
                container.activeView = page.controller.view
                container.needsLayout = true
                scheduleActivation(for: route)
                logRouteDisplayed(route: route, source: source)
            }
        }

        private func logRouteDisplayed(route: AppRoute, source: String) {
            guard route == navigationState.selectedRoute else { return }
            let startedAt = navigationState.lastNavigationStartedAt
            guard startedAt > Date.distantPast.addingTimeInterval(1) else { return }
            let elapsedMs = Date().timeIntervalSince(startedAt) * 1_000
            routePerformanceLogger.notice(
                "route_displayed route=\(route.rawValue, privacy: .public) source=\(source, privacy: .public) elapsed_ms=\(elapsedMs, format: .fixed(precision: 1), privacy: .public)"
            )
            if ProcessInfo.processInfo.environment["FAST_SORT_ROUTE_PERF_SMOKE"] == "1" {
                let message = String(
                    format: "route_displayed route=%@ source=%@ elapsed_ms=%.1f",
                    route.rawValue,
                    source,
                    elapsedMs
                )
                if let data = "\(message)\n".data(using: .utf8) {
                    FileHandle.standardOutput.write(data)
                }
            }
        }

        private func schedulePageBuild(
            route: AppRoute,
            in container: RouteContainerView,
            appState: AppState,
            navigate: @escaping (AppRoute) -> Void
        ) {
            pageBuildTask?.cancel()
            pageBuildTask = Task { @MainActor [weak self, weak container] in
                await Task.yield()
                guard !Task.isCancelled, let self, let container, activeRoute == route else { return }
                let page = pageController(for: route, appState: appState, navigate: navigate)
                guard !Task.isCancelled, activeRoute == route else { return }
                showCachedPage(page, route: route, in: container, source: "built")
                schedulePrewarm(excluding: route, in: container, appState: appState, navigate: navigate)
                self.pageBuildTask = nil
            }
        }

        private func placeholderView(for route: AppRoute) -> NSView {
            if let view = placeholderViews[route] {
                return view
            }
            let view = NSView(frame: .zero)
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.actions = Self.disabledLayerActions
            placeholderViews[route] = view
            return view
        }

        private func showActiveView(_ view: NSView, in container: RouteContainerView) {
            view.translatesAutoresizingMaskIntoConstraints = true
            view.autoresizingMask = [.width, .height]
            view.isHidden = false
            view.alphaValue = 1
            view.frame = container.bounds
            view.layer?.zPosition = 1
        }

        private func parkInactiveView(_ view: NSView) {
            view.alphaValue = 0
            view.isHidden = true
            view.autoresizingMask = []
            view.layer?.zPosition = 0
        }

        private func warmInactiveView(_ view: NSView, in container: RouteContainerView) {
            view.translatesAutoresizingMaskIntoConstraints = true
            view.autoresizingMask = []
            view.isHidden = false
            view.alphaValue = 0
            view.layer?.zPosition = 0
            if !container.bounds.isEmpty {
                view.frame = container.bounds
                view.needsLayout = true
                view.layoutSubtreeIfNeeded()
            }
            parkInactiveView(view)
        }

        private func scheduleActivation(for route: AppRoute) {
            activationTask?.cancel()
            activationTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, activeRoute == route else { return }
                cachedPages[route]?.activation.setActive(true)
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled, activeRoute == route else { return }
                for (cachedRoute, cachedPage) in cachedPages where cachedRoute != route {
                    cachedPage.activation.setActive(false)
                }
                self.activationTask = nil
            }
        }

        private func schedulePrewarm(
            excluding activeRoute: AppRoute,
            in container: RouteContainerView,
            appState: AppState,
            navigate: @escaping (AppRoute) -> Void
        ) {
            let routes = Self.prewarmTargets(after: activeRoute)
                .filter { $0 != activeRoute && cachedPages[$0] == nil }
            enqueuePrewarmRoutes(routes)
            startPrewarmQueue(in: container, appState: appState, navigate: navigate)
        }

        private func requestPrewarm(_ route: AppRoute) {
            guard let container else { return }
            guard route != activeRoute, cachedPages[route] == nil else { return }
            enqueuePrewarmRoutes([route])
            pullPrewarmForward(by: 0.08)
            startPrewarmQueue(in: container, appState: appState, navigate: navigationState.navigate(to:))
        }

        private func startPrewarmQueue(
            in container: RouteContainerView,
            appState: AppState,
            navigate: @escaping (AppRoute) -> Void
        ) {
            guard prewarmTask == nil, !pendingPrewarmRoutes.isEmpty else { return }
            prewarmTask = Task { @MainActor [weak self, weak container] in
                while !Task.isCancelled {
                    guard let self, let container else { return }
                    await waitForPrewarmIdle()
                    guard !Task.isCancelled else { return }
                    guard !pendingPrewarmRoutes.isEmpty else { break }
                    let route = pendingPrewarmRoutes.removeFirst()
                    guard route != self.activeRoute, cachedPages[route] == nil else { continue }
                    let page = pageController(for: route, appState: appState, navigate: navigate)
                    page.activation.setActive(false)
                    if page.controller.view.superview !== container {
                        page.controller.view.translatesAutoresizingMaskIntoConstraints = true
                        container.addSubview(page.controller.view)
                    }
                    warmInactiveView(page.controller.view, in: container)
                    try? await Task.sleep(nanoseconds: 90_000_000)
                }
                self?.prewarmTask = nil
            }
        }

        private func postponePrewarm(by interval: TimeInterval) {
            prewarmReadyAt = Date().addingTimeInterval(interval)
        }

        private func pullPrewarmForward(by interval: TimeInterval) {
            let target = Date().addingTimeInterval(interval)
            if prewarmReadyAt <= Date() || target < prewarmReadyAt {
                prewarmReadyAt = target
            }
        }

        private func enqueuePrewarmRoutes(_ routes: [AppRoute]) {
            let filtered = routes.filter { route in
                cachedPages[route] == nil && !pendingPrewarmRoutes.contains(route)
            }
            guard !filtered.isEmpty else { return }
            pendingPrewarmRoutes = filtered + pendingPrewarmRoutes
        }

        private func waitForPrewarmIdle() async {
            while !Task.isCancelled {
                let routeReadyAt = lastRouteChangeAt.addingTimeInterval(0.45)
                let readyAt = prewarmReadyAt > routeReadyAt ? prewarmReadyAt : routeReadyAt
                let remaining = readyAt.timeIntervalSinceNow
                if remaining <= 0 {
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(min(0.05, remaining) * 1_000_000_000))
            }
        }

        private static let disabledLayerActions: [String: CAAction] = [
            "bounds": NSNull(),
            "frame": NSNull(),
            "position": NSNull(),
            "opacity": NSNull(),
            "sublayers": NSNull()
        ]

        private static func prewarmTargets(after route: AppRoute) -> [AppRoute] {
            let priority: [AppRoute]
            switch route {
            case .dashboard:
                priority = [.liveRooms, .pick, .blacklist]
            case .liveRooms:
                priority = [.pick, .entertainment]
            case .entertainment:
                priority = [.liveRooms, .pick]
            case .pick:
                priority = [.liveRooms, .blacklist, .douyinRemark]
            case .douyinRemark:
                priority = [.pick, .settings]
            case .blacklist:
                priority = [.pick, .dashboard]
            case .vipOrder:
                priority = [.payment, .profile]
            case .danmakuCookieTest:
                priority = [.liveRooms, .settings]
            case .settings:
                priority = [.printerTest, .liveRooms]
            case .profile:
                priority = [.settings, .payment]
            case .payment:
                priority = [.vipOrder, .profile]
            case .printerTest:
                priority = [.settings]
            }
            return priority
        }

        private struct CachedPageController {
            let controller: NSHostingController<AnyView>
            let activation: PageActivationState
        }
    }
}

private final class RouteContainerView: NSView {
    weak var activeView: NSView?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        activeView?.frame = bounds
    }

}

private struct CachedRoutePage: View {
    let route: AppRoute
    let navigate: (AppRoute) -> Void

    @ViewBuilder
    var body: some View {
        switch route {
        case .dashboard:
            DashboardView { nextRoute in
                navigate(nextRoute)
            }
        case .liveRooms:
            LiveRoomsView()
        case .entertainment:
            EntertainmentModeView()
        case .pick:
            PickView()
        case .douyinRemark:
            DouyinRemarkView()
        case .blacklist:
            BlacklistView()
        case .vipOrder:
            VipOrderView()
        case .danmakuCookieTest:
            DanmakuCookieTestView()
        case .settings:
            SettingsView {
                navigate(.printerTest)
            }
        case .profile:
            ProfileView()
        case .payment:
            PaymentView()
        case .printerTest:
            PrinterTestView()
        }
    }
}

struct AccentOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(FastSortTheme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(FastSortTheme.surface.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(FastSortTheme.accent.opacity(0.3), lineWidth: 1)
            }
    }
}

struct TopbarTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(FastSortTheme.accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(FastSortTheme.surface.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(FastSortTheme.accent.opacity(0.22), lineWidth: 1)
            }
    }
}

struct VipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background((configuration.isPressed ? FastSortTheme.accentDark : FastSortTheme.accent))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .shadow(color: FastSortTheme.accentShadow, radius: 8, x: 0, y: 4)
    }
}
