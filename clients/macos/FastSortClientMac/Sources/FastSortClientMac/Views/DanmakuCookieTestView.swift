import AppKit
import Foundation
import SwiftUI
import WebKit

struct DanmakuCookieTestView: View {
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

            if viewModel.canCopyWorkbenchDiagnostics {
                Button(viewModel.isCopyingWorkbenchDiagnostics ? "正在生成诊断..." : "复制抖音捕获诊断") {
                    viewModel.copyWorkbenchDiagnostics()
                }
                .buttonStyle(AccentOutlineButtonStyle())
                .disabled(viewModel.isCopyingWorkbenchDiagnostics)
            }

            if viewModel.selectedPlatform.key == "xhs" {
                Button("打开小红书直播助手") {
                    viewModel.loadXiaohongshuLiveAssistant()
                }
                .buttonStyle(AccentOutlineButtonStyle())
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
                onBlockedNavigation: viewModel.handleBlockedNavigation(url:),
                onWorkbenchCapture: viewModel.handleWorkbenchCapture(payload:)
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
    @Published var showCookieValues = false
    @Published var liveRoomInput = ""
    @Published var danmuStatus = DanmakuConnectionStatus.idle
    @Published var danmuStatusText = "尚未连接弹幕。"
    @Published var danmuStatusLevel = DanmakuStatusLevel.info
    @Published var danmuMessages: [DanmakuTestMessage] = []
    @Published var workbenchCaptureCount = 0
    @Published var isCopyingWorkbenchDiagnostics = false

    let websiteDataStore = DanmakuWebAuthSessionStore.shared.websiteDataStore
    private weak var webView: WKWebView?
    private var didPrepareInitialLoad = false
    private var lastAutoCollectURL = ""
    private var directDanmuTask: Task<Void, Never>?
    private var activeDirectSession: DanmakuWebSocketSession?
    private var activeNativeConnection: (any NativeDanmakuConnection)?
    private var seenDanmuMessageIds = Set<String>()
    private var capturedWorkbenchPayloads: [String] = []
    private var capturedWorkbenchPayloadSignatures = Set<String>()
    private var capturedDouyinRoomInput: String?

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
        clearWorkbenchCaptures()
        lastAutoCollectURL = ""
        statusText = "已切换到 \(platform.name)，准备打开登录页。"
        statusLevel = .info
        loadSelectedPlatform()
    }

    func loadSelectedPlatform() {
        currentURLText = selectedPlatform.loginURL.absoluteString
        isPageMatched = false
        matchText = "等待登录"
        clearWorkbenchCaptures()
        statusText = "已加载 \(selectedPlatform.name) 登录地址。"
        statusLevel = .info
        loadRequest = DanmakuLoadRequest(url: selectedPlatform.loginURL)
    }

