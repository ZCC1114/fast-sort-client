import AppKit
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
                Text("按迅拣平台配置打开工作台登录页，登录后从当前 WebKit 会话采集平台 Cookie。")
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

            Button("立即采集 Cookie") {
                viewModel.collectCookies(trigger: "点击采集")
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
                Text("弹幕连接")
                    .font(.system(size: 14, weight: .semibold))
                if viewModel.selectedPlatform.requiresDanmuInput {
                    TextField(viewModel.selectedPlatform.danmuInputPlaceholder, text: $viewModel.liveRoomInput)
                        .webTextInput()
                } else {
                    Text(viewModel.selectedPlatform.danmuInputPlaceholder)
                        .font(.system(size: 12))
                        .foregroundStyle(FastSortTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                EmptyPanel(text: viewModel.isDanmuConnected ? "等待平台弹幕消息" : "采集 Cookie 后连接弹幕")
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
    private var activeDirectSession: DanmakuWebSocketSession?
    private var activeNativeConnection: (any NativeDanmakuConnection)?
    private var seenDanmuMessageIds = Set<String>()

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
            return "\(selectedPlatform.name) 暂未移植平台直连弹幕 adapter。需要先补齐 native adapter。"
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
            statusText = "URL 已命中平台成功页规则，2.5 秒后自动采集 Cookie。"
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
        statusText = "正在保存 \(selectedPlatform.name) 工作台登录态到迅拣直播间..."
        statusLevel = .info
        defer { isSavingRoom = false }

        do {
            let service = LiveRoomsService(apiClient: apiClient)
            if selectedPlatform.key == "tb" {
                try await service.addTaobaoRoom(roomName: "淘宝直播间", liveSession: cookieHeader)
                statusText = "淘宝工作台登录态已保存到迅拣直播间 liveSession。开播时会由 native adapter 解析当前直播并直连弹幕。"
            } else {
                try await service.addOrUpdateXiaohongshuRoom(cookies: cookieHeader)
                statusText = "小红书 ark 工作台登录态已保存到迅拣直播间。后续需要补齐 native adapter 的直播解析和弹幕拉取链路。"
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
                ? "请先采集 Cookie。已迁移 native adapter 的平台会优先用工作台 Cookie 自动解析当前直播。"
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
        case .taobao, .xiaohongshu, .kuaishou, .shopee, .douyin, .tiktok, .wechat:
            await runNativeDanmu(adapter: adapter, cookieHeader: cookieHeader)
        }
    }

    private func appendDanmuMessage(_ message: DanmakuTestMessage) {
        danmuMessages = Array((danmuMessages + [message]).suffix(120))
    }

    private func runNativeDanmu(adapter: DanmakuDirectAdapterKind, cookieHeader: String) async {
        do {
            let platformKey = nativePlatformKey(for: adapter)
            guard let nativeAdapter = NativeDanmakuAdapterFactory().adapter(for: platformKey) else {
                throw NativeDanmakuAdapterError.unsupportedPlatform(adapter.displayName)
            }
            let input = liveRoomInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let request = NativeDanmakuConnectRequest(
                platformKey: platformKey,
                roomId: nil,
                roomNumber: input.isEmpty ? nil : input,
                eid: nil,
                liveType: nil,
                liveSession: cookieHeader,
                cookieHeader: cookieHeader,
                displayName: selectedPlatform.name
            )
            let preparedRequest = try await nativeAdapter.prepare(request)
            activeNativeConnection = try await nativeAdapter.connect(
                request: preparedRequest,
                onEvent: { [weak self] event in
                    self?.handleNativeDanmuEvent(event, adapter: adapter)
                }
            )
        } catch {
            guard !Task.isCancelled else { return }
            danmuStatus = .error
            danmuStatusText = "\(adapter.displayName) native adapter 连接失败：\(error.localizedDescription)"
            danmuStatusLevel = .error
            appendDanmuMessage(.system("\(adapter.displayName) native adapter 连接失败：\(error.localizedDescription)"))
            cleanupDanmuTasks()
        }
    }

    private func handleNativeDanmuEvent(_ event: NativeDanmakuEvent, adapter: DanmakuDirectAdapterKind) {
        switch event.event {
        case .status:
            handleNativeStatus(event.status, adapter: adapter)
        case .chat:
            let messageId = event.messageId ?? event.eventId
            guard !seenDanmuMessageIds.contains(messageId) else { return }
            seenDanmuMessageIds.insert(messageId)
            appendDanmuMessage(
                DanmakuTestMessage(
                    id: messageId,
                    messageId: messageId,
                    user: event.userName ?? "用户",
                    content: event.content ?? "",
                    roomId: event.platformRoomId ?? event.roomId ?? ""
                )
            )
            danmuStatus = .open
            danmuStatusText = "\(adapter.displayName) native adapter 收到弹幕。"
            danmuStatusLevel = .success
        case .error:
            danmuStatus = .error
            danmuStatusText = event.content ?? "\(adapter.displayName) native adapter 连接失败。"
            danmuStatusLevel = .error
            appendDanmuMessage(.system(danmuStatusText))
        case .gift, .member, .like, .social, .control:
            break
        }
    }

    private func handleNativeStatus(_ status: NativeDanmakuStatus?, adapter: DanmakuDirectAdapterKind) {
        switch status {
        case .connecting:
            danmuStatus = .connecting
            danmuStatusText = "\(adapter.displayName) native adapter 正在连接平台弹幕。"
            danmuStatusLevel = .info
        case .living:
            danmuStatus = .open
            danmuStatusText = "\(adapter.displayName) native adapter 已连上平台弹幕。"
            danmuStatusLevel = .success
        case .stopped, .disconnected:
            danmuStatus = .closed
            danmuStatusText = "\(adapter.displayName) native adapter 已断开。"
            danmuStatusLevel = .info
        case .loginExpired:
            danmuStatus = .error
            danmuStatusText = "\(adapter.displayName) 登录失效。"
            danmuStatusLevel = .error
        case .notStarted:
            danmuStatus = .error
            danmuStatusText = "\(adapter.displayName) 当前账号未开播。"
            danmuStatusLevel = .error
        case .error:
            danmuStatus = .error
            danmuStatusText = "\(adapter.displayName) native adapter 连接失败。"
            danmuStatusLevel = .error
        case .none:
            break
        }
    }

    private func nativePlatformKey(for adapter: DanmakuDirectAdapterKind) -> String {
        switch adapter {
        case .taobao: return "taobao"
        case .kuaishou: return "kuaishou"
        case .xiaohongshu: return "xiaohongshu"
        case .douyin: return "douyin"
        case .tiktok: return "tiktok"
        case .shopee: return "shopee"
        case .wechat: return "wechat"
        }
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
        activeDirectSession?.cancel()
        activeDirectSession = nil
        activeNativeConnection?.cancel()
        activeNativeConnection = nil
        directDanmuTask?.cancel()
        directDanmuTask = nil
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
