import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    let navigationState: NavigationState
    @State private var didRunRouteSmoke = false

    private var isRoutePerformanceSmokeEnabled: Bool {
        ProcessInfo.processInfo.environment["FAST_SORT_ROUTE_PERF_SMOKE"] == "1"
    }

    var body: some View {
        Group {
            if appState.isRestoringSession {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在恢复登录状态")
                        .foregroundStyle(FastSortTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.isAuthenticated || isRoutePerformanceSmokeEnabled {
                AppShellView(appState: appState, navigationState: navigationState)
            } else {
                LoginView()
            }
        }
        .background(FastSortTheme.background)
        .task {
            guard !isRoutePerformanceSmokeEnabled else { return }
            await appState.restoreSession()
        }
        .task(id: appState.isAuthenticated) {
            await runRoutePerformanceSmokeIfNeeded()
        }
        .onChange(of: appState.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                navigationState.reset()
            }
        }
    }

    @MainActor
    private func runRoutePerformanceSmokeIfNeeded() async {
        guard appState.isAuthenticated || isRoutePerformanceSmokeEnabled else { return }
        guard !didRunRouteSmoke else { return }
        guard isRoutePerformanceSmokeEnabled else { return }
        didRunRouteSmoke = true

        let routes: [AppRoute] = [
            .liveRooms,
            .entertainment,
            .pick,
            .douyinRemark,
            .blacklist,
            .vipOrder,
            .danmakuCookieTest,
            .settings,
            .profile,
            .payment,
            .printerTest,
            .dashboard
        ]
        writeSmokeLine("route_smoke_cold_start")
        try? await Task.sleep(nanoseconds: 220_000_000)
        for route in routes {
            navigationState.navigate(to: route)
            try? await Task.sleep(nanoseconds: 220_000_000)
        }
        writeSmokeLine("route_smoke_cold_end")

        writeSmokeLine("route_smoke_cached_start")
        try? await Task.sleep(nanoseconds: 260_000_000)
        for route in routes {
            navigationState.requestPrewarm(route)
            try? await Task.sleep(nanoseconds: 140_000_000)
            navigationState.navigate(to: route)
            try? await Task.sleep(nanoseconds: 650_000_000)
        }
        for route in routes {
            navigationState.navigate(to: route)
            try? await Task.sleep(nanoseconds: 260_000_000)
        }
        writeSmokeLine("route_smoke_cached_end")

        if ProcessInfo.processInfo.environment["FAST_SORT_ROUTE_PERF_SMOKE_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func writeSmokeLine(_ message: String) {
        if let data = "\(message)\n".data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
    }
}