    func loadXiaohongshuLiveAssistant() {
        guard selectedPlatform.key == "xhs",
              let url = URL(string: "https://redlive.xiaohongshu.com/live_plan") else { return }
        currentURLText = url.absoluteString
        isPageMatched = false
        matchText = "等待直播助手登录态"
        lastAutoCollectURL = ""
        statusText = "已打开小红书直播助手页。页面加载完成后会自动采集 redlive Cookie，也可以手动点“立即采集 Cookie”。"
        statusLevel = .info
        loadRequest = DanmakuLoadRequest(url: url)
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

    var canCopyWorkbenchDiagnostics: Bool {
        selectedPlatform.directDanmuAdapter == .douyin && workbenchCaptureCount > 0
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

    func handleWorkbenchCapture(payload: DanmakuWebCapturePayload) {
        guard selectedPlatform.directDanmuAdapter == .douyin else { return }
        let text = String(payload.combinedText.prefix(60_000))
        guard !text.isEmpty else { return }
        let signature = payload.signature
        guard !capturedWorkbenchPayloadSignatures.contains(signature) else { return }
        capturedWorkbenchPayloadSignatures.insert(signature)
        capturedWorkbenchPayloads.append(text)
        if capturedWorkbenchPayloads.count > 80 {
            capturedWorkbenchPayloads.removeFirst(capturedWorkbenchPayloads.count - 80)
        }
        workbenchCaptureCount = capturedWorkbenchPayloads.count

        guard let candidate = douyinWorkbenchRoomInputCandidate(from: text) else { return }
        if capturedDouyinRoomInput != candidate {
            statusText = "已从抖店中控接口响应捕获到直播标识：\(candidate)。现在可以点击“连接弹幕”。"
            statusLevel = .success
        }
        capturedDouyinRoomInput = candidate
    }

    func copyWorkbenchDiagnostics() {
        guard canCopyWorkbenchDiagnostics, !isCopyingWorkbenchDiagnostics else { return }
        let payloads = capturedWorkbenchPayloads
        let candidate = capturedDouyinRoomInput
        isCopyingWorkbenchDiagnostics = true
        statusText = "正在生成抖音捕获诊断..."
        statusLevel = .info
        Task.detached(priority: .userInitiated) {
            let diagnostics = DanmakuWorkbenchDiagnosticsBuilder.build(
                payloads: payloads,
                candidate: candidate
            )
            await MainActor.run {
                self.copyToPasteboard(diagnostics)
                self.isCopyingWorkbenchDiagnostics = false
                self.statusText = "已复制抖音捕获诊断，内容已脱敏并限制大小。请把诊断文本发给我用于补齐字段解析。"
                self.statusLevel = .success
            }
        }
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
        clearWorkbenchCaptures()
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
            let input = await nativeRoomInput(adapter: adapter)
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

    private func nativeRoomInput(adapter: DanmakuDirectAdapterKind) async -> String {
        let input = liveRoomInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.isEmpty, adapter == .douyin else { return input }

        if let capturedDouyinRoomInput {
            appendDanmuMessage(.system("已使用抖店中控接口捕获到的直播标识：\(capturedDouyinRoomInput)"))
            return capturedDouyinRoomInput
        }

        if let capturedCandidate = douyinWorkbenchRoomInputCandidate(from: capturedWorkbenchPayloads.joined(separator: "\n")) {
            capturedDouyinRoomInput = capturedCandidate
            appendDanmuMessage(.system("已从已捕获的抖店中控接口响应解析到直播标识：\(capturedCandidate)"))
            return capturedCandidate
        }

        guard let candidate = await douyinRoomInputFromCurrentWebView() else {
            appendDanmuMessage(.system("未能从当前抖店中控页面或已捕获的 \(capturedWorkbenchPayloads.count) 条接口响应解析到 room_id/live_id，将继续用 Cookie 请求工作台兜底；如仍失败，需要等待中控页面刷新接口或补充中控接口 HAR。"))
            return ""
        }

        capturedDouyinRoomInput = candidate
        appendDanmuMessage(.system("已从当前抖店中控页面解析到直播标识：\(candidate)"))
        return candidate
    }

    private func douyinRoomInputFromCurrentWebView() async -> String? {
        guard let webView else { return nil }
        let script = """
        (() => {
          const text = value => {
            if (value === undefined || value === null) return "";
            if (typeof value === "string") return value;
            if (typeof value === "number" || typeof value === "boolean") return String(value);
            try { return JSON.stringify(value); } catch (_) { return ""; }
          };
          const storageDump = store => {
            const output = {};
            if (!store) return output;
            for (let i = 0; i < Math.min(store.length, 200); i += 1) {
              const key = store.key(i);
              if (!key) continue;
              const value = store.getItem(key) || "";
              if (/room|live|webcast|anchor|douyin|aweme/i.test(key + value)) {
                output[key] = value.slice(0, 8000);
              }
            }
            return output;
          };
          const windowHints = {};
          for (const key of Object.keys(window).slice(0, 1200)) {
            if (!/room|live|webcast|anchor|douyin|aweme/i.test(key)) continue;
            try {
              const value = text(window[key]).slice(0, 8000);
              if (value) windowHints[key] = value;
            } catch (_) {}
          }
          const frames = Array.from(document.querySelectorAll("iframe")).slice(0, 20).map(frame => {
            const item = { src: frame.src || "" };
            try {
              item.href = frame.contentWindow && frame.contentWindow.location ? frame.contentWindow.location.href : "";
              item.html = frame.contentDocument && frame.contentDocument.documentElement ? frame.contentDocument.documentElement.outerHTML.slice(0, 120000) : "";
              item.text = frame.contentDocument && frame.contentDocument.body ? frame.contentDocument.body.innerText.slice(0, 40000) : "";
            } catch (_) {}
            return item;
          });
          const scripts = Array.from(document.scripts)
            .map(script => script.src || script.textContent || "")
            .filter(value => /room|live|webcast|anchor|douyin|aweme/i.test(value))
            .join("\\n")
            .slice(0, 120000);
          return JSON.stringify({
            href: location.href,
            title: document.title,
            bodyText: document.body ? document.body.innerText.slice(0, 80000) : "",
            html: document.documentElement ? document.documentElement.outerHTML.slice(0, 240000) : "",
            localStorage: storageDump(window.localStorage),
            sessionStorage: storageDump(window.sessionStorage),
            windowHints,
            frames,
            scripts
          });
        })();
        """

        let rawValue = try? await webView.evaluateJavaScript(script)
        let text = (rawValue as? String) ?? rawValue.map { "\($0)" } ?? ""
        return douyinWorkbenchRoomInputCandidate(from: text)
    }

    private func douyinWorkbenchRoomInputCandidate(from text: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")

        for jsonText in possibleJSONTexts(from: decoded) {
            guard let data = jsonText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let roomId = douyinJSONCandidate(in: object, path: [], mode: .room) {
                return roomId
            }
        }

        let roomKeys = [
            "room_id", "roomId", "webcast_room_id", "webcastRoomId",
            "room_id_str", "roomIdStr", "webcast_room_id_str", "webcastRoomIdStr",
            "live_room_id", "liveRoomId", "live_room_id_str", "liveRoomIdStr",
            "current_room_id", "currentRoomId", "ecom_live_room_id", "ecomLiveRoomId",
            "im_room_id", "imRoomId", "roomID", "RoomId", "roomid", "roomidstr",
            "webcastRoomID", "webcast_roomid", "liveRoomID", "live_roomid"
        ]
        for key in roomKeys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key),
               isDouyinRoomIdCandidate(value) {
                return value
            }
        }

        let roomKeyPattern = roomKeys
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let roomPatterns = [
            #"["'](?:\#(roomKeyPattern))["']\s*[:=]\s*["']?(\d{5,30})"#,
            #"\\?["'](?:\#(roomKeyPattern))\\?["']\s*[:=]\s*\\?["']?(\d{5,30})"#,
            #"(?:(?:\#(roomKeyPattern))=)([0-9]{5,30})"#,
            #"(?i)(?:room|webcast|live)[A-Za-z0-9_\-]{0,48}(?:id|ID|Id)["']?\s*[:=]\s*["']?(\d{5,30})"#
        ]
        for pattern in roomPatterns {
            if let value = firstDouyinRegexValue(in: decoded, pattern: pattern),
               isDouyinRoomIdCandidate(value) {
                return value
            }
        }
        return nil
    }

    private func douyinRoomInputCandidate(from text: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")

        if let jsonCandidate = douyinRoomInputCandidateFromJSON(decoded) {
            return jsonCandidate
        }

        let roomKeys = [
            "room_id", "roomId", "webcast_room_id", "webcastRoomId",
            "room_id_str", "roomIdStr", "webcast_room_id_str", "webcastRoomIdStr",
            "live_room_id", "liveRoomId", "live_room_id_str", "liveRoomIdStr",
            "current_room_id", "currentRoomId", "ecom_live_room_id", "ecomLiveRoomId",
            "im_room_id", "imRoomId", "roomID", "RoomId", "roomid", "roomidstr",
            "webcastRoomID", "webcast_roomid", "liveRoomID", "live_roomid"
        ]
        for key in roomKeys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key),
               isDouyinRoomIdCandidate(value) {
                return value
            }
        }

