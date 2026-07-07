import AppKit
import CryptoKit
import Foundation
import SwiftUI
import WebKit

struct DanmakuCookieTestView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DanmakuCookieTestViewModel()

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 16) {
                controlPanel
                    .frame(width: 360)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 14) {
                    browserPanel
                        .frame(height: max(300, proxy.size.height * 0.44))
                    cookiePanel
                        .frame(maxWidth: .infinity)
                    danmuPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.top, 20)
            .macPagePadding()
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .onAppear {
            viewModel.prepareInitialLoad()
        }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("平台授权测试")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FastSortTheme.text)
                Text("按弹幕捕手的平台注册表打开登录页，登录后从当前 WebKit 会话采集平台 Cookie。")
                    .font(.system(size: 12))
                    .foregroundStyle(FastSortTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(DanmakuPlatform.all) { platform in
                    platformButton(platform)
                }
            }

            Divider()

            selectedPlatformInfo

            HStack(spacing: 10) {
                Button("打开登录页") {
                    viewModel.loadSelectedPlatform()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("清空会话") {
                    viewModel.clearSession()
                }
                .buttonStyle(AccentOutlineButtonStyle())
            }

            Button("手动采集 Cookie") {
                viewModel.collectCookies(trigger: "手动采集")
            }
            .buttonStyle(AccentOutlineButtonStyle())
            .disabled(viewModel.isCollecting)

            if viewModel.selectedPlatform.key == "xhs" || viewModel.selectedPlatform.key == "tb" {
                Button(viewModel.isSavingRoom ? "保存中..." : "保存到迅拣直播间") {
                    Task {
                        await viewModel.saveCurrentPlatformRoom(apiClient: appState.makeAPIClient())
                    }
                }
                .buttonStyle(AccentOutlineButtonStyle())
                .disabled(viewModel.isSavingRoom || viewModel.cookieSnapshots.isEmpty || !appState.isAuthenticated)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("弹幕连接参数")
                    .font(.system(size: 14, weight: .semibold))
                TextField(viewModel.selectedPlatform.danmuInputPlaceholder, text: $viewModel.liveRoomInput)
                    .webTextInput()
                HStack(spacing: 10) {
                    Button(viewModel.isDanmuConnected ? "断开弹幕" : "连接弹幕") {
                        viewModel.toggleDanmuConnection()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isDanmuConnecting || !viewModel.canConnectDanmu)
                    Button("清空弹幕") {
                        viewModel.clearDanmuMessages()
                    }
                    .buttonStyle(AccentOutlineButtonStyle())
                    .disabled(viewModel.danmuMessages.isEmpty)
                }
                Text(viewModel.danmuHelpText)
                    .font(.system(size: 12))
                    .foregroundStyle(FastSortTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("显示完整 Cookie 值", isOn: $viewModel.showCookieValues)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FastSortTheme.text)

            Text("完整值只用于本机测试；默认显示脱敏值，本模块不会自动上传 Cookie。")
                .font(.system(size: 12))
                .foregroundStyle(FastSortTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .webCard()
    }

    private var danmuPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("弹幕展示")
                        .font(.system(size: 18, weight: .semibold))
                    Text(viewModel.danmuStatusText)
                        .font(.system(size: 12))
                        .foregroundStyle(viewModel.danmuStatusLevel == .error ? FastSortTheme.danger : FastSortTheme.muted)
                }
                Spacer()
                statusPill(viewModel.danmuStatusLabel, color: viewModel.danmuStatusColor)
            }

            if viewModel.danmuMessages.isEmpty {
                EmptyPanel(text: viewModel.isDanmuConnected ? "等待平台弹幕消息" : "采集 Cookie 后填写直播间号/链接并连接弹幕")
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.danmuMessages) { message in
                            danmuMessageRow(message)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .webCard()
    }

    private func danmuMessageRow(_ message: DanmakuTestMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(message.timeText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(FastSortTheme.muted)
                .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(message.user)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FastSortTheme.text)
                    if !message.roomId.isEmpty {
                        Text(message.roomId)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(FastSortTheme.muted)
                    }
                }
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(FastSortTheme.text)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(FastSortTheme.groupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    private func platformButton(_ platform: DanmakuPlatform) -> some View {
        let active = platform.id == viewModel.selectedPlatform.id
        return Button {
            viewModel.selectPlatform(platform)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: platform.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.name)
                        .font(.system(size: 13, weight: active ? .semibold : .medium))
                    Text("ID \(platform.id) · \(platform.key)")
                        .font(.system(size: 11))
                        .foregroundStyle(FastSortTheme.muted)
                }
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(FastSortTheme.success)
                }
            }
            .foregroundStyle(active ? FastSortTheme.accent : FastSortTheme.text.opacity(0.86))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 42)
            .background(active ? FastSortTheme.accentSoft : FastSortTheme.groupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .buttonStyle(.plain)
    }

    private var selectedPlatformInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前配置")
                .font(.system(size: 14, weight: .semibold))
            infoLine("登录地址", viewModel.selectedPlatform.loginURL.absoluteString)
            infoLine("Cookie 域", viewModel.selectedPlatform.cookieDomain)
            infoLine("成功页匹配", viewModel.selectedPlatform.pageHandlerMatch)
            if !viewModel.selectedPlatform.cookieURLs.isEmpty {
                infoLine("补充 Cookie URL", viewModel.selectedPlatform.cookieURLs.map(\.absoluteString).joined(separator: "\n"))
            }
        }
        .font(.system(size: 12))
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FastSortTheme.muted)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(FastSortTheme.text)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private var browserPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("平台登录窗口")
                        .font(.system(size: 18, weight: .semibold))
                    Text(viewModel.currentURLText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(FastSortTheme.muted)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer()
                matchBadge
            }

            DanmakuAuthWebView(
                request: viewModel.loadRequest,
                dataStore: viewModel.websiteDataStore,
                onWebViewReady: viewModel.attachWebView(_:),
                onNavigation: viewModel.handleNavigation(url:),
                isAllowedNavigation: viewModel.isAllowedNavigation(url:),
                onBlockedNavigation: viewModel.handleBlockedNavigation(url:)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FastSortTheme.border, lineWidth: 1)
            }

            if !viewModel.statusText.isEmpty {
                Text(viewModel.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(viewModel.statusLevel == .error ? FastSortTheme.danger : FastSortTheme.muted)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .webCard()
    }

    private var matchBadge: some View {
        Label(viewModel.matchText, systemImage: viewModel.isPageMatched ? "checkmark.seal.fill" : "hourglass")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(viewModel.isPageMatched ? FastSortTheme.success : FastSortTheme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(viewModel.isPageMatched ? Color(hex: 0xe9f8ef) : FastSortTheme.groupedBackground)
            .clipShape(Capsule())
    }

    private var cookiePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cookie 采集结果")
                        .font(.system(size: 18, weight: .semibold))
                    Text("共 \(viewModel.cookieSnapshots.count) 条，按平台 Cookie 域和补充 URL 域过滤。")
                        .font(.system(size: 12))
                        .foregroundStyle(FastSortTheme.muted)
                }
                Spacer()
                if viewModel.isCollecting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("复制脱敏 JSON") {
                    viewModel.copyMaskedJSON()
                }
                .buttonStyle(AccentOutlineButtonStyle())
                .disabled(viewModel.cookieSnapshots.isEmpty)
                Button("复制完整 Cookie 串") {
                    viewModel.copyFullCookieString()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.cookieSnapshots.isEmpty || !viewModel.showCookieValues)
            }

            if viewModel.cookieSnapshots.isEmpty {
                EmptyPanel(text: "登录平台并点击采集后显示 Cookie 摘要")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                cookieTable
            }
        }
        .padding(16)
        .webCard()
    }

    private var cookieTable: some View {
        VStack(spacing: 0) {
            cookieHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.cookieSnapshots) { snapshot in
                        cookieRow(snapshot)
                        Divider()
                    }
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FastSortTheme.border, lineWidth: 1)
        }
    }

    private var cookieHeader: some View {
        HStack(spacing: 12) {
            Text("Name").frame(width: 180, alignment: .leading)
            Text("Domain").frame(width: 190, alignment: .leading)
            Text("Value").frame(maxWidth: .infinity, alignment: .leading)
            Text("Flag").frame(width: 96, alignment: .leading)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(FastSortTheme.muted)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(FastSortTheme.groupedBackground)
    }

    private func cookieRow(_ snapshot: DanmakuCookieSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(snapshot.name)
                .frame(width: 180, alignment: .leading)
            Text(snapshot.domain)
                .frame(width: 190, alignment: .leading)
            Text(snapshot.displayValue(showFull: viewModel.showCookieValues))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Text(snapshot.flagsText)
                .frame(width: 96, alignment: .leading)
                .foregroundStyle(FastSortTheme.muted)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

@MainActor
final class DanmakuCookieTestViewModel: ObservableObject {
    @Published private var selectedPlatformID = DanmakuPlatform.all[0].id
    @Published var loadRequest: DanmakuLoadRequest?
    @Published var currentURLText = "尚未打开平台登录页"
    @Published var isPageMatched = false
    @Published var matchText = "等待登录"
    @Published var statusText = ""
    @Published var statusLevel = DanmakuStatusLevel.info
    @Published var cookieSnapshots: [DanmakuCookieSnapshot] = []
    @Published var isCollecting = false
    @Published var isSavingRoom = false
    @Published var showCookieValues = false
    @Published var liveRoomInput = ""
    @Published var danmuStatus = DanmakuConnectionStatus.idle
    @Published var danmuStatusText = "尚未连接弹幕。"
    @Published var danmuStatusLevel = DanmakuStatusLevel.info
    @Published var danmuMessages: [DanmakuTestMessage] = []

    let websiteDataStore = DanmakuWebAuthSessionStore.shared.websiteDataStore
    private weak var webView: WKWebView?
    private var didPrepareInitialLoad = false
    private var lastAutoCollectURL = ""
    private var directDanmuTask: Task<Void, Never>?
    private var activeBridgeSession: DanmakuWebSocketSession?
    private var activeDirectSession: DanmakuWebSocketSession?
    private var seenDanmuMessageIds = Set<String>()
    private let taobaoDanmuHosts = ["https://impaas.alicdn.com", "https://impaasgw.alicdn.com"]
    private let taobaoMobileUserAgent = "Mozilla/5.0 (Linux; Android 11; Pixel 4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
    private let desktopUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"

    var selectedPlatform: DanmakuPlatform {
        DanmakuPlatform.all.first { $0.id == selectedPlatformID } ?? DanmakuPlatform.all[0]
    }

    func prepareInitialLoad() {
        guard !didPrepareInitialLoad else { return }
        didPrepareInitialLoad = true
        loadSelectedPlatform()
    }

    func attachWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    func selectPlatform(_ platform: DanmakuPlatform) {
        selectedPlatformID = platform.id
        cookieSnapshots = []
        showCookieValues = false
        closeDanmuSocket(clearMessages: true)
        liveRoomInput = ""
        lastAutoCollectURL = ""
        statusText = "已切换到 \(platform.name)，准备打开登录页。"
        statusLevel = .info
        loadSelectedPlatform()
    }

    func loadSelectedPlatform() {
        currentURLText = selectedPlatform.loginURL.absoluteString
        isPageMatched = false
        matchText = "等待登录"
        statusText = "已加载 \(selectedPlatform.name) 登录地址。"
        statusLevel = .info
        loadRequest = DanmakuLoadRequest(url: selectedPlatform.loginURL)
    }

    var isDanmuConnected: Bool {
        danmuStatus == .open || danmuStatus == .connecting
    }

    var isDanmuConnecting: Bool {
        danmuStatus == .connecting
    }

    var canConnectDanmu: Bool {
        selectedPlatform.supportsDirectDanmuAdapter
            && (!selectedPlatform.requiresDanmuInput || !liveRoomInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !cookieSnapshots.isEmpty
    }

    var danmuStatusLabel: String {
        switch danmuStatus {
        case .idle: return "未连接"
        case .connecting: return "连接中"
        case .open: return "已连接"
        case .closed: return "已断开"
        case .error: return "异常"
        }
    }

    var danmuStatusColor: Color {
        switch danmuStatus {
        case .open: return FastSortTheme.success
        case .connecting: return FastSortTheme.accent
        case .error: return FastSortTheme.danger
        default: return FastSortTheme.muted
        }
    }

    var danmuHelpText: String {
        if !selectedPlatform.supportsDirectDanmuAdapter {
            return "\(selectedPlatform.name) 暂未移植平台直连弹幕 adapter。当前先按弹幕捕手链路打通淘宝。"
        }
        if cookieSnapshots.isEmpty {
            return "先完成平台登录并采集 Cookie，再连接弹幕。"
        }
        return selectedPlatform.directDanmuAdapter?.helpText ?? "本测试使用采集到的 Cookie 在客户端直连平台弹幕源，不经过迅拣后端。"
    }

    func handleNavigation(url: URL) {
        let urlString = url.absoluteString
        currentURLText = urlString
        let matched = selectedPlatform.matchesSuccessURL(urlString)
        isPageMatched = matched
        matchText = matched ? "已命中成功页" : "未命中成功页"
        if matched, lastAutoCollectURL != urlString {
            lastAutoCollectURL = urlString
            statusText = "URL 已命中弹幕捕手 pageHandlerMatch，2.5 秒后自动采集 Cookie。"
            statusLevel = .success
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard self.currentURLText == urlString else { return }
                self.collectCookies(trigger: "URL 命中后自动采集")
            }
        }
    }

    func isAllowedNavigation(url: URL) -> Bool {
        selectedPlatform.isAllowedNavigation(url)
    }

    func handleBlockedNavigation(url: URL) {
        statusText = "已阻止授权窗口跳转到非平台白名单域名，并交给外部浏览器打开：\(url.host ?? url.absoluteString)"
        statusLevel = .error
    }

    func collectCookies(trigger: String) {
        guard !isCollecting else { return }
        guard webView != nil else {
            statusText = "WebView 尚未初始化，暂时无法采集。"
            statusLevel = .error
            return
        }
        isCollecting = true
        statusText = "\(trigger)中..."
        statusLevel = .info
        websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            DispatchQueue.main.async {
                self?.finishCollecting(cookies: cookies, trigger: trigger)
            }
        }
    }

    func clearSession() {
        cookieSnapshots = []
        showCookieValues = false
        closeDanmuSocket(clearMessages: true)
        isPageMatched = false
        matchText = "等待登录"
        lastAutoCollectURL = ""
        statusText = "正在清空当前测试会话..."
        statusLevel = .info
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        websiteDataStore.removeData(ofTypes: types, modifiedSince: Date.distantPast) { [weak self] in
            DispatchQueue.main.async {
                self?.statusText = "测试会话已清空，可重新打开平台登录页。"
                self?.statusLevel = .success
                self?.loadSelectedPlatform()
            }
        }
    }

    func copyFullCookieString() {
        guard showCookieValues else {
            statusText = "请先打开“显示完整 Cookie 值”再复制完整 Cookie 串。"
            statusLevel = .error
            return
        }
        copyToPasteboard(cookieString(masked: false))
        statusText = "已复制完整 Cookie 串到剪贴板。"
        statusLevel = .success
    }

    @MainActor
    func saveCurrentPlatformRoom(apiClient: APIClient) async {
        guard selectedPlatform.key == "xhs" || selectedPlatform.key == "tb" else { return }
        let cookieHeader = cookieString(masked: false).replacingOccurrences(of: ";", with: "; ")
        guard !cookieHeader.isEmpty else {
            statusText = "请先完成 \(selectedPlatform.name) 登录并采集 Cookie。"
            statusLevel = .error
            return
        }

        isSavingRoom = true
        statusText = "正在按弹幕捕手添加直播间阶段保存 \(selectedPlatform.name) Cookie..."
        statusLevel = .info
        defer { isSavingRoom = false }

        do {
            let service = LiveRoomsService(apiClient: apiClient)
            if selectedPlatform.key == "tb" {
                try await service.addTaobaoRoom(roomName: "淘宝直播间", liveSession: cookieHeader)
                statusText = "淘宝 Cookie 已保存到迅拣直播间 liveSession。开播时会由本机 helper 解析当前直播 roomId。"
            } else {
                try await service.addOrUpdateXiaohongshuRoom(cookies: cookieHeader)
                statusText = "小红书 ark 工作台 Cookie 已保存到迅拣直播间。后续会按弹幕捕手客户端侧 adapter 的边界补齐本机解析直播和拉取弹幕链路。"
            }
            statusLevel = .success
        } catch {
            statusText = "保存 \(selectedPlatform.name) 直播间失败：\(error.localizedDescription)"
            statusLevel = .error
        }
    }

    func copyMaskedJSON() {
        let rows = cookieSnapshots.map { snapshot in
            [
                "name": snapshot.name,
                "domain": snapshot.domain,
                "path": snapshot.path,
                "value": snapshot.maskedValue,
                "flags": snapshot.flagsText
            ]
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return }
        copyToPasteboard(text)
        statusText = "已复制脱敏 JSON 到剪贴板。"
        statusLevel = .success
    }

    func toggleDanmuConnection() {
        if isDanmuConnected {
            closeDanmuSocket(clearMessages: false)
        } else {
            connectDanmu()
        }
    }

    func clearDanmuMessages() {
        danmuMessages = []
        seenDanmuMessageIds = []
    }

    private func connectDanmu() {
        guard canConnectDanmu else {
            danmuStatus = .error
            danmuStatusText = selectedPlatform.supportsDirectDanmuAdapter
                ? "请先采集 Cookie，并按当前平台要求填写直播间号/直播链接。"
                : "\(selectedPlatform.name) 暂未移植平台直连弹幕 adapter。"
            danmuStatusLevel = .error
            return
        }
        guard let adapter = selectedPlatform.directDanmuAdapter else {
            danmuStatus = .error
            danmuStatusText = "\(selectedPlatform.name) 的直连弹幕 adapter 尚未实现。"
            danmuStatusLevel = .error
            return
        }
        closeDanmuSocket(clearMessages: false, updateStatus: false)
        let cookieHeader = cookieString(masked: false).replacingOccurrences(of: ";", with: "; ")
        danmuStatus = .connecting
        danmuStatusText = "正在启动 \(selectedPlatform.name) 弹幕直连..."
        danmuStatusLevel = .info
        directDanmuTask = Task { [weak self] in
            await self?.runDirectDanmu(adapter: adapter, cookieHeader: cookieHeader)
        }
    }

    private func runDirectDanmu(adapter: DanmakuDirectAdapterKind, cookieHeader: String) async {
        switch adapter {
        case .taobao:
            await runTaobaoBridgeDanmu(cookieHeader: cookieHeader)
        case .xiaohongshu:
            await runXiaohongshuBridgeDanmu(cookieHeader: cookieHeader)
        case .kuaishou:
            await runKuaishouBridgeDanmu(cookieHeader: cookieHeader)
        case .shopee:
            await runLocalBridgeDanmu(adapter: adapter, cookieHeader: cookieHeader)
        case .douyin, .tiktok, .wechat:
            await runLocalBridgeDanmu(adapter: adapter, cookieHeader: cookieHeader)
        }
    }

    private func appendDanmuMessage(_ message: DanmakuTestMessage) {
        danmuMessages = Array((danmuMessages + [message]).suffix(120))
    }

    private func closeDanmuSocket(clearMessages: Bool, updateStatus: Bool = true) {
        cleanupDanmuTasks()
        if updateStatus {
            danmuStatus = .idle
            danmuStatusText = "弹幕连接已关闭。"
            danmuStatusLevel = .info
        }
        if clearMessages {
            clearDanmuMessages()
        }
    }

    private func cleanupDanmuTasks() {
        activeBridgeSession?.cancel()
        activeBridgeSession = nil
        activeDirectSession?.cancel()
        activeDirectSession = nil
        directDanmuTask?.cancel()
        directDanmuTask = nil
    }

    private func runTaobaoDirectDanmu(cookieHeader: String) async {
        do {
            let roomId = try await resolveTaobaoRoomId(input: liveRoomInput, cookieHeader: cookieHeader)
            guard !Task.isCancelled else { return }
            danmuStatus = .open
            danmuStatusText = "淘宝 roomId 已解析：\(roomId)，正在直连 impaas 弹幕源。"
            danmuStatusLevel = .success
            appendDanmuMessage(.system("淘宝直连已启动 roomId=\(roomId)"))

            let deviceId = stableTaobaoDeviceId(roomId)
            var start = Int(Date().timeIntervalSince1970 * 1000)
            var end = start
            while !Task.isCancelled {
                let messages = try await fetchTaobaoMessages(
                    roomId: roomId,
                    start: start,
                    end: end,
                    deviceId: deviceId,
                    cookieHeader: cookieHeader
                )
                guard !Task.isCancelled else { return }
                if let nextEnd = messages.nextEndTime {
                    start = nextEnd
                    end = nextEnd + 1
                }
                if !messages.items.isEmpty {
                    for item in messages.items {
                        if !item.messageId.isEmpty {
                            guard !seenDanmuMessageIds.contains(item.messageId) else { continue }
                            seenDanmuMessageIds.insert(item.messageId)
                            if seenDanmuMessageIds.count > 500 {
                                seenDanmuMessageIds.remove(seenDanmuMessageIds.first ?? "")
                            }
                        }
                        appendDanmuMessage(item)
                    }
                    danmuStatusText = "淘宝弹幕直连中，本轮收到 \(messages.items.count) 条。"
                    danmuStatusLevel = .success
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } catch {
            guard !Task.isCancelled else { return }
            danmuStatus = .error
            danmuStatusText = "淘宝直连失败：\(error.localizedDescription)"
            danmuStatusLevel = .error
            appendDanmuMessage(.system("淘宝直连失败：\(error.localizedDescription)"))
            cleanupDanmuTasks()
        }
    }

    private func runKuaishouDirectDanmu(cookieHeader: String) async {
        do {
            let roomId = kuaishouRoomId(from: liveRoomInput)
            guard !roomId.isEmpty else {
                throw DanmakuDirectError("请输入快手直播间号或 live.kuaishou.com/u/{id} 链接")
            }
            let roomInit = try await resolveKuaishouRoomInit(roomId: roomId, cookieHeader: cookieHeader)
            guard roomInit.live, let webSocketURL = roomInit.webSocketURLs.first, let url = URL(string: webSocketURL) else {
                throw DanmakuDirectError("快手房间未开播，或未返回 WebSocket token/地址")
            }
            let session = DanmakuWebSocketSession()
            activeDirectSession = session
            var heartbeatTask: Task<Void, Never>?
            defer { heartbeatTask?.cancel() }
            try await session.run(
                request: URLRequest(url: url),
                onOpen: {
                    try await session.send(.data(buildKuaishouEnterRoomMessage(roomInit: roomInit)))
                    danmuStatus = .open
                    danmuStatusText = "快手 roomId 已解析：\(roomId)，正在直连直播间 WebSocket。"
                    danmuStatusLevel = .success
                    appendDanmuMessage(.system("快手直连已启动 roomId=\(roomId), liveStreamId=\(roomInit.liveStreamId)"))
                    heartbeatTask = Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 20_000_000_000)
                            guard !Task.isCancelled else { return }
                            try? await session.send(.data(buildKuaishouHeartbeatMessage()))
                        }
                    }
                },
                onMessage: { message in
                    let items = try decodeKuaishouWebSocketMessage(message, roomId: roomId, liveStreamId: roomInit.liveStreamId)
                    if !items.isEmpty {
                        for item in items {
                            if !item.messageId.isEmpty {
                                guard !seenDanmuMessageIds.contains(item.messageId) else { continue }
                                seenDanmuMessageIds.insert(item.messageId)
                            }
                            appendDanmuMessage(item)
                        }
                        danmuStatusText = "快手弹幕直连中，本轮收到 \(items.count) 条。"
                        danmuStatusLevel = .success
                    }
                }
            )
        } catch {
            guard !Task.isCancelled else { return }
            danmuStatus = .error
            danmuStatusText = "快手直连失败：\(error.localizedDescription)"
            danmuStatusLevel = .error
            appendDanmuMessage(.system("快手直连失败：\(error.localizedDescription)"))
            cleanupDanmuTasks()
        }
    }

    private func runLocalBridgeDanmu(adapter: DanmakuDirectAdapterKind, cookieHeader: String) async {
        do {
            if let helperKind = DanmakuPlatformRegistry.localBridgeConfig(for: adapter)?.helperKind {
                try await LocalDanmakuHelperManager.shared.ensureRunning(helperKind)
            }
            let url = try localBridgeURL(adapter: adapter, cookieHeader: cookieHeader)
            try await runBridgeWebSocket(adapter: adapter, platformKey: selectedPlatform.key, request: URLRequest(url: url))
        } catch {
            guard !Task.isCancelled else { return }
            danmuStatus = .error
            danmuStatusText = "\(adapter.displayName) 连接失败：\(error.localizedDescription)"
            danmuStatusLevel = .error
            appendDanmuMessage(.system("\(adapter.displayName) 连接失败：\(error.localizedDescription)"))
            cleanupDanmuTasks()
        }
    }

    private func runTaobaoBridgeDanmu(cookieHeader: String) async {
        do {
            try await LocalDanmakuHelperManager.shared.ensureRunning(.taobao)
            let input = liveRoomInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let explicitRoomId = input.isEmpty ? nil : taobaoRoomId(from: input)
            let explicitURL = input.hasPrefix("http") && explicitRoomId == nil ? input : nil
            let fallbackRoomId = !input.isEmpty && explicitRoomId == nil && explicitURL == nil ? input : nil
            let data = try await checkAndStartLocalLive(
                port: 8201,
                sessionId: "tb-test-\(sha1Hex(cookieHeader))",
                cookie: cookieHeader,
                roomId: explicitRoomId ?? fallbackRoomId,
                sourceURL: explicitURL
            )
            guard let roomId = data.roomId?.trimmingCharacters(in: .whitespacesAndNewlines), !roomId.isEmpty else {
                throw DanmakuDirectError(data.message ?? "淘宝 helper 未从千牛工作台 Cookie 解析到当前直播 room_id")
            }
            let path = data.wsPath?.isEmpty == false ? data.wsPath! : "/tb-ws-room/\(roomId)"
            guard let url = localBridgeURL(port: 8201, path: path) else {
                throw DanmakuDirectError("淘宝 helper WebSocket URL 构造失败")
            }
            try await runBridgeWebSocket(adapter: .taobao, platformKey: "tb", request: URLRequest(url: url))
        } catch {
            guard !Task.isCancelled else { return }
            danmuStatus = .error
            danmuStatusText = "淘宝连接失败：\(error.localizedDescription)"
            danmuStatusLevel = .error
            appendDanmuMessage(.system("淘宝连接失败：\(error.localizedDescription)"))
            cleanupDanmuTasks()
        }
    }

    private func runXiaohongshuBridgeDanmu(cookieHeader: String) async {
        guard !Task.isCancelled else { return }
        let cookieMap = DanmakuCookieSessionParser.cookieMap(fromCookieHeader: cookieHeader)
        let cookieNames = cookieMap.keys.sorted().joined(separator: ", ")
        let hasArkToken = cookieMap["access-token-ark.xiaohongshu.com"]?.isEmpty == false
        let state = hasArkToken ? "已采到 ark 工作台登录态" : "未采到 ark 工作台登录态"
        let message = """
        小红书不能再调用旧登录态方案。后续应以 ark 工作台 Cookie 作为登录态，并在客户端侧 adapter 继续解析直播和拉取弹幕。当前迅拣还缺少这段本机 adapter。当前状态：\(state)。当前 Cookie：\(cookieNames)。
        """
        danmuStatus = .error
        danmuStatusText = message
        danmuStatusLevel = .error
        appendDanmuMessage(.system(message))
        cleanupDanmuTasks()
    }

    private func runKuaishouBridgeDanmu(cookieHeader: String) async {
        do {
            try await LocalDanmakuHelperManager.shared.ensureRunning(.kuaishou)
            var roomId = kuaishouRoomId(from: liveRoomInput)
            var wsPath: String?
            if roomId.isEmpty {
                let data = try await checkAndStartLocalLive(
                    port: 8301,
                    sessionId: "ks-test-\(sha1Hex(cookieHeader))",
                    cookie: cookieHeader,
                    roomId: nil
                )
                roomId = data.roomId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                wsPath = data.wsPath
            }
            guard !roomId.isEmpty else {
                throw DanmakuDirectError("快手 helper 未解析到直播间号，可能当前账号未开播")
            }
            let path = wsPath?.isEmpty == false ? wsPath! : "/ks-ws/\(roomId)"
            guard let url = localBridgeURL(port: 8301, path: path) else {
                throw DanmakuDirectError("快手 helper WebSocket URL 构造失败")
            }
            var request = URLRequest(url: url)
            if !cookieHeader.isEmpty {
                request.setValue(cookieHeader, forHTTPHeaderField: "x-kuaishou-cookie")
            }
            try await runBridgeWebSocket(adapter: .kuaishou, platformKey: "ks", request: request)
        } catch {
            guard !Task.isCancelled else { return }
            danmuStatus = .error
            danmuStatusText = "快手连接失败：\(error.localizedDescription)"
            danmuStatusLevel = .error
            appendDanmuMessage(.system("快手连接失败：\(error.localizedDescription)"))
            cleanupDanmuTasks()
        }
    }

    private func runBridgeWebSocket(
        adapter: DanmakuDirectAdapterKind,
        platformKey: String,
        request: URLRequest
    ) async throws {
        let session = DanmakuWebSocketSession()
        activeBridgeSession = session
        try await session.run(
            request: request,
            onOpen: { [weak self] in
                guard let self else { return }
                self.danmuStatus = .open
                self.danmuStatusText = "\(adapter.displayName) 已连接本机直连 adapter：\(request.url?.host ?? "localhost"):\(request.url?.port ?? 0)"
                self.danmuStatusLevel = .success
                self.appendDanmuMessage(.system("\(adapter.displayName) 本机 adapter 已连接：\(request.url?.absoluteString ?? "")"))
            },
            onMessage: { [weak self] message in
                guard let self else { return }
                try await self.handleBridgeWebSocketMessage(message, platformKey: platformKey, adapter: adapter)
            }
        )
    }

    private func resolveTaobaoRoomId(input: String, cookieHeader: String) async throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DanmakuDirectError("请输入淘宝 roomId 或直播链接作为兜底参数")
        }
        if let roomId = taobaoRoomId(from: trimmed) {
            return roomId
        }
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            return trimmed
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(taobaoMobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""
        if let roomId = taobaoRoomId(from: html) {
            return roomId
        }
        throw DanmakuDirectError("未能从淘宝兜底链接解析 roomId")
    }

    private func fetchTaobaoMessages(
        roomId: String,
        start: Int,
        end: Int,
        deviceId: String,
        cookieHeader: String
    ) async throws -> TaobaoPollResult {
        var lastError: Error?
        for host in taobaoDanmuHosts {
            guard let url = URL(string: "\(host)/live/message/\(roomId)/\(start)/\(end)?deviceId=\(deviceId)") else {
                throw DanmakuDirectError("淘宝弹幕 URL 构造失败")
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue(taobaoMobileUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("Keep-Alive", forHTTPHeaderField: "Connection")
            if !cookieHeader.isEmpty {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    lastError = DanmakuDirectError("\(host) HTTP \(http.statusCode)")
                    if [403, 404, 429].contains(http.statusCode) {
                        continue
                    }
                    throw lastError ?? DanmakuDirectError("淘宝弹幕接口 HTTP \(http.statusCode)")
                }
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw DanmakuDirectError("淘宝弹幕接口返回不是 JSON")
                }
                let nextEndTime = flexibleInt(object["endTime"])
                let payloads = object["payloads"] as? [[String: Any]] ?? []
                let items = payloads.compactMap { decodeTaobaoPayload($0, roomId: roomId) }
                return TaobaoPollResult(nextEndTime: nextEndTime, items: items)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? DanmakuDirectError("淘宝弹幕接口请求失败")
    }

    private func decodeTaobaoPayload(_ payload: [String: Any], roomId: String) -> DanmakuTestMessage? {
        guard let rawBase64 = payload["data"] as? String else { return nil }
        guard let data = Data(base64Encoded: paddedBase64(rawBase64)) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let content = firstText(object, keys: ["content", "text", "msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let renders = object["renders"] as? [String: Any] ?? [:]
        let userId = taobaoUserId(renders: renders, root: object)
        let messageId = firstText(object, keys: ["id", "msgId", "messageId"], fallback: "")
            .isEmpty ? "\(roomId)-\(userId)-\(content)-\(Date().timeIntervalSince1970)" : firstText(object, keys: ["id", "msgId", "messageId"])
        let liveId = firstText(renders, keys: ["liveId"], fallback: roomId)
        return DanmakuTestMessage(
            id: messageId,
            messageId: messageId,
            user: taobaoNick(root: object, renders: renders),
            content: content,
            roomId: liveId.isEmpty ? roomId : liveId
        )
    }

    private func taobaoRoomId(from text: String) -> String? {
        let decoded = decodeRepeatedly(text)
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
        if let value = queryValue(in: decoded, name: "wh_cid"), !value.isEmpty {
            return value
        }
        if let livePlayURL = queryValue(in: decoded, name: "livePlayUrl"),
           let roomId = firstRegexMatch(in: decodeRepeatedly(livePlayURL), pattern: #"liveplatform/([A-Fa-f0-9\-]{16,})___"#) {
            return roomId
        }
        if let roomId = firstRegexMatch(in: decoded, pattern: #"liveplatform/([A-Fa-f0-9\-]{16,})___"#) {
            return roomId
        }
        if let roomId = firstRegexMatch(in: decoded, pattern: #"wh_cid=([^&"' <>\n]+)"#) {
            return decodeRepeatedly(roomId)
        }
        if let uuid = firstRegexMatch(in: decoded, pattern: #"^([A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12})$"#) {
            return uuid
        }
        return nil
    }

    private func queryValue(in text: String, name: String) -> String? {
        if let url = URL(string: text),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name == name })?.value {
            return decodeRepeatedly(value)
        }
        let escaped = NSRegularExpression.escapedPattern(for: name)
        if let value = firstRegexMatch(in: text, pattern: "\(escaped)=([^&\"' <>\\n]+)") {
            return decodeRepeatedly(value)
        }
        return nil
    }

    private func firstRegexMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private func decodeRepeatedly(_ value: String) -> String {
        var current = value
        for _ in 0..<3 {
            guard let decoded = current.removingPercentEncoding, decoded != current else { break }
            current = decoded
        }
        return current
    }

    private func paddedBase64(_ value: String) -> String {
        let remainder = value.count % 4
        guard remainder != 0 else { return value }
        return value + String(repeating: "=", count: 4 - remainder)
    }

    private func flexibleInt(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let int64 = value as? Int64 { return Int(int64) }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func firstText(_ payload: [String: Any], keys: [String], fallback: String = "") -> String {
        for key in keys {
            if let value = payload[key], !(value is NSNull) {
                return "\(value)"
            }
        }
        return fallback
    }

    private func taobaoNick(root: [String: Any], renders: [String: Any]) -> String {
        let nick = firstText(root, keys: ["tbNick"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !nick.isEmpty { return nick }
        let snsNick = firstText(renders, keys: ["snsNick"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !snsNick.isEmpty { return snsNick }
        let publisherNick = firstText(root, keys: ["publisherNick", "nick"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return publisherNick.isEmpty ? "淘宝用户" : publisherNick
    }

    private func taobaoUserId(renders: [String: Any], root: [String: Any]) -> String {
        let direct = firstText(renders, keys: ["tbUserIdEncode", "userId", "userIdEncode"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }
        for field in ["snsNickPic", "guangGuangJumpUrl"] {
            let urlText = firstText(renders, keys: [field])
            if let userId = queryValue(in: urlText, name: "userIdStrV2")
                ?? queryValue(in: urlText, name: "userIdStr")
                ?? queryValue(in: urlText, name: "userId") {
                return userId
            }
        }
        return firstText(root, keys: ["userId", "uid", "publisherId"])
    }

    private func stableTaobaoDeviceId(_ roomId: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(roomId.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(24).description
    }

    private func resolveKuaishouRoomInit(roomId: String, cookieHeader: String) async throws -> KuaishouRoomInit {
        let pageURL = URL(string: "https://live.kuaishou.com/u/\(roomId)")!
        var pageRequest = URLRequest(url: pageURL)
        pageRequest.timeoutInterval = 12
        applyKuaishouHeaders(to: &pageRequest, cookieHeader: cookieHeader, referer: pageURL.absoluteString)
        let (htmlData, response) = try await URLSession.shared.data(for: pageRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DanmakuDirectError("快手房间页 HTTP \(http.statusCode)")
        }
        let html = String(data: htmlData, encoding: .utf8) ?? ""
        let detail = try extractKuaishouPlayDetail(from: html)
        let author = detail["author"] as? [String: Any] ?? [:]
        let liveStream = detail["liveStream"] as? [String: Any] ?? [:]
        let liveStreamId = firstText(liveStream, keys: ["id"])
        let isLiving = boolValue(detail["isLiving"]) || boolValue(author["living"]) || !liveStreamId.isEmpty
        guard !liveStreamId.isEmpty else {
            throw DanmakuDirectError(isLiving ? "快手房间显示直播中，但未解析到 liveStreamId" : "快手房间未开播")
        }
        let websocketInfo = try await fetchKuaishouWebSocketInfo(roomId: roomId, liveStreamId: liveStreamId, cookieHeader: cookieHeader)
        let token = firstText(websocketInfo, keys: ["token"])
        let urls = (websocketInfo["websocketUrls"] as? [String])
            ?? (websocketInfo["webSocketAddresses"] as? [String])
            ?? []
        return KuaishouRoomInit(
            roomId: roomId,
            title: firstText(author, keys: ["name"], fallback: roomId),
            liveStreamId: liveStreamId,
            token: token,
            webSocketURLs: urls,
            live: isLiving && !token.isEmpty && !urls.isEmpty
        )
    }

    private func fetchKuaishouWebSocketInfo(roomId: String, liveStreamId: String, cookieHeader: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://live.kuaishou.com/live_api/liveroom/websocketinfo?caver=2&liveStreamId=\(liveStreamId)") else {
            throw DanmakuDirectError("快手 websocketinfo URL 构造失败")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        applyKuaishouHeaders(to: &request, cookieHeader: cookieHeader, referer: "https://live.kuaishou.com/u/\(roomId)")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DanmakuDirectError("快手 websocketinfo HTTP \(http.statusCode)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = root["data"] as? [String: Any] else {
            throw DanmakuDirectError("快手 websocketinfo 返回结构异常")
        }
        if let result = flexibleInt(dataObject["result"]), result != 1, result != 0, result != 671, result != 677 {
            throw DanmakuDirectError("快手 websocketinfo 业务返回 result=\(result)")
        }
        return dataObject
    }

    private func applyKuaishouHeaders(to request: inout URLRequest, cookieHeader: String, referer: String) {
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if let kww = DanmakuCookieSessionParser.cookieMap(fromCookieHeader: cookieHeader)["kwfv1"], !kww.isEmpty {
            request.setValue(kww, forHTTPHeaderField: "Kww")
        }
    }

    private func extractKuaishouPlayDetail(from html: String) throws -> [String: Any] {
        let pattern = #""playList":\s*\[([\s\S]*?)\](?=,\s*"loading"|$)"#
        guard let jsonText = firstRegexMatch(in: html, pattern: pattern)?.replacingOccurrences(of: "undefined", with: "null"),
              let data = jsonText.data(using: .utf8),
              let detail = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DanmakuDirectError("未能从快手房间页解析 playList")
        }
        return detail
    }

    private func kuaishouRoomId(from input: String) -> String {
        let decoded = decodeRepeatedly(input.trimmingCharacters(in: .whitespacesAndNewlines))
        if let url = URL(string: decoded), let host = url.host, host.contains("kuaishou.com") {
            let parts = url.path.split(separator: "/").map(String.init)
            if let index = parts.firstIndex(of: "u"), parts.indices.contains(index + 1) {
                return parts[index + 1]
            }
            if let last = parts.last, !last.isEmpty {
                return last
            }
        }
        return decoded
    }

    private func buildKuaishouEnterRoomMessage(roomInit: KuaishouRoomInit) -> Data {
        var enterRoom = Data()
        enterRoom.append(protoStringField(1, roomInit.token))
        enterRoom.append(protoStringField(2, roomInit.liveStreamId))
        enterRoom.append(protoStringField(7, randomPageId()))
        var socketMessage = Data()
        socketMessage.append(protoVarintField(1, 200))
        socketMessage.append(protoLengthField(3, enterRoom))
        return socketMessage
    }

    private func buildKuaishouHeartbeatMessage() -> Data {
        var heartbeat = Data()
        heartbeat.append(protoVarintField(1, UInt64(Date().timeIntervalSince1970 * 1000)))
        var socketMessage = Data()
        socketMessage.append(protoVarintField(1, 1))
        socketMessage.append(protoLengthField(3, heartbeat))
        return socketMessage
    }

    private func decodeKuaishouWebSocketMessage(
        _ message: URLSessionWebSocketTask.Message,
        roomId: String,
        liveStreamId: String
    ) throws -> [DanmakuTestMessage] {
        let data: Data
        switch message {
        case .data(let value):
            data = value
        case .string:
            return []
        @unknown default:
            return []
        }
        let socketFields = parseProtoFields(data)
        let payloadType = socketFields.firstVarint(1)
        guard payloadType == 310 else { return [] }
        let compressionType = socketFields.firstVarint(2) ?? 0
        guard compressionType == 0 || compressionType == 1 else {
            throw DanmakuDirectError("快手暂不支持 compressionType=\(compressionType) 的 WebSocket payload")
        }
        guard let payload = socketFields.firstData(3) else { return [] }
        let feedFields = parseProtoFields(payload)
        return feedFields
            .allData(5)
            .compactMap { decodeKuaishouCommentFeed($0, roomId: roomId, liveStreamId: liveStreamId) }
    }

    private func decodeKuaishouCommentFeed(_ data: Data, roomId: String, liveStreamId: String) -> DanmakuTestMessage? {
        let fields = parseProtoFields(data)
        let rawId = fields.firstString(1)
        let userData = fields.firstData(2)
        let content = fields.firstString(3)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { return nil }
        let userFields = userData.map(parseProtoFields) ?? []
        let userId = userFields.firstString(1) ?? ""
        let userName = userFields.firstString(2) ?? "快手用户"
        let messageId = rawId?.isEmpty == false ? rawId! : sha1Hex("\(roomId)|\(userId)|\(content)|\(UUID().uuidString)")
        return DanmakuTestMessage(
            id: messageId,
            messageId: messageId,
            user: userName,
            content: content,
            roomId: liveStreamId
        )
    }

    private func localBridgeURL(adapter: DanmakuDirectAdapterKind, cookieHeader: String) throws -> URL {
        do {
            return try DanmakuLocalConnectionBuilder.bridgeURL(
                adapter: adapter,
                input: liveRoomInput,
                cookieHeader: cookieHeader
            )
        } catch {
            throw DanmakuDirectError(error.localizedDescription)
        }
    }

    private func localBridgeURL(port: Int, path: String, queryItems: [URLQueryItem] = []) -> URL? {
        DanmakuLocalConnectionBuilder.webSocketURL(port: port, path: path, queryItems: queryItems)
    }

    private func localHTTPURL(port: Int, path: String) -> URL? {
        DanmakuLocalConnectionBuilder.httpURL(port: port, path: path)
    }

    private func checkAndStartLocalLive(
        port: Int,
        sessionId: String,
        cookie: String,
        roomId: String?,
        sourceURL: String? = nil
    ) async throws -> LocalLivePrepareData {
        guard let url = localHTTPURL(port: port, path: "/api/live/check_and_start") else {
            throw DanmakuDirectError("本机 helper URL 构造失败")
        }
        var payload: [String: Any] = [
            "session_id": sessionId,
            "auto_start": true,
            "cookie": cookie
        ]
        if let roomId = roomId?.trimmingCharacters(in: .whitespacesAndNewlines), !roomId.isEmpty {
            payload["room_id"] = roomId
        }
        if let sourceURL = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceURL.isEmpty {
            payload["url"] = sourceURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DanmakuDirectError("本机 helper HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(LocalLivePrepareResponse.self, from: data)
        guard decoded.success != false else {
            throw DanmakuDirectError(decoded.msg ?? decoded.message ?? "本机 helper 返回失败")
        }
        return decoded.data ?? LocalLivePrepareData(status: nil, roomId: nil, title: nil, cover: nil, wsPath: nil, message: decoded.msg ?? decoded.message)
    }

    private func handleBridgeWebSocketMessage(
        _ message: URLSessionWebSocketTask.Message,
        platformKey: String,
        adapter: DanmakuDirectAdapterKind
    ) async throws {
        guard let text = DanmakuSocketMessageParser.text(from: message), !text.isEmpty else { return }
        if let status = DanmakuSocketMessageParser.status(fromText: text) {
            handleBridgeSocketStatus(status, adapter: adapter)
            return
        }
        guard
            let data = text.data(using: .utf8),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = DanmakuTestMessage(payload: payload, platformKey: platformKey)
        else {
            appendDanmuMessage(.system(text))
            return
        }
        if !message.messageId.isEmpty {
            guard !seenDanmuMessageIds.contains(message.messageId) else { return }
            seenDanmuMessageIds.insert(message.messageId)
        }
        appendDanmuMessage(message)
        danmuStatusText = "\(adapter.displayName) 本机 adapter 收到弹幕。"
        danmuStatusLevel = .success
    }

    private func handleBridgeSocketStatus(_ status: DanmakuSocketTextStatus, adapter: DanmakuDirectAdapterKind) {
        switch status {
        case .pong:
            break
        case .living:
            danmuStatus = .open
            danmuStatusText = "\(adapter.displayName) 本机 adapter 已连上平台弹幕。"
            danmuStatusLevel = .success
        case .connecting:
            danmuStatus = .connecting
            danmuStatusText = "\(adapter.displayName) 本机 adapter 正在连接平台弹幕。"
            danmuStatusLevel = .info
        case .stopped, .ended:
            danmuStatusText = "\(adapter.displayName) 直播已结束。"
            danmuStatusLevel = .info
            closeDanmuSocket(clearMessages: false)
        case .disconnected:
            danmuStatus = .closed
            danmuStatusText = "\(adapter.displayName) 已断开。"
            danmuStatusLevel = .info
            closeDanmuSocket(clearMessages: false)
        case .loginExpired:
            danmuStatus = .error
            danmuStatusText = "\(adapter.displayName) 登录失效。"
            danmuStatusLevel = .error
            closeDanmuSocket(clearMessages: false)
        case .paused:
            danmuStatusText = "\(adapter.displayName) 直播暂停。"
            danmuStatusLevel = .info
        case .notStarted:
            danmuStatusText = "\(adapter.displayName) 未开播。"
            danmuStatusLevel = .info
        }
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let string = value as? String { return ["1", "true", "yes"].contains(string.lowercased()) }
        return false
    }

    private func randomPageId() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let prefix = String((0..<16).map { _ in chars.randomElement() ?? "x" })
        return "\(prefix)\(Int(Date().timeIntervalSince1970 * 1000))"
    }

    private func sha1Hex(_ text: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func finishCollecting(cookies: [HTTPCookie], trigger: String) {
        let filtered = cookies
            .filter { selectedPlatform.matches(cookie: $0) }
            .sorted {
                if $0.domain == $1.domain {
                    return $0.name < $1.name
                }
                return $0.domain < $1.domain
            }
        cookieSnapshots = filtered.map(DanmakuCookieSnapshot.init(cookie:))
        isCollecting = false
        if filtered.isEmpty {
            statusText = "\(trigger)完成，但未采集到 \(selectedPlatform.name) 的 Cookie。请确认已在内嵌登录页完成平台登录。"
            statusLevel = .error
        } else {
            let domains = Set(filtered.map(\.domain)).sorted().joined(separator: ", ")
            statusText = "\(trigger)完成，采集到 \(filtered.count) 条 Cookie。域名：\(domains)"
            statusLevel = .success
        }
    }

    private func cookieString(masked: Bool) -> String {
        cookieSnapshots
            .map { "\($0.name)=\(masked ? $0.maskedValue : $0.value)" }
            .joined(separator: ";")
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct ProtoField {
    let number: Int
    let wireType: Int
    let varint: UInt64?
    let data: Data?

    var stringValue: String? {
        guard let data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private extension Array where Element == ProtoField {
    func firstVarint(_ number: Int) -> UInt64? {
        first { $0.number == number && $0.wireType == 0 }?.varint
    }

    func firstData(_ number: Int) -> Data? {
        first { $0.number == number && $0.wireType == 2 }?.data
    }

    func firstString(_ number: Int) -> String? {
        first { $0.number == number && $0.wireType == 2 }?.stringValue
    }

    func allData(_ number: Int) -> [Data] {
        compactMap { $0.number == number && $0.wireType == 2 ? $0.data : nil }
    }
}

private func parseProtoFields(_ data: Data) -> [ProtoField] {
    var fields: [ProtoField] = []
    var index = data.startIndex
    while index < data.endIndex {
        guard let key = readProtoVarint(data, index: &index) else { break }
        let number = Int(key >> 3)
        let wireType = Int(key & 0x7)
        switch wireType {
        case 0:
            guard let value = readProtoVarint(data, index: &index) else { return fields }
            fields.append(ProtoField(number: number, wireType: wireType, varint: value, data: nil))
        case 2:
            guard let length = readProtoVarint(data, index: &index) else { return fields }
            let end = data.index(index, offsetBy: Int(length), limitedBy: data.endIndex) ?? data.endIndex
            guard end <= data.endIndex else { return fields }
            fields.append(ProtoField(number: number, wireType: wireType, varint: nil, data: data[index..<end]))
            index = end
        case 5:
            let end = data.index(index, offsetBy: 4, limitedBy: data.endIndex) ?? data.endIndex
            guard end <= data.endIndex else { return fields }
            fields.append(ProtoField(number: number, wireType: wireType, varint: nil, data: data[index..<end]))
            index = end
        case 1:
            let end = data.index(index, offsetBy: 8, limitedBy: data.endIndex) ?? data.endIndex
            guard end <= data.endIndex else { return fields }
            fields.append(ProtoField(number: number, wireType: wireType, varint: nil, data: data[index..<end]))
            index = end
        default:
            return fields
        }
    }
    return fields
}

private func readProtoVarint(_ data: Data, index: inout Data.Index) -> UInt64? {
    var result: UInt64 = 0
    var shift: UInt64 = 0
    while index < data.endIndex && shift < 64 {
        let byte = data[index]
        index = data.index(after: index)
        result |= UInt64(byte & 0x7F) << shift
        if byte & 0x80 == 0 {
            return result
        }
        shift += 7
    }
    return nil
}

private func protoVarintField(_ fieldNumber: Int, _ value: UInt64) -> Data {
    var data = encodeProtoVarint(UInt64(fieldNumber << 3))
    data.append(encodeProtoVarint(value))
    return data
}

private func protoLengthField(_ fieldNumber: Int, _ payload: Data) -> Data {
    var data = encodeProtoVarint(UInt64((fieldNumber << 3) | 2))
    data.append(encodeProtoVarint(UInt64(payload.count)))
    data.append(payload)
    return data
}

private func protoStringField(_ fieldNumber: Int, _ value: String) -> Data {
    protoLengthField(fieldNumber, Data(value.utf8))
}

private func encodeProtoVarint(_ value: UInt64) -> Data {
    var value = value
    var data = Data()
    while value >= 0x80 {
        data.append(UInt8(value & 0x7F) | 0x80)
        value >>= 7
    }
    data.append(UInt8(value))
    return data
}

private struct DanmakuAuthWebView: NSViewRepresentable {
    let request: DanmakuLoadRequest?
    let dataStore: WKWebsiteDataStore
    let onWebViewReady: (WKWebView) -> Void
    let onNavigation: (URL) -> Void
    let isAllowedNavigation: (URL) -> Bool
    let onBlockedNavigation: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onNavigation: onNavigation,
            isAllowedNavigation: isAllowedNavigation,
            onBlockedNavigation: onBlockedNavigation
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"
        onWebViewReady(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(
            onNavigation: onNavigation,
            isAllowedNavigation: isAllowedNavigation,
            onBlockedNavigation: onBlockedNavigation
        )
        guard let request else { return }
        guard context.coordinator.lastRequestID != request.id else { return }
        context.coordinator.lastRequestID = request.id
        nsView.load(URLRequest(url: request.url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var lastRequestID: UUID?
        private var onNavigation: (URL) -> Void
        private var isAllowedNavigation: (URL) -> Bool
        private var onBlockedNavigation: (URL) -> Void

        init(
            onNavigation: @escaping (URL) -> Void,
            isAllowedNavigation: @escaping (URL) -> Bool,
            onBlockedNavigation: @escaping (URL) -> Void
        ) {
            self.onNavigation = onNavigation
            self.isAllowedNavigation = isAllowedNavigation
            self.onBlockedNavigation = onBlockedNavigation
        }

        func update(
            onNavigation: @escaping (URL) -> Void,
            isAllowedNavigation: @escaping (URL) -> Bool,
            onBlockedNavigation: @escaping (URL) -> Void
        ) {
            self.onNavigation = onNavigation
            self.isAllowedNavigation = isAllowedNavigation
            self.onBlockedNavigation = onBlockedNavigation
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            guard Self.requiresPlatformWhitelist(url) else {
                decisionHandler(.allow)
                return
            }
            if isAllowedNavigation(url) {
                decisionHandler(.allow)
            } else {
                onBlockedNavigation(url)
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let url = webView.url {
                onNavigation(url)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                onNavigation(url)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if let url = webView.url {
                onNavigation(url)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                if Self.requiresPlatformWhitelist(url), !isAllowedNavigation(url) {
                    onBlockedNavigation(url)
                    NSWorkspace.shared.open(url)
                } else {
                    webView.load(navigationAction.request)
                }
            }
            return nil
        }

        private static func requiresPlatformWhitelist(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }
    }
}

struct DanmakuLoadRequest: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

struct DanmakuCookieSnapshot: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let value: String
    let domain: String
    let path: String
    let isSecure: Bool
    let isHTTPOnly: Bool
    let expiresText: String

    init(cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
        if let expiresDate = cookie.expiresDate {
            expiresText = expiresDate.formatted(date: .numeric, time: .shortened)
        } else {
            expiresText = "Session"
        }
    }

    var maskedValue: String {
        guard !value.isEmpty else { return "" }
        if value.count <= 8 {
            return String(repeating: "*", count: min(value.count, 4))
        }
        return "\(value.prefix(4))...\(value.suffix(4)) (\(value.count) chars)"
    }

    var flagsText: String {
        var flags: [String] = []
        if isSecure { flags.append("Secure") }
        if isHTTPOnly { flags.append("HttpOnly") }
        if flags.isEmpty { flags.append("Plain") }
        return flags.joined(separator: " ")
    }

    func displayValue(showFull: Bool) -> String {
        showFull ? value : maskedValue
    }
}

enum DanmakuStatusLevel {
    case info
    case success
    case error
}

enum DanmakuConnectionStatus {
    case idle
    case connecting
    case open
    case closed
    case error
}

struct TaobaoPollResult {
    let nextEndTime: Int?
    let items: [DanmakuTestMessage]
}

struct KuaishouRoomInit {
    let roomId: String
    let title: String
    let liveStreamId: String
    let token: String
    let webSocketURLs: [String]
    let live: Bool
}

struct DanmakuDirectError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

struct DanmakuTestMessage: Identifiable, Equatable {
    let id: String
    let messageId: String
    let user: String
    let content: String
    let roomId: String
    let createdAt: Date

    var timeText: String {
        createdAt.formatted(date: .omitted, time: .standard)
    }

    init(id: String, messageId: String, user: String, content: String, roomId: String, createdAt: Date = Date()) {
        self.id = id
        self.messageId = messageId
        self.user = user
        self.content = content
        self.roomId = roomId
        self.createdAt = createdAt
    }

    init?(payload: [String: Any], platformKey: String) {
        let content = Self.firstText(payload, keys: ["danmuContent", "content", "text", "msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let messageId = Self.firstText(
            payload,
            keys: ["ksMsgId", "msgId", "dyMsgId", "tbMsgId", "xhsMsgId", "wxMsgId", "messageId", "id"]
        )
        let roomId = Self.firstText(
            payload,
            keys: ["dyRoomId", "tbRoomId", "xhsRoomId", "wxRoomId", "ksRoomId", "roomId", "room_id"]
        )
        self.init(
            id: messageId.isEmpty ? "\(Date().timeIntervalSince1970)-\(UUID().uuidString)" : messageId,
            messageId: messageId,
            user: Self.firstText(payload, keys: ["danmuUserName", "nickname", "userName", "user"], fallback: "用户"),
            content: content,
            roomId: roomId.isEmpty ? platformKey : roomId
        )
    }

    static func system(_ text: String) -> DanmakuTestMessage {
        DanmakuTestMessage(
            id: "system-\(Date().timeIntervalSince1970)-\(UUID().uuidString)",
            messageId: "",
            user: "系统",
            content: text,
            roomId: ""
        )
    }

    private static func firstText(_ payload: [String: Any], keys: [String], fallback: String = "") -> String {
        for key in keys {
            if let value = payload[key], !(value is NSNull) {
                return "\(value)"
            }
        }
        return fallback
    }
}
