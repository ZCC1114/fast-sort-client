import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var token: String = ""
    @Published var profileName: String = ""
    @Published var vipStatusText: String = "未开通 VIP"
    @Published var currentUserId: String = ""
    @Published var isPaidVip = false
    @Published var isVipActive = false
    @Published var isRestoringSession = false

    private let tokenStore = SecureTokenStore()
    private var didAttemptRestore = false

    var isAuthenticated: Bool {
        !token.isEmpty
    }

    func restoreSession() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        isRestoringSession = true
        defer { isRestoringSession = false }

        guard let storedToken = tokenStore.load(), !storedToken.isEmpty else {
            return
        }

        token = storedToken
        do {
            let profile = try await makeAuthService().getProfile()
            applyProfile(profile)
        } catch {
            clearLocalSession()
        }
    }

    func sendLoginCaptcha(phone: String) async throws {
        try await AuthService(apiClient: APIClient()).generateCaptcha(phone: normalizedPhone(phone))
    }

    func loginWithSMS(phone: String, captcha: String) async throws {
        let cleanPhone = normalizedPhone(phone)
        let result = try await AuthService(apiClient: APIClient()).captchaLogin(phone: cleanPhone, captcha: captcha)
        try await completeLogin(result: result)
    }

    func loginWithAccount(phone: String, password: String) async throws {
        let cleanPhone = normalizedPhone(phone)
        let result = try await AuthService(apiClient: APIClient()).accountLogin(username: cleanPhone, password: password)
        try await completeLogin(result: result)
    }

    func logout() async {
        if isAuthenticated {
            try? await makeAuthService().logout()
        }
        clearLocalSession()
    }

    func normalizedPhone(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"^\s*86\s*"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func makeAPIClient() -> APIClient {
        APIClient(bearerToken: token)
    }

    private func makeAuthService() -> AuthService {
        AuthService(apiClient: makeAPIClient())
    }

    private func completeLogin(result: LoginResponse) async throws {
        guard let newToken = result.token, !newToken.isEmpty else {
            throw APIError.emptyData
        }

        token = newToken
        do {
            try tokenStore.save(newToken)
            let profile = try await makeAuthService().getProfile()
            applyProfile(profile)
        } catch {
            clearLocalSession()
            throw error
        }
    }

    private func applyProfile(_ profile: ProfileResponse) {
        profileName = profile.user?.displayName ?? "迅拣用户"
        currentUserId = profile.user?.id ?? ""
        isPaidVip = profile.vip?.vipFlag?.value == 1
        isVipActive = profile.vip?.vipFlag?.value == 1 || profile.vip?.freeVipFlag?.value == 1
        vipStatusText = Self.vipStatusText(profile.vip)
    }

    private func clearLocalSession() {
        tokenStore.clear()
        token = ""
        profileName = ""
        currentUserId = ""
        isPaidVip = false
        isVipActive = false
        vipStatusText = "未开通 VIP"
    }

    private static func vipStatusText(_ vip: VipProfile?) -> String {
        guard let vip else { return "未开通 VIP" }

        if vip.vipFlag?.value == 1 {
            let days = remainingDays(endTime: vip.vipEndTime) ?? vip.vipRemainingDays?.value
            return "会员剩余\(days.map(String.init) ?? "-")天"
        }

        if vip.freeVipFlag?.value == 1 {
            let days = remainingDays(endTime: vip.freeVipEndTime) ?? vip.freeVipRemainingDays?.value
            return "免费会员剩余\(days.map(String.init) ?? "-")天"
        }

        return "未开通 VIP"
    }

    private static func remainingDays(endTime: String?) -> Int? {
        guard let endTime, !endTime.isEmpty, let date = parseDate(endTime) else {
            return nil
        }
        let seconds = date.timeIntervalSince(Date())
        return max(0, Int(ceil(seconds / 86_400)))
    }

    private static func parseDate(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}

@MainActor
final class NavigationState: ObservableObject {
    private(set) var selectedRoute: AppRoute = .dashboard
    private(set) var lastNavigationStartedAt = Date.distantPast
    private var routeListeners: [UUID: RouteListener] = [:]
    private var prewarmListeners: [UUID: PrewarmListener] = [:]

    func navigate(to route: AppRoute) {
        guard selectedRoute != route else { return }
        lastNavigationStartedAt = Date()
        selectedRoute = route
        routeListeners.values
            .sorted { $0.priority > $1.priority }
            .forEach { listener in
                listener.handler(route)
            }
    }

    func reset() {
        navigate(to: .dashboard)
    }

    @discardableResult
    func addRouteListener(priority: Int = 0, _ listener: @escaping @MainActor (AppRoute) -> Void) -> UUID {
        let id = UUID()
        routeListeners[id] = RouteListener(priority: priority, handler: listener)
        return id
    }

    func removeRouteListener(_ id: UUID?) {
        guard let id else { return }
        routeListeners.removeValue(forKey: id)
    }

    func requestPrewarm(_ route: AppRoute) {
        guard selectedRoute != route else { return }
        prewarmListeners.values.forEach { listener in
            listener.handler(route)
        }
    }

    @discardableResult
    func addPrewarmListener(_ listener: @escaping @MainActor (AppRoute) -> Void) -> UUID {
        let id = UUID()
        prewarmListeners[id] = PrewarmListener(handler: listener)
        return id
    }

    func removePrewarmListener(_ id: UUID?) {
        guard let id else { return }
        prewarmListeners.removeValue(forKey: id)
    }

    private struct RouteListener {
        let priority: Int
        let handler: @MainActor (AppRoute) -> Void
    }

    private struct PrewarmListener {
        let handler: @MainActor (AppRoute) -> Void
    }
}

@MainActor
final class PageActivationState: ObservableObject {
    @Published var isActive = false

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
    }

    func waitForFirstInteractiveFrame(nanoseconds: UInt64 = 120_000_000) async -> Bool {
        guard isActive else { return false }
        await Task.yield()
        try? await Task.sleep(nanoseconds: nanoseconds)
        return isActive && !Task.isCancelled
    }
}