        let roomKeyPattern = roomKeys
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let roomPatterns = [
            #"["'](?:\#(roomKeyPattern))["']\s*[:=]\s*["']?(\d{5,30})"#,
            #"\\?["'](?:\#(roomKeyPattern))\\?["']\s*[:=]\s*\\?["']?(\d{5,30})"#,
            #"(?:(?:\#(roomKeyPattern))=)([0-9]{5,30})"#,
            #"(?i)(?:room|webcast|live)[A-Za-z0-9_\-]{0,48}(?:id|ID|Id)["']?\s*[:=]\s*["']?(\d{5,30})"#
        ]
        for pattern in roomPatterns {
            if let value = firstDouyinRegexValue(in: decoded, pattern: pattern),
               isDouyinRoomIdCandidate(value) {
                return value
            }
        }

        if let livePageId = NativeDanmakuHTTP.firstRegexMatch(
            in: decoded,
            pattern: #"live\.douyin\.com/([A-Za-z0-9_\-]{4,80})"#
        ) {
            return livePageId
        }

        let liveKeys = [
            "live_id", "liveId", "live_id_str", "liveIdStr",
            "webcastLiveId", "webcast_live_id", "anchorLiveId", "anchor_live_id",
            "douyinId", "authorLiveId", "author_live_id"
        ]
        for key in liveKeys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key),
               isDouyinLiveIdCandidate(value) {
                return value
            }
        }

        let liveKeyPattern = liveKeys
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let livePatterns = [
            #"["'](?:\#(liveKeyPattern))["']\s*[:=]\s*["']?([A-Za-z0-9_\-]{4,80})"#,
            #"\\?["'](?:\#(liveKeyPattern))\\?["']\s*[:=]\s*\\?["']?([A-Za-z0-9_\-]{4,80})"#,
            #"(?i)(?:live|webcast|anchor|douyin)[A-Za-z0-9_\-]{0,48}(?:id|ID|Id)["']?\s*[:=]\s*["']?([A-Za-z0-9_\-]{4,80})"#
        ]
        for pattern in livePatterns {
            if let value = firstDouyinRegexValue(in: decoded, pattern: pattern),
               isDouyinLiveIdCandidate(value) {
                return value
            }
        }

        return nil
    }

    private func douyinRoomInputCandidateFromJSON(_ text: String) -> String? {
        for jsonText in possibleJSONTexts(from: text) {
            guard let data = jsonText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let roomId = douyinJSONCandidate(in: object, path: [], mode: .room) {
                return roomId
            }
            if let liveId = douyinJSONCandidate(in: object, path: [], mode: .live) {
                return liveId
            }
        }
        return nil
    }

    private enum DouyinJSONCandidateMode {
        case room
        case live
    }

    private func douyinJSONCandidate(in value: Any, path: [String], mode: DouyinJSONCandidateMode) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, item) in dictionary {
                let normalizedKey = normalizeDouyinFieldKey(key)
                let fullPath = path + [normalizedKey]
                guard let text = douyinJSONStringValue(item) else { continue }
                switch mode {
                case .room:
                    if douyinKeyLooksLikeRoomId(normalizedKey, path: fullPath), isDouyinRoomIdCandidate(text) {
                        return text
                    }
                case .live:
                    if douyinKeyLooksLikeLiveId(normalizedKey, path: fullPath), isDouyinLiveIdCandidate(text) {
                        return text
                    }
                }
            }
            for (key, item) in dictionary {
                if let candidate = douyinJSONCandidate(in: item, path: path + [normalizeDouyinFieldKey(key)], mode: mode) {
                    return candidate
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let candidate = douyinJSONCandidate(in: item, path: path, mode: mode) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func possibleJSONTexts(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var outputs: [String] = []
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            outputs.append(trimmed)
        }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            outputs.append(String(trimmed[start...end]))
        }
        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]"), start < end {
            outputs.append(String(trimmed[start...end]))
        }
        return Array(Set(outputs))
    }

    private func normalizeDouyinFieldKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private func douyinJSONStringValue(_ value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func douyinKeyLooksLikeRoomId(_ key: String, path: [String]) -> Bool {
        let pathText = path.joined(separator: ".")
        let exact = Set([
            "roomid", "roomidstr", "webcastroomid", "webcastroomidstr",
            "liveroomid", "liveroomidstr", "currentroomid", "ecomliveroomid", "imroomid"
        ])
        if exact.contains(key) { return true }
        if key == "id", path.dropLast().contains(where: { $0.contains("room") || $0.contains("webcast") }) {
            return true
        }
        return pathText.contains("room") && key.contains("id")
    }

    private func douyinKeyLooksLikeLiveId(_ key: String, path: [String]) -> Bool {
        let pathText = path.joined(separator: ".")
        let exact = Set([
            "liveid", "liveidstr", "webcastliveid", "webcastliveidstr",
            "anchorliveid", "authorliveid", "douyinid"
        ])
        if exact.contains(key) { return true }
        if key == "id", path.dropLast().contains(where: { $0.contains("live") || $0.contains("anchor") }) {
            return true
        }
        return (pathText.contains("live") || pathText.contains("anchor") || pathText.contains("webcast")) && key.contains("id")
    }

    private func firstDouyinRegexValue(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        for index in stride(from: match.numberOfRanges - 1, through: 1, by: -1) {
            guard let valueRange = Range(match.range(at: index), in: text) else { continue }
            let value = String(text[valueRange])
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func isDouyinRoomIdCandidate(_ value: String) -> Bool {
        value.range(of: #"^\d{5,30}$"#, options: .regularExpression) != nil
    }

    private func isDouyinLiveIdCandidate(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_\-]{4,80}$"#, options: .regularExpression) != nil
    }

    private func clearWorkbenchCaptures() {
        capturedWorkbenchPayloads = []
        capturedWorkbenchPayloadSignatures = []
        capturedDouyinRoomInput = nil
        workbenchCaptureCount = 0
        isCopyingWorkbenchDiagnostics = false
    }

    private func buildWorkbenchDiagnostics() -> String {
        let joinedPayloads = capturedWorkbenchPayloads.joined(separator: "\n")
        let candidate = capturedDouyinRoomInput ?? douyinRoomInputCandidate(from: joinedPayloads)
        let sections = capturedWorkbenchPayloads.enumerated().map { index, payload in
            let masked = maskSensitiveWorkbenchText(payload)
            return """
            ## capture \(index + 1)
            \(workbenchDiagnosticSnippet(from: masked))
            """
        }
        return """
        # Douyin Workbench Capture Diagnostic
        generated_at: \(ISO8601DateFormatter().string(from: Date()))
        captured_count: \(capturedWorkbenchPayloads.count)
        parsed_candidate: \(candidate ?? "nil")

        \(sections.joined(separator: "\n\n"))
        """
    }

    private func maskSensitiveWorkbenchText(_ text: String) -> String {
        var output = text
        let replacements = [
            (#"(?i)(["']?[A-Za-z0-9_\-]*(?:token|cookie|session|authorization|auth|ticket|csrf|sign|signature|secret|passwd|password|sid)[A-Za-z0-9_\-]*["']?\s*[:=]\s*["']?)([^"',&\s}\]]{4,})"#, "$1***"),
            (#"(?i)((?:token|cookie|session|authorization|auth|ticket|csrf|sign|signature|secret|passwd|password|sid)[A-Za-z0-9_\-]*=)[^&\s"']+"#, "$1***"),
            (#"([A-Za-z0-9_\-=]{96,})"#, "***long-value***")
        ]
        for (pattern, template) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: template)
        }
        return output
    }

    private func workbenchDiagnosticSnippet(from text: String) -> String {
        let keywords = #"(?i)(room|webcast|live|anchor|douyin|comment|message|chat|control|直播|中控|互动)"#
        guard let regex = try? NSRegularExpression(pattern: keywords) else {
            return String(text.prefix(1600))
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return String(text.prefix(1600))
        }

        var snippets: [String] = []
        var usedRanges: [Range<String.Index>] = []
        for match in matches.prefix(8) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let lower = text.index(matchRange.lowerBound, offsetBy: -360, limitedBy: text.startIndex) ?? text.startIndex
            let upper = text.index(matchRange.upperBound, offsetBy: 520, limitedBy: text.endIndex) ?? text.endIndex
            let snippetRange = lower..<upper
            if usedRanges.contains(where: { rangesOverlap($0, snippetRange) }) {
                continue
            }
            usedRanges.append(snippetRange)
            snippets.append(String(text[snippetRange]))
        }
        return snippets.joined(separator: "\n---\n")
    }

    private func rangesOverlap(_ left: Range<String.Index>, _ right: Range<String.Index>) -> Bool {
        left.lowerBound < right.upperBound && right.lowerBound < left.upperBound
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
            let names = Set(filtered.map(\.name))
            if selectedPlatform.key == "xhs", !names.contains("access-token-redlive.xiaohongshu.com") {
                statusText = "\(trigger)完成，采集到 \(filtered.count) 条 Cookie，但缺少 redlive token。请点击“打开小红书直播助手”，页面加载成功后重新采集 Cookie。域名：\(domains)"
                statusLevel = .error
                return
            }
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

private enum DanmakuWorkbenchDiagnosticsBuilder {
    static func build(payloads: [String], candidate: String?) -> String {
        let sampledPayloads = payloads.suffix(12).map { String($0.prefix(8_000)) }
        let sections = sampledPayloads.enumerated().map { index, payload in
            let masked = maskSensitiveText(payload)
            return """
            ## capture \(payloads.count - sampledPayloads.count + index + 1)
            \(diagnosticSnippet(from: masked))
            """
        }
        let output = """
        # Douyin Workbench Capture Diagnostic
        generated_at: \(ISO8601DateFormatter().string(from: Date()))
        captured_count: \(payloads.count)
        sampled_count: \(sampledPayloads.count)
        parsed_candidate: \(candidate ?? "nil")

        \(sections.joined(separator: "\n\n"))
        """
        return String(output.prefix(60_000))
    }

    private static func maskSensitiveText(_ text: String) -> String {
        var output = text
        let replacements = [
            (#"(?i)(["']?[A-Za-z0-9_\-]*(?:token|cookie|session|authorization|auth|ticket|csrf|sign|signature|secret|passwd|password|sid)[A-Za-z0-9_\-]*["']?\s*[:=]\s*["']?)([^"',&\s}\]]{4,})"#, "$1***"),
            (#"(?i)((?:token|cookie|session|authorization|auth|ticket|csrf|sign|signature|secret|passwd|password|sid)[A-Za-z0-9_\-]*=)[^&\s"']+"#, "$1***"),
            (#"([A-Za-z0-9_\-=]{96,})"#, "***long-value***")
        ]
        for (pattern, template) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: template)
        }
        return output
    }

    private static func diagnosticSnippet(from text: String) -> String {
        let keywords = #"(?i)(room|webcast|live|anchor|douyin|comment|message|chat|control|直播|中控|互动)"#
        guard let regex = try? NSRegularExpression(pattern: keywords) else {
            return String(text.prefix(1200))
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return String(text.prefix(1200))
        }

        var snippets: [String] = []
        var usedRanges: [Range<String.Index>] = []
        for match in matches.prefix(5) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let lower = text.index(matchRange.lowerBound, offsetBy: -240, limitedBy: text.startIndex) ?? text.startIndex
            let upper = text.index(matchRange.upperBound, offsetBy: 360, limitedBy: text.endIndex) ?? text.endIndex
            let snippetRange = lower..<upper
            if usedRanges.contains(where: { rangesOverlap($0, snippetRange) }) {
                continue
            }
            usedRanges.append(snippetRange)
            snippets.append(String(text[snippetRange]))
        }
        return snippets.joined(separator: "\n---\n")
    }

    private static func rangesOverlap(_ left: Range<String.Index>, _ right: Range<String.Index>) -> Bool {
        left.lowerBound < right.upperBound && right.lowerBound < left.upperBound
    }
}

struct DanmakuWebCapturePayload {
    let kind: String
    let url: String
    let status: Int
    let href: String
    let text: String

    var combinedText: String {
        [kind, url, "\(status)", href, text]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var signature: String {
        [
            kind,
            url,
            "\(status)",
            String(text.prefix(512))
        ].joined(separator: "|")
    }
}

private struct DanmakuAuthWebView: NSViewRepresentable {
    let request: DanmakuLoadRequest?
    let dataStore: WKWebsiteDataStore
    let onWebViewReady: (WKWebView) -> Void
    let onNavigation: (URL) -> Void
    let isAllowedNavigation: (URL) -> Bool
    let onBlockedNavigation: (URL) -> Void
    let onWorkbenchCapture: (DanmakuWebCapturePayload) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onNavigation: onNavigation,
            isAllowedNavigation: isAllowedNavigation,
            onBlockedNavigation: onBlockedNavigation,
            onWorkbenchCapture: onWorkbenchCapture
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: Coordinator.captureHandlerName)
        userContentController.addUserScript(
            WKUserScript(
                source: Coordinator.captureScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        configuration.userContentController = userContentController
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
            onBlockedNavigation: onBlockedNavigation,
            onWorkbenchCapture: onWorkbenchCapture
        )
        guard let request else { return }
        guard context.coordinator.lastRequestID != request.id else { return }
        context.coordinator.lastRequestID = request.id
        nsView.load(URLRequest(url: request.url))
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.captureHandlerName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let captureHandlerName = "fastSortDanmakuCapture"
        static let captureScript = #"""
        (() => {
          if (window.__fastSortDanmakuCaptureInstalled) return;
          window.__fastSortDanmakuCaptureInstalled = true;

          const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.fastSortDanmakuCapture;
          const keywordPattern = /jinritemai|douyin|bytedance|webcast|room|live|anchor|comment|message|chat|control|互动|直播|中控/i;
          const text = value => {
            if (value === undefined || value === null) return "";
            if (typeof value === "string") return value;
            if (value instanceof ArrayBuffer) return "";
            try { return JSON.stringify(value); } catch (_) { return String(value); }
          };
          const post = (kind, url, status, value) => {
            try {
              if (!handler) return;
              const body = text(value);
              if (!body && !url) return;
              const sample = `${url || ""}\n${body.slice(0, 2000)}`;
              if (!keywordPattern.test(sample)) return;
              handler.postMessage({
                kind,
                url: String(url || ""),
                status: Number(status || 0),
                href: String(location.href || ""),
                text: body.slice(0, 60000),
                ts: Date.now()
              });
            } catch (_) {}
          };
          const shouldReadBody = (url, contentType) => {
            const target = String(url || "");
            const type = String(contentType || "");
            return keywordPattern.test(target) || /json|text|javascript|html|xml/i.test(type);
          };

          const nativeFetch = window.fetch;
          if (typeof nativeFetch === "function") {
            window.fetch = function(input, init) {
              const url = typeof input === "string" ? input : (input && input.url) || "";
              return nativeFetch.apply(this, arguments).then(response => {
                try {
                  const contentType = response.headers && response.headers.get ? response.headers.get("content-type") : "";
                  if (shouldReadBody(url || response.url, contentType)) {
                    response.clone().text()
                      .then(body => post("fetch", url || response.url, response.status, body))
                      .catch(() => {});
                  } else {
                    post("fetch-url", url || response.url, response.status, url || response.url);
                  }
                } catch (_) {}
                return response;
              });
            };
          }

          const nativeOpen = XMLHttpRequest.prototype.open;
          const nativeSend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function(method, url) {
            this.__fastSortDanmakuURL = url;
            this.__fastSortDanmakuMethod = method;
            return nativeOpen.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function() {
            try {
              this.addEventListener("loadend", () => {
                try {
                  const url = this.responseURL || this.__fastSortDanmakuURL || "";
                  const contentType = this.getResponseHeader ? this.getResponseHeader("content-type") : "";
                  if (!shouldReadBody(url, contentType)) {
                    post("xhr-url", url, this.status, url);
                    return;
                  }
                  let body = "";
                  if (!this.responseType || this.responseType === "text") {
                    body = this.responseText || "";
                  } else if (this.responseType === "json") {
                    body = text(this.response);
                  }
                  post("xhr", url, this.status, body);
                } catch (_) {}
              });
            } catch (_) {}
            return nativeSend.apply(this, arguments);
          };

          const NativeWebSocket = window.WebSocket;
          if (typeof NativeWebSocket === "function") {
            const FastSortWebSocket = function(url, protocols) {
              post("websocket-open", url, 0, String(url || ""));
              const socket = protocols === undefined ? new NativeWebSocket(url) : new NativeWebSocket(url, protocols);
              try {
                socket.addEventListener("message", event => {
                  if (typeof event.data === "string") {
                    post("websocket-message", url, 0, event.data);
                  }
                });
              } catch (_) {}
              return socket;
            };
            FastSortWebSocket.prototype = NativeWebSocket.prototype;
            try { Object.setPrototypeOf(FastSortWebSocket, NativeWebSocket); } catch (_) {}
            for (const key of ["CONNECTING", "OPEN", "CLOSING", "CLOSED"]) {
              try { Object.defineProperty(FastSortWebSocket, key, { value: NativeWebSocket[key] }); } catch (_) {}
            }
            window.WebSocket = FastSortWebSocket;
          }
        })();
        """#

        var lastRequestID: UUID?
        private var onNavigation: (URL) -> Void
        private var isAllowedNavigation: (URL) -> Bool
        private var onBlockedNavigation: (URL) -> Void
        private var onWorkbenchCapture: (DanmakuWebCapturePayload) -> Void

        init(
            onNavigation: @escaping (URL) -> Void,
            isAllowedNavigation: @escaping (URL) -> Bool,
            onBlockedNavigation: @escaping (URL) -> Void,
            onWorkbenchCapture: @escaping (DanmakuWebCapturePayload) -> Void
        ) {
            self.onNavigation = onNavigation
            self.isAllowedNavigation = isAllowedNavigation
            self.onBlockedNavigation = onBlockedNavigation
            self.onWorkbenchCapture = onWorkbenchCapture
        }

        func update(
            onNavigation: @escaping (URL) -> Void,
            isAllowedNavigation: @escaping (URL) -> Bool,
            onBlockedNavigation: @escaping (URL) -> Void,
            onWorkbenchCapture: @escaping (DanmakuWebCapturePayload) -> Void
        ) {
            self.onNavigation = onNavigation
            self.isAllowedNavigation = isAllowedNavigation
            self.onBlockedNavigation = onBlockedNavigation
            self.onWorkbenchCapture = onWorkbenchCapture
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
            webView.evaluateJavaScript(Self.captureScript, completionHandler: nil)
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

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.captureHandlerName,
                  let body = message.body as? [String: Any] else { return }
            let payload = DanmakuWebCapturePayload(
                kind: body["kind"] as? String ?? "",
                url: body["url"] as? String ?? "",
                status: body["status"] as? Int ?? 0,
                href: body["href"] as? String ?? "",
                text: body["text"] as? String ?? ""
            )
            DispatchQueue.main.async { [onWorkbenchCapture] in
                onWorkbenchCapture(payload)
            }
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