enum AppRoute: String, CaseIterable, Identifiable {
    case dashboard
    case liveRooms
    case entertainment
    case pick
    case douyinRemark
    case blacklist
    case vipOrder
    case danmakuCookieTest
    case settings
    case profile
    case payment
    case printerTest

    var id: String { rawValue }

    static let sidebarRoutes: [AppRoute] = [
        .dashboard,
        .liveRooms,
        .entertainment,
        .pick,
        .douyinRemark,
        .blacklist,
        .vipOrder,
        .danmakuCookieTest,
        .settings
    ]

    var title: String {
        switch self {
        case .dashboard: return "首页"
        case .liveRooms: return "直播端"
        case .entertainment: return "娱乐模式"
        case .pick: return "理货端"
        case .douyinRemark: return "订单一键备注"
        case .blacklist: return "黑名单"
        case .vipOrder: return "充值记录"
        case .danmakuCookieTest: return "直播授权测试"
        case .settings: return "设置"
        case .profile: return "个人中心"
        case .payment: return "支付"
        case .printerTest: return "打印测试"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .liveRooms: return "play.rectangle.fill"
        case .entertainment: return "sparkles.tv.fill"
        case .pick: return "tag.fill"
        case .douyinRemark: return "text.bubble.fill"
        case .blacklist: return "person.crop.circle.badge.xmark"
        case .vipOrder: return "crown.fill"
        case .danmakuCookieTest: return "network.badge.shield.half.filled"
        case .settings: return "line.3.horizontal"
        case .profile: return "person.crop.circle.fill"
        case .payment: return "creditcard.fill"
        case .printerTest: return "printer.fill"
        }
    }
}
