import AppKit
import Foundation
import SwiftUI
import WebKit

struct DanmakuCookieTestView: View {
    @StateObject private var viewModel = DanmakuCookieTestViewModel()
    @State private var authWindowController: DanmakuAuthWindowController?

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 16) {
                controlPanel
                    .frame(width: 360)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 14) {
                    cookiePanel
                        .frame(maxWidth: .infinity)
                        .frame(height: max(210, min(300, proxy.size.height * 0.26)))
                    danmuPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
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
                Text("点击平台会直接打开独立登录窗口，登录后从当前 WebKit 会话采集平台 Cookie。")
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

            if !viewModel.statusText.isEmpty {
                Text(viewModel.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(viewModel.statusLevel == .error ? FastSortTheme.danger : FastSortTheme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("打开登录页") {
                    openAuthWindow(loadSelectedPlatform: true)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("独立窗口") {
                    openAuthWindow()
                }
                .buttonStyle(AccentOutlineButtonStyle())
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
                Button(viewModel.workbenchDiagnosticsButtonTitle) {
                    viewModel.copyWorkbenchDiagnostics()
                }
                .buttonStyle(AccentOutlineButtonStyle())
                .disabled(viewModel.isCopyingWorkbenchDiagnostics)
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
                    if !message.subtitleId.isEmpty {
                        Text(message.subtitleId)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(FastSortTheme.muted)
                    }
                }
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(FastSortTheme.text)
                    .textSelection(.enabled)
                if !message.rawText.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("组装内容")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FastSortTheme.muted)
                        Text(message.rawText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(FastSortTheme.muted)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FastSortTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .macHoverRow(
            shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
            normalBackground: FastSortTheme.groupedBackground,
            hoverBackground: FastSortTheme.rowHover,
            hoverBorder: FastSortTheme.accent.opacity(0.22)
        )
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
            if active {
                openAuthWindow(loadSelectedPlatform: !viewModel.isAuthWindowOpen)
            } else {
                viewModel.selectPlatform(platform)
                openAuthWindow()
            }
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
            .macHoverRow(
                active: active,
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                normalBackground: FastSortTheme.groupedBackground,
                activeBackground: FastSortTheme.accentSoft,
                hoverBackground: FastSortTheme.rowHover,
                activeHoverBackground: FastSortTheme.activeHover,
                normalBorder: Color.clear,
                activeBorder: FastSortTheme.accent.opacity(0.16),
                hoverBorder: FastSortTheme.accent.opacity(0.28)
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .buttonStyle(.plain)
    }

    private func openAuthWindow(loadSelectedPlatform: Bool = false) {
        if loadSelectedPlatform {
            viewModel.loadSelectedPlatform()
        }
        if let authWindowController {
            if authWindowController.isClosed {
                self.authWindowController = nil
            } else {
                authWindowController.show()
                return
            }
        }
        let controller = DanmakuAuthWindowController(viewModel: viewModel) {
            viewModel.markAuthWindowClosed()
        }
        authWindowController = controller
        viewModel.markAuthWindowOpened()
        controller.show()
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
        .macHoverRow(
            shape: Rectangle(),
            normalBackground: Color.clear,
            hoverBackground: FastSortTheme.rowHover,
            hoverBorder: nil,
            borderWidth: 0
        )
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
    @Published var isAuthWindowOpen = false

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
    private var capturedXiaohongshuRoomInput: String?
    private var capturedXiaohongshuRoomInputIsTrusted = false

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

    func markAuthWindowOpened() {
        isAuthWindowOpen = true
    }

    func markAuthWindowClosed() {
        isAuthWindowOpen = false
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
        guard let adapter = selectedPlatform.directDanmuAdapter else { return false }
        return [.douyin, .wechat, .xiaohongshu, .taobao].contains(adapter) && workbenchCaptureCount > 0
    }

    var workbenchDiagnosticsButtonTitle: String {
        if isCopyingWorkbenchDiagnostics {
            return "正在生成诊断..."
        }
        return "复制\(selectedPlatform.directDanmuAdapter?.displayName ?? "平台")捕获诊断"
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
        guard let adapter = selectedPlatform.directDanmuAdapter,
              [.douyin, .wechat, .xiaohongshu, .taobao].contains(adapter) else { return }
        let text = String(payload.combinedText.prefix(60_000))
        guard !text.isEmpty else { return }
        guard storeWorkbenchPayload(text: text, signature: payload.signature) else { return }

        switch adapter {
        case .douyin:
            if selectedPlatform.key == "dy_web",
               !shouldUseDouyinWebCapturedPayloadForRoomInput(text) {
                return
            }
            guard let candidate = douyinWorkbenchRoomInputCandidate(from: text) else { return }
            if selectedPlatform.key == "dy_web",
               isDouyinPublicRoomIdCandidate(candidate) {
                return
            }
            if capturedDouyinRoomInput != candidate {
                let sourceName = selectedPlatform.key == "dy_web" ? "抖音网页响应" : "抖店中控接口响应"
                statusText = "已从\(sourceName)捕获到直播标识：\(candidate)。现在可以点击“连接弹幕”。"
                statusLevel = .success
            }
            capturedDouyinRoomInput = candidate
        case .wechat:
            if wechatPayloadContainsMessages(text) {
                statusText = "已捕获到视频号工作台直播评论响应。现在可以点击“连接弹幕”。"
                statusLevel = .success
            } else if wechatPayloadLooksUseful(text) {
                statusText = "已捕获到视频号工作台接口响应；未捕获评论流时会回退到 sessionid/wxuin native 请求。"
                statusLevel = .info
            }
        case .xiaohongshu:
            if xiaohongshuPayloadContainsMessages(text) {
                statusText = "已捕获到小红书 ark 直播中控弹幕响应。现在可以点击“连接弹幕”。"
                statusLevel = .success
                if let candidate = xiaohongshuRoomInputCandidate(from: text),
                   shouldReplaceXiaohongshuRoomInput(current: capturedXiaohongshuRoomInput, candidate: candidate) || !capturedXiaohongshuRoomInputIsTrusted {
                    capturedXiaohongshuRoomInput = candidate
                    capturedXiaohongshuRoomInputIsTrusted = true
                }
            } else if let candidate = xiaohongshuRoomInputCandidate(from: text) {
                let isTrusted = xiaohongshuRoomInputPayloadIsTrusted(text)
                if shouldReplaceXiaohongshuRoomInput(current: capturedXiaohongshuRoomInput, candidate: candidate)
                    || (isTrusted && !capturedXiaohongshuRoomInputIsTrusted) {
                    capturedXiaohongshuRoomInput = candidate
                    capturedXiaohongshuRoomInputIsTrusted = isTrusted
                    if isTrusted {
                        statusText = "已从小红书直播接口响应捕获到直播标识：\(candidate)。现在可以点击“连接弹幕”。"
                        statusLevel = .success
                    } else {
                        statusText = "已保存小红书低置信度直播标识：\(candidate)。该值仅用于诊断，连接时会继续使用 ark 中控捕获流。"
                        statusLevel = .info
                    }
                }
            } else if xiaohongshuPayloadLooksUseful(text) {
                statusText = "已捕获到小红书 ark 工作台接口响应；采集 Cookie 后可直接连接弹幕。"
                statusLevel = .info
            }
        case .taobao:
            if text.localizedCaseInsensitiveContains("impaas")
                || text.localizedCaseInsensitiveContains("powermsg")
                || text.localizedCaseInsensitiveContains("live/message") {
                statusText = "已捕获到淘宝弹幕接口响应。现在可以点击“连接弹幕”。"
                statusLevel = .success
            }
        default:
            break
        }
    }

    private func storeWorkbenchPayload(text: String, signature: String) -> Bool {
        guard !capturedWorkbenchPayloadSignatures.contains(signature) else { return false }
        capturedWorkbenchPayloadSignatures.insert(signature)
        capturedWorkbenchPayloads.append(text)
        while capturedWorkbenchPayloads.count > 200 {
            if let removableIndex = capturedWorkbenchPayloads.firstIndex(where: { payload in
                !payload.localizedCaseInsensitiveContains("websocket-")
                    && !payload.localizedCaseInsensitiveContains("frontier.snssdk.com")
                    && !payload.localizedCaseInsensitiveContains("mmfinderassistant-bin/live/msg")
                    && !payload.localizedCaseInsensitiveContains("xiaohongshu")
                    && !payload.localizedCaseInsensitiveContains("ark")
                    && !payload.localizedCaseInsensitiveContains("taobao")
                    && !payload.localizedCaseInsensitiveContains("impaas")
                    && !payload.localizedCaseInsensitiveContains("ws-msgacs")
                    && !payload.localizedCaseInsensitiveContains("powermsg")
            }) {
                capturedWorkbenchPayloads.remove(at: removableIndex)
            } else {
                capturedWorkbenchPayloads.removeFirst()
            }
        }
        workbenchCaptureCount = capturedWorkbenchPayloads.count
        return true
    }

    private func wechatPayloadLooksUseful(_ text: String) -> Bool {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
        return decoded.localizedCaseInsensitiveContains("mmfinderassistant-bin/live/msg")
            || decoded.localizedCaseInsensitiveContains("\"msgList\"")
            || decoded.localizedCaseInsensitiveContains("\"msg_list\"")
            || decoded.localizedCaseInsensitiveContains("respJsonStr")
            || decoded.localizedCaseInsensitiveContains("liveCookies")
            || decoded.localizedCaseInsensitiveContains("liveObjectId")
            || decoded.localizedCaseInsensitiveContains("finderUsername")
    }

    private func wechatPayloadContainsMessages(_ text: String) -> Bool {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
        return decoded.localizedCaseInsensitiveContains("mmfinderassistant-bin/live/msg")
            || decoded.localizedCaseInsensitiveContains("\"msgList\"")
            || decoded.localizedCaseInsensitiveContains("\"msg_list\"")
            || decoded.localizedCaseInsensitiveContains("respJsonStr")
    }

    private func wechatFinderUsernameCandidate(from text: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")

        for jsonText in possibleJSONTexts(from: decoded) {
            guard let data = jsonText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let candidate = wechatFinderUsernameCandidate(in: object) {
                return candidate
            }
        }

        return NativeDanmakuHTTP.firstRegexMatch(
            in: decoded,
            pattern: #""finderUsername"\s*:\s*"([^"]{6,128})""#
        )
    }

    private func wechatFinderUsernameCandidate(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let text = dictionary["finderUsername"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            for item in dictionary.values {
                if let candidate = wechatFinderUsernameCandidate(in: item) {
                    return candidate
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let candidate = wechatFinderUsernameCandidate(in: item) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func xiaohongshuPayloadLooksUseful(_ text: String) -> Bool {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
        return decoded.localizedCaseInsensitiveContains("ark.xiaohongshu.com")
            || decoded.localizedCaseInsensitiveContains("xiaohongshu")
            || decoded.localizedCaseInsensitiveContains("room_id")
            || decoded.localizedCaseInsensitiveContains("roomId")
            || decoded.localizedCaseInsensitiveContains("liveId")
            || decoded.localizedCaseInsensitiveContains("customData")
            || decoded.localizedCaseInsensitiveContains("comment")
            || decoded.localizedCaseInsensitiveContains("评论")
            || decoded.localizedCaseInsensitiveContains("直播中控")
    }

    private func xiaohongshuPayloadContainsMessages(_ text: String) -> Bool {
        !xiaohongshuEvents(fromWorkbenchPayload: text).isEmpty
    }

    private func xiaohongshuRoomInputPayloadIsTrusted(_ text: String) -> Bool {
        if xiaohongshuPayloadContainsMessages(text) {
            return true
        }
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
        let lowercased = decoded.lowercased()
        if lowercased.contains("customdata")
            || lowercased.contains("commentid")
            || lowercased.contains("ack_code")
            || lowercased.contains("live-assistant.xiaohongshu.com")
            || lowercased.contains("living_room") {
            return true
        }
        return decoded.localizedCaseInsensitiveContains("room_id")
            || decoded.localizedCaseInsensitiveContains("roomId")
            || decoded.localizedCaseInsensitiveContains("liveRoomId")
            || decoded.localizedCaseInsensitiveContains("live_room_id")
            || decoded.localizedCaseInsensitiveContains("xhsRoomId")
    }

    private func trustedXiaohongshuRoomInputCandidate() -> String? {
        if let capturedXiaohongshuRoomInput,
           capturedXiaohongshuRoomInputIsTrusted,
           isXiaohongshuRoomCandidate(capturedXiaohongshuRoomInput) {
            return capturedXiaohongshuRoomInput
        }

        for payload in capturedWorkbenchPayloads.reversed() {
            guard xiaohongshuRoomInputPayloadIsTrusted(payload),
                  let candidate = xiaohongshuRoomInputCandidate(from: payload),
                  isXiaohongshuRoomCandidate(candidate) else { continue }
            capturedXiaohongshuRoomInput = candidate
            capturedXiaohongshuRoomInputIsTrusted = true
            return candidate
        }
        return nil
    }

    private func xiaohongshuRoomInputCandidate(from text: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")

        for jsonText in possibleJSONTexts(from: decoded) {
            guard let data = jsonText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let roomId = xiaohongshuJSONRoomCandidate(in: object, path: []) {
                return roomId
            }
        }

        let roomKeys = [
            "room_id", "roomId", "room_id_str", "roomIdStr",
            "live_room_id", "liveRoomId", "live_id", "liveId",
            "current_room_id", "currentRoomId", "xhsRoomId",
            "broadcastId", "broadcast_id", "roomOid", "room_id"
        ]
        for key in roomKeys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key),
               isXiaohongshuRoomCandidate(value) {
                return value
            }
        }

        let roomKeyPattern = roomKeys
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let roomPatterns = [
            #"["'](?:\#(roomKeyPattern))["']\s*[:=]\s*["']?([A-Za-z0-9_\-]{5,80})"#,
            #"\\?["'](?:\#(roomKeyPattern))\\?["']\s*[:=]\s*\\?["']?([A-Za-z0-9_\-]{5,80})"#,
            #"(?:(?:\#(roomKeyPattern))=)([A-Za-z0-9_\-]{5,80})"#,
            #"(?i)(?:room|live)[A-Za-z0-9_\-]{0,48}(?:id|ID|Id)["']?\s*[:=]\s*["']?([A-Za-z0-9_\-]{5,80})"#
        ]
        for pattern in roomPatterns {
            if let value = firstRegexValue(in: decoded, pattern: pattern),
               isXiaohongshuRoomCandidate(value) {
                return value
            }
        }
        return nil
    }

    private func xiaohongshuJSONRoomCandidate(in value: Any, path: [String]) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, item) in dictionary {
                let normalizedKey = normalizePlatformFieldKey(key)
                let fullPath = path + [normalizedKey]
                guard xiaohongshuKeyLooksLikeRoomId(normalizedKey, path: fullPath),
                      let text = platformJSONStringValue(item),
                      isXiaohongshuRoomCandidate(text) else { continue }
                return text
            }
            for (key, item) in dictionary {
                if let candidate = xiaohongshuJSONRoomCandidate(in: item, path: path + [normalizePlatformFieldKey(key)]) {
                    return candidate
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let candidate = xiaohongshuJSONRoomCandidate(in: item, path: path) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func xiaohongshuKeyLooksLikeRoomId(_ key: String, path: [String]) -> Bool {
        let pathText = path.joined(separator: ".")
        let exact = Set([
            "roomid", "roomidstr", "roomoid", "xhsroomid",
            "liveroomid", "liveroomidstr", "liveid", "liveidstr",
            "currentroomid", "broadcastid"
        ])
        if exact.contains(key) { return true }
        if key == "id", path.dropLast().contains(where: { $0.contains("room") || $0.contains("live") || $0.contains("broadcast") }) {
            return true
        }
        return (pathText.contains("room") || pathText.contains("live") || pathText.contains("broadcast")) && key.contains("id")
    }

    private func isXiaohongshuRoomCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let blockedLiterals = Set([
            "array", "bigint", "boolean", "false", "function", "home",
            "login", "null", "number", "object", "promise", "record",
            "seller", "string", "symbol", "ticket", "true", "undefined"
        ])
        guard trimmed.range(of: #"^[A-Za-z0-9_\-]{5,80}$"#, options: .regularExpression) != nil else { return false }
        guard trimmed.range(of: #"\d"#, options: .regularExpression) != nil else { return false }
        guard !blockedLiterals.contains(lowercased) else { return false }
        guard trimmed.range(of: #"^\d{1,4}$"#, options: .regularExpression) == nil else { return false }
        guard trimmed.localizedCaseInsensitiveContains("home") == false else { return false }
        return true
    }

    private func shouldReplaceXiaohongshuRoomInput(current: String?, candidate: String) -> Bool {
        guard isXiaohongshuRoomCandidate(candidate) else { return false }
        guard let current = current?.trimmingCharacters(in: .whitespacesAndNewlines),
              isXiaohongshuRoomCandidate(current) else {
            return true
        }
        return xiaohongshuRoomCandidateScore(candidate) > xiaohongshuRoomCandidateScore(current)
    }

    private func xiaohongshuRoomCandidateScore(_ value: String) -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var score = trimmed.count
        if trimmed.range(of: #"^\d{8,30}$"#, options: .regularExpression) != nil {
            score += 1_000
        }
        if trimmed.range(of: #"^[A-Fa-f0-9]{16,40}$"#, options: .regularExpression) != nil {
            score += 200
        }
        return score
    }

    private func capturedWorkbenchCandidateText() -> String? {
        switch selectedPlatform.directDanmuAdapter {
        case .douyin:
            if selectedPlatform.key == "dy_web",
               let capturedDouyinRoomInput,
               isDouyinPublicRoomIdCandidate(capturedDouyinRoomInput) {
                return nil
            }
            return capturedDouyinRoomInput
        case .xiaohongshu:
            guard let capturedXiaohongshuRoomInput,
                  isXiaohongshuRoomCandidate(capturedXiaohongshuRoomInput) else { return nil }
            return capturedXiaohongshuRoomInput
        case .taobao:
            return taobaoRoomInputCandidate(from: capturedWorkbenchPayloads.joined(separator: "\n"))
                ?? taobaoRoomInputCandidate(from: currentURLText)
        case .wechat, .kuaishou, .shopee, .tiktok, .none:
            return nil
        }
    }

    func copyWorkbenchDiagnostics() {
        guard canCopyWorkbenchDiagnostics, !isCopyingWorkbenchDiagnostics else { return }
        isCopyingWorkbenchDiagnostics = true
        let platformName = selectedPlatform.directDanmuAdapter?.displayName ?? selectedPlatform.name
        statusText = "正在生成\(platformName)捕获诊断..."
        statusLevel = .info
        Task { @MainActor in
            var payloads = capturedWorkbenchPayloads
            if selectedPlatform.directDanmuAdapter == .xiaohongshu,
               let snapshot = await xiaohongshuPageSnapshotText() {
                payloads.append("live-center-dom\n\(snapshot)")
            }
            let candidate = capturedWorkbenchCandidateText()
            let diagnostics = await Task.detached(priority: .userInitiated) {
                DanmakuWorkbenchDiagnosticsBuilder.build(
                    platformName: platformName,
                    payloads: payloads,
                    candidate: candidate
                )
            }.value
            copyToPasteboard(diagnostics)
            isCopyingWorkbenchDiagnostics = false
            statusText = "已复制\(platformName)捕获诊断，内容已脱敏并限制大小。"
            statusLevel = .success
        }
    }

    func collectCookies(trigger: String) {
        guard !isCollecting else { return }
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
        case .wechat:
            if await waitForWechatWorkbenchMessageCapture() {
                await runWechatWorkbenchCaptureDanmu()
            } else {
                appendDanmuMessage(.system("未捕获到视频号工作台评论接口，改用 sessionid/wxuin native 请求链路。"))
                await runNativeDanmu(adapter: adapter, cookieHeader: cookieHeader)
            }
        case .xiaohongshu:
            await runNativeDanmu(adapter: adapter, cookieHeader: cookieHeader)
        case .taobao, .kuaishou, .shopee, .douyin, .tiktok:
            await runNativeDanmu(adapter: adapter, cookieHeader: cookieHeader)
        }
    }

    private func appendDanmuMessage(_ message: DanmakuTestMessage) {
        danmuMessages = Array((danmuMessages + [message]).suffix(120))
    }

    private func waitForWechatWorkbenchMessageCapture() async -> Bool {
        for _ in 0..<24 {
            if capturedWorkbenchPayloads.contains(where: wechatPayloadContainsMessages(_:)) {
                return true
            }
            try? await Task.sleep(nanoseconds: 125_000_000)
        }
        return false
    }

    private func xiaohongshuPageSnapshotText() async -> String? {
        await evaluateXiaohongshuJavaScript(
            #"""
            (() => {
              const bodyText = String(document.body && document.body.innerText || '').trim();
              const liveTerms = ['评论', '观众', '直播画面', '场观', '开播', '直播数据', '互动', '商品', '结束直播', '直播状态'];
              const visible = element => {
                const rect = element.getBoundingClientRect();
                const style = getComputedStyle(element);
                return rect.width > 80 && rect.height > 80 && style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > 0;
              };
              const iframes = Array.from(document.querySelectorAll('iframe'));
              const resources = performance.getEntriesByType('resource')
                .map(entry => String(entry.name || ''))
                .filter(url => /live|comment|message|room|ark|xiaohongshu|zelda/i.test(url))
                .slice(-80);
              return JSON.stringify({
                href: location.href,
                title: document.title,
                readyState: document.readyState,
                bodyTextLength: bodyText.length,
                bodyText: bodyText.slice(0, 6000),
                liveTermCount: liveTerms.filter(term => bodyText.includes(term)).length,
                iframeCount: iframes.length,
                visibleIframeCount: iframes.filter(visible).length,
                elementCount: document.querySelectorAll('*').length,
                resources
              });
            })()
            """#
        )
    }

    private func evaluateXiaohongshuJavaScript(_ script: String) async -> String? {
        guard let webView else { return nil }
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { result, _ in
                if let result = result as? String {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func runWechatWorkbenchCaptureDanmu() async {
        danmuStatus = .open
        danmuStatusText = "视频号 native adapter 已连接工作台捕获流。"
        danmuStatusLevel = .success
        appendDanmuMessage(.system("已使用视频号工作台捕获到的直播接口响应连接弹幕。"))

        var processedPayloads = Set<String>()
        while !Task.isCancelled {
            let payloads = capturedWorkbenchPayloads
            var emitted = 0
            for payload in payloads {
                let signature = NativeDanmakuHTTP.sha1Hex(payload)
                guard !processedPayloads.contains(signature) else { continue }
                processedPayloads.insert(signature)
                let events = wechatEvents(fromWorkbenchPayload: payload)
                for event in events {
                    handleNativeDanmuEvent(event, adapter: .wechat)
                    emitted += 1
                }
            }

            if emitted == 0, processedPayloads.isEmpty {
                danmuStatusText = "视频号 native adapter 已连接，等待工作台评论接口刷新。"
                danmuStatusLevel = .info
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func runNativeDanmu(adapter: DanmakuDirectAdapterKind, cookieHeader: String) async {
        do {
            let adapterPlatformKey = nativePlatformKey(for: adapter)
            guard let nativeAdapter = NativeDanmakuAdapterFactory().adapter(for: adapterPlatformKey) else {
                throw NativeDanmakuAdapterError.unsupportedPlatform(adapter.displayName)
            }
            let input = await nativeRoomInput(adapter: adapter)
            let requestPlatformKey = adapter == .douyin ? selectedPlatform.key : adapterPlatformKey
            let liveSession = nativeLiveSessionPayload(adapter: adapter, cookieHeader: cookieHeader)
            let request = NativeDanmakuConnectRequest(
                platformKey: requestPlatformKey,
                roomId: nil,
                roomNumber: input.isEmpty ? nil : input,
                eid: nil,
                liveType: nil,
                liveSession: liveSession,
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

    private func nativeLiveSessionPayload(adapter: DanmakuDirectAdapterKind, cookieHeader: String) -> String {
        if adapter == .xiaohongshu {
            let object: [String: Any] = [
                "version": 1,
                "platform": selectedPlatform.key,
                "cookieHeader": cookieHeader
            ]
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object),
                  let text = String(data: data, encoding: .utf8) else {
                return cookieHeader
            }
            return text
        }

        guard adapter == .douyin, selectedPlatform.key == "dy_web" else {
            return cookieHeader
        }

        let payloads = capturedWorkbenchPayloads
            .suffix(40)
            .filter { shouldIncludeDouyinWebPayloadInNativeSession($0) }
            .map { String($0.prefix(20_000)) }
        var object: [String: Any] = [
            "version": 1,
            "platform": selectedPlatform.key,
            "cookieHeader": cookieHeader,
            "currentURL": currentURLText,
            "capturedPayloads": Array(payloads)
        ]
        if let capturedDouyinRoomInput,
           !isDouyinPublicRoomIdCandidate(capturedDouyinRoomInput) {
            object["capturedDouyinRoomInput"] = capturedDouyinRoomInput
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return cookieHeader
        }
        return text
    }

    private func nativeRoomInput(adapter: DanmakuDirectAdapterKind) async -> String {
        let input = liveRoomInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.isEmpty else { return input }
        if adapter == .wechat {
            if let finderUsername = wechatFinderUsernameCandidate(from: capturedWorkbenchPayloads.joined(separator: "\n")) {
                appendDanmuMessage(.system("已从视频号首页 auth_data 解析到 finderUsername，将用于 native 请求链路。"))
                return finderUsername
            }
            return ""
        }
        if adapter == .xiaohongshu {
            appendDanmuMessage(.system("将仅使用已采集的千帆 Cookie 查询当前直播并连接平台长链，无需打开直播中控页面。"))
            return ""
        }
        if adapter == .taobao {
            appendDanmuMessage(.system("将仅使用已采集的千牛 Cookie 查询当前直播并连接 impaas 评论源，无需打开直播管理页面。"))
            return ""
        }
        guard adapter == .douyin else { return input }

        if selectedPlatform.key == "dy_web" {
            appendDanmuMessage(.system("抖音网页版将仅使用 Cookie 自动解析当前登录账号正在直播的房间，并连接 Webcast WSS。"))
            return ""
        }

        appendDanmuMessage(.system("抖音将直接使用 Cookie 请求抖店工作台评论接口，不再把页面捕获到的 liveId 当 roomId 直连 WSS。"))
        return ""
    }

    private func taobaoRoomInputCandidate(from text: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
        if let roomId = NativeDanmakuHTTP.firstRegexMatch(
            in: decoded,
            pattern: #"(?:https?:)?//(?:impaas|impaasgw)\.alicdn\.com/live/message/([A-Za-z0-9_\-]{6,80})/"#,
            options: [.caseInsensitive]
        ) {
            return roomId
        }
        if let roomId = NativeDanmakuHTTP.firstRegexMatch(
            in: decoded,
            pattern: #"/live/message/([A-Za-z0-9_\-]{6,80})/"#,
            options: [.caseInsensitive]
        ) {
            return roomId
        }
        let keys = ["wh_cid", "roomId", "room_id", "liveId", "live_id", "liveRoomId", "liveRoomID", "livingRoomId", "liveIdStr"]
        for key in keys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key),
               isTaobaoRoomIdCandidate(value) {
                return value
            }
        }
        let keyPattern = ##"["']?(?:wh_cid|roomId|room_id|liveId|live_id|liveRoomId|liveRoomID|livingRoomId|liveIdStr)["']?\s*[:=]\s*["']?([A-Za-z0-9_\-]{6,80})"##
        if let value = NativeDanmakuHTTP.firstRegexMatch(in: decoded, pattern: keyPattern, options: [.caseInsensitive]),
           isTaobaoRoomIdCandidate(value) {
            return value
        }
        return nil
    }

    private func isTaobaoRoomIdCandidate(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_\-]{6,80}$"#, options: .regularExpression) != nil
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
            if let roomId = douyinJSONCandidate(in: object, path: [], mode: .room),
               isDouyinPublicRoomIdCandidate(roomId) {
                return roomId
            }
        }

        let roomKeys = [
            "room_id", "roomId", "webcast_room_id", "webcastRoomId",
            "room_id_str", "roomIdStr", "webcast_room_id_str", "webcastRoomIdStr",
            "live_room_id", "liveRoomId", "live_room_id_str", "liveRoomIdStr",
            "current_room_id", "currentRoomId", "ecom_live_room_id", "ecomLiveRoomId",
            "im_room_id", "imRoomId", "roomID", "RoomId", "roomid", "roomidstr",
            "webcastRoomID", "webcast_roomid", "liveRoomID", "live_roomid",
            "wss_push_room_id", "wssPushRoomId", "push_room_id", "pushRoomId"
        ]
        for key in roomKeys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key),
               isDouyinPublicRoomIdCandidate(value) {
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
            #"(?i)(?:wss_push_room_id|push_room_id|room_id|webcast_room_id|live_room_id|ecom_live_room_id|current_room_id)\s*[:=]\s*["']?(\d{5,30})"#,
            #"(?i)(?:room|webcast|live)[A-Za-z0-9_\-]{0,48}(?:id|ID|Id)["']?\s*[:=]\s*["']?(\d{5,30})"#
        ]
        for pattern in roomPatterns {
            if let value = firstDouyinRegexValue(in: decoded, pattern: pattern),
               isDouyinPublicRoomIdCandidate(value) {
                return value
            }
        }

        if let livePageId = NativeDanmakuHTTP.firstRegexMatch(
            in: decoded,
            pattern: #"live\.douyin\.com/([A-Za-z0-9_\-]{4,80})"#
        ), isDouyinLiveIdCandidate(livePageId) {
            return livePageId
        }

        let liveKeys = [
            "live_id", "liveId", "live_id_str", "liveIdStr",
            "webcastLiveId", "webcast_live_id", "webcastLiveIdStr", "webcast_live_id_str",
            "anchorLiveId", "anchor_live_id", "authorLiveId", "author_live_id",
            "douyinId"
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

    private func shouldUseDouyinWebCapturedPayloadForRoomInput(_ text: String) -> Bool {
        let decoded = normalizedDouyinWebCaptureText(text)
        if isDouyinWebUnrelatedFeedPayload(decoded) {
            return false
        }
        if decoded.localizedCaseInsensitiveContains("live.douyin.com/") {
            return true
        }
        return decoded.localizedCaseInsensitiveContains("/aweme/v1/web/user/profile/self/")
            || decoded.localizedCaseInsensitiveContains("/aweme/v1/web/aweme/post/")
            || decoded.localizedCaseInsensitiveContains("/aweme/v1/web/social/count")
            || decoded.localizedCaseInsensitiveContains("/aweme/v1/web/user/profile/other/")
            || decoded.localizedCaseInsensitiveContains("www.douyin.com/user/self")
            || decoded.localizedCaseInsensitiveContains("\"unique_id\"")
            || decoded.localizedCaseInsensitiveContains("\"room_id\"")
    }

    private func shouldIncludeDouyinWebPayloadInNativeSession(_ text: String) -> Bool {
        let decoded = normalizedDouyinWebCaptureText(text)
        guard !isDouyinWebUnrelatedFeedPayload(decoded) else { return false }
        if decoded.localizedCaseInsensitiveContains("/webcast/im/push/preview/") {
            return decoded.localizedCaseInsensitiveContains("live.douyin.com/")
                && !decoded.localizedCaseInsensitiveContains("www.douyin.com/friend")
        }
        return shouldUseDouyinWebCapturedPayloadForRoomInput(decoded)
    }

    private func normalizedDouyinWebCaptureText(_ text: String) -> String {
        NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
    }

    private func isDouyinWebUnrelatedFeedPayload(_ decoded: String) -> Bool {
        if decoded.localizedCaseInsensitiveContains("www.douyin.com/friend") {
            return true
        }
        if decoded.localizedCaseInsensitiveContains("/aweme/v1/web/familiar/feed/") {
            return true
        }
        if decoded.localizedCaseInsensitiveContains("cell_room")
            && decoded.localizedCaseInsensitiveContains("\"rawdata\"") {
            return true
        }
        return false
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
            "webcastRoomID", "webcast_roomid", "liveRoomID", "live_roomid",
            "wss_push_room_id", "wssPushRoomId", "push_room_id", "pushRoomId"
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
            #"(?i)(?:wss_push_room_id|push_room_id|room_id|webcast_room_id|live_room_id|ecom_live_room_id|current_room_id)\s*[:=]\s*["']?(\d{5,30})"#,
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

    private func xiaohongshuEvents(fromWorkbenchPayload payload: String) -> [NativeDanmakuEvent] {
        var events: [NativeDanmakuEvent] = []
        var eventIds = Set<String>()
        for decoded in xiaohongshuCaptureTextCandidates(from: payload) {
            for jsonText in possibleJSONTexts(from: decoded) {
                guard let data = jsonText.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) else { continue }
                for message in xiaohongshuMessageObjects(in: object) {
                    guard let event = decodeXiaohongshuWorkbenchMessage(message) else { continue }
                    guard !eventIds.contains(event.eventId) else { continue }
                    eventIds.insert(event.eventId)
                    events.append(event)
                }
            }
        }
        return events
    }

    private func xiaohongshuCaptureTextCandidates(from payload: String) -> [String] {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(payload)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
        var results = [decoded]
        let encodedFrames = NativeDanmakuHTTP.allRegexMatches(
            in: decoded,
            pattern: #"__base64__:([A-Za-z0-9+/_=-]{8,})"#
        )
        for encodedFrame in encodedFrames {
            var normalized = encodedFrame
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            normalized = NativeDanmakuHTTP.paddedBase64(normalized)
            guard var data = Data(base64Encoded: normalized) else { continue }
            if NativeDanmakuHTTP.isGzipPayload(data),
               let inflated = try? NativeDanmakuHTTP.gunzip(data) {
                data = inflated
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { continue }
            results.append(text)
        }
        return Array(Set(results))
    }

    private func xiaohongshuMessageObjects(in value: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 9 else { return [] }
        if let dictionary = value as? [String: Any] {
            var messages: [[String: Any]] = []
            if xiaohongshuDictionaryLooksLikeComment(dictionary) {
                messages.append(dictionary)
            }

            for key in ["customData", "custom_data", "respJsonStr", "resp_json_str", "payload", "body", "d"] {
                guard let text = dictionary[key] as? String,
                      let nested = xiaohongshuNestedObject(from: text, allowBase64: key == "d") else { continue }
                messages.append(contentsOf: xiaohongshuMessageObjects(in: nested, depth: depth + 1))
            }

            for key in [
                "comments", "commentList", "comment_list", "messageList", "message_list",
                "msgList", "msg_list", "items", "list", "rows", "records", "messages",
                "data", "result", "payload", "body", "b", "d"
            ] {
                if let nested = dictionary[key] {
                    messages.append(contentsOf: xiaohongshuMessageObjects(in: nested, depth: depth + 1))
                }
            }
            return messages
        }
        if let array = value as? [Any] {
            return array.flatMap { xiaohongshuMessageObjects(in: $0, depth: depth + 1) }
        }
        return []
    }

    private func xiaohongshuNestedObject(from text: String, allowBase64: Bool) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            return object
        }
        if allowBase64,
           let data = Data(base64Encoded: NativeDanmakuHTTP.paddedBase64(trimmed)),
           let object = try? JSONSerialization.jsonObject(with: data) {
            return object
        }
        return nil
    }

    private func xiaohongshuDictionaryLooksLikeComment(_ dictionary: [String: Any]) -> Bool {
        guard !firstXiaohongshuContent(dictionary).isEmpty else { return false }
        if !firstXiaohongshuText(dictionary, keys: ["commentId", "comment_id", "msg_id", "msgId", "messageId", "message_id"]).isEmpty {
            return true
        }
        if dictionary["profile"] is [String: Any] || dictionary["user"] is [String: Any] || dictionary["sender"] is [String: Any] {
            return true
        }
        let type = firstXiaohongshuText(dictionary, keys: ["type", "msgType", "msg_type", "messageType", "message_type"]).lowercased()
        if ["text", "comment", "chat", "1"].contains(type) {
            return true
        }
        return dictionary.keys.contains { key in
            let normalized = normalizePlatformFieldKey(key)
            return normalized.contains("comment") || normalized.contains("nickname")
        }
    }

    private func decodeXiaohongshuWorkbenchMessage(_ member: [String: Any]) -> NativeDanmakuEvent? {
        let content = firstXiaohongshuContent(member).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, xiaohongshuDictionaryLooksLikeComment(member) else { return nil }

        let profile = firstXiaohongshuDictionary(member, keys: ["profile", "user", "sender", "author"])
        let rawMessageId = firstXiaohongshuText(
            member,
            keys: ["msg_id", "msgId", "commentId", "comment_id", "messageId", "message_id", "id", "seq"]
        )
        let directUserId = firstXiaohongshuText(member, keys: ["user_id", "userId", "userID", "openId", "openid"])
        let profileUserId = firstXiaohongshuText(profile, keys: ["user_id", "userId", "id", "openId", "openid"])
        let userId = directUserId.isEmpty ? profileUserId : directUserId
        let directUserName = firstXiaohongshuText(member, keys: ["nickname", "nickName", "nick_name", "userName", "name"])
        let profileUserName = firstXiaohongshuText(profile, keys: ["nickname", "nickName", "nick_name", "userName", "name"])
        let userName = directUserName.isEmpty ? profileUserName : directUserName
        let roomId = firstXiaohongshuText(
            member,
            keys: ["room_id", "roomId", "xhsRoomId", "liveId", "live_id", "liveRoomId", "live_room_id"]
        )
        let resolvedRoomId = roomId.isEmpty ? capturedXiaohongshuRoomInput : roomId

        let messageId = rawMessageId.isEmpty
            ? NativeDanmakuHTTP.sha1Hex("xhs|\(resolvedRoomId ?? "")|\(userId)|\(userName)|\(content)")
            : rawMessageId
        let fansGroup = firstXiaohongshuDictionary(profile, keys: ["fans_group", "fansGroup"])
        let fansStatus = fansGroup.isEmpty
            ? "0"
            : NativeDanmakuHTTP.boolValue(fansGroup["active_fans"] ?? fansGroup["activeFans"]) ? "1" : "2"
        let rawPayload: [String: Any] = [
            "xhsMsgId": rawMessageId,
            "msgId": messageId,
            "danmuUserId": userId,
            "danmuUserName": userName.isEmpty ? "小红书用户" : userName,
            "danmuContent": content,
            "xhsRoomId": resolvedRoomId ?? "",
            "orderNumber": "",
            "blackLevel": "0",
            "fansStatus": fansStatus,
            "createdUsers": []
        ]

        return NativeDanmakuEvent(
            eventId: messageId,
            platform: "xiaohongshu",
            event: .chat,
            status: nil,
            roomId: nil,
            platformRoomId: resolvedRoomId,
            messageId: messageId,
            userId: userId,
            userName: userName.isEmpty ? "小红书用户" : userName,
            content: content,
            rawPayload: rawPayload
        )
    }

    private func firstXiaohongshuContent(_ object: [String: Any]) -> String {
        let strong = firstXiaohongshuText(
            object,
            keys: ["desc", "content", "text", "commentContent", "comment_content", "msgContent", "msg_content"]
        )
        if !strong.isEmpty { return strong }
        guard object["profile"] is [String: Any]
                || object["user"] is [String: Any]
                || !firstXiaohongshuText(object, keys: ["commentId", "comment_id", "msg_id", "msgId"]).isEmpty else {
            return ""
        }
        return firstXiaohongshuText(object, keys: ["message", "msg"])
    }

    private func firstXiaohongshuText(_ object: [String: Any], keys: [String]) -> String {
        for key in keys {
            guard let value = object[key], !(value is NSNull) else { continue }
            if let string = value as? String {
                let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return ""
    }

    private func firstXiaohongshuDictionary(_ object: [String: Any], keys: [String]) -> [String: Any] {
        for key in keys {
            if let dictionary = object[key] as? [String: Any] {
                return dictionary
            }
        }
        return [:]
    }

    private func wechatEvents(fromWorkbenchPayload payload: String) -> [NativeDanmakuEvent] {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(payload)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")

        var events: [NativeDanmakuEvent] = []
        var eventIds = Set<String>()
        for jsonText in possibleJSONTexts(from: decoded) {
            guard let data = jsonText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            for message in wechatMessageObjects(in: object) {
                guard let event = decodeWechatWorkbenchMessage(message) else { continue }
                guard !eventIds.contains(event.eventId) else { continue }
                eventIds.insert(event.eventId)
                events.append(event)
            }
        }
        return events
    }

    private func wechatMessageObjects(in value: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 8 else { return [] }
        if let dictionary = value as? [String: Any] {
            var messages: [[String: Any]] = []
            for key in ["msgList", "msg_list"] {
                if let list = dictionary[key] as? [[String: Any]] {
                    messages.append(contentsOf: list)
                }
            }
            for key in ["respJsonStr", "resp_json_str"] {
                if let text = dictionary[key] as? String,
                   let data = text.data(using: .utf8),
                   let inner = try? JSONSerialization.jsonObject(with: data) {
                    messages.append(contentsOf: wechatMessageObjects(in: inner, depth: depth + 1))
                }
            }
            for nestedKey in ["data", "payload", "result"] {
                if let nested = dictionary[nestedKey] {
                    messages.append(contentsOf: wechatMessageObjects(in: nested, depth: depth + 1))
                }
            }
            return messages
        }
        if let array = value as? [Any] {
            return array.flatMap { wechatMessageObjects(in: $0, depth: depth + 1) }
        }
        return []
    }

    private func decodeWechatWorkbenchMessage(_ member: [String: Any]) -> NativeDanmakuEvent? {
        let type = NativeDanmakuHTTP.flexibleInt(member["type"])
            ?? NativeDanmakuHTTP.flexibleInt(member["msgType"])
            ?? NativeDanmakuHTTP.flexibleInt(member["msg_type"])
        guard type == nil || type == 1 else { return nil }

        let content = firstWechatText(member, keys: ["content", "text", "comment", "msgContent", "msg_content"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let rawMessageId = firstWechatText(member, keys: ["seq", "clientMsgId", "client_msg_id", "msgId", "msg_id", "id"])
        let nickname = firstWechatText(member, keys: ["nickname", "nickName", "userName", "senderNickName"])
        let username = firstWechatText(member, keys: ["username", "userId", "user_id", "openid", "openId"])
        let messageId = rawMessageId.isEmpty
            ? NativeDanmakuHTTP.sha1Hex("wechat|\(nickname)|\(username)|\(content)")
            : rawMessageId
        let userId = wechatDecodedOpenId(from: rawMessageId) ?? username
        let userName = nickname.isEmpty ? "视频号用户" : nickname

        return NativeDanmakuEvent(
            eventId: messageId,
            platform: "wechat",
            event: .chat,
            status: nil,
            roomId: nil,
            platformRoomId: firstWechatText(member, keys: ["liveId", "live_id"]),
            messageId: messageId,
            userId: userId,
            userName: userName,
            content: content,
            rawPayload: member
        )
    }

    private func firstWechatText(_ object: [String: Any], keys: [String]) -> String {
        for key in keys {
            guard let value = object[key], !(value is NSNull) else { continue }
            let text = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }
        return ""
    }

    private func wechatDecodedOpenId(from messageId: String) -> String? {
        guard let range = messageId.range(of: "_o9h") else { return nil }
        return String(messageId[messageId.index(after: range.lowerBound)...])
    }

    private func normalizePlatformFieldKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private func platformJSONStringValue(_ value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func firstRegexValue(in text: String, pattern: String) -> String? {
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
            "liveroomid", "liveroomidstr", "currentroomid", "ecomliveroomid", "imroomid",
            "wsspushroomid", "pushroomid"
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

    private func isDouyinPublicRoomIdCandidate(_ value: String) -> Bool {
        value.range(of: #"^\d{12,30}$"#, options: .regularExpression) != nil
    }

    private func isDouyinLiveIdCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let blockedLiterals = Set([
            "anchor", "author", "aweme", "comment", "douyin", "false", "home",
            "index", "live", "login", "main", "message", "post", "recommend",
            "room", "search", "self", "share", "static", "stream", "true",
            "undefined", "user", "video", "webcast"
        ])
        guard trimmed.range(of: #"^[A-Za-z0-9_\-]{4,80}$"#, options: .regularExpression) != nil else { return false }
        guard !blockedLiterals.contains(lowercased) else { return false }
        guard !isRejectedDouyinWebRid(lowercased) else { return false }
        guard !lowercased.contains(".js"), !lowercased.contains(".css") else { return false }
        return trimmed.range(of: #"\d"#, options: .regularExpression) != nil
    }

    private func isRejectedDouyinWebRid(_ lowercased: String) -> Bool {
        if lowercased.hasPrefix("stream-") || lowercased.hasPrefix("pull-") || lowercased.hasPrefix("push-") {
            return true
        }
        let blockedFragments = [
            "_flv", "flv_", ".flv", "_m3u8", ".m3u8",
            "_hd", "_sd", "_uhd", "stream-", "pull-flv", "pull-hls"
        ]
        return blockedFragments.contains { lowercased.contains($0) }
    }

    private func clearWorkbenchCaptures() {
        capturedWorkbenchPayloads = []
        capturedWorkbenchPayloadSignatures = []
        capturedDouyinRoomInput = nil
        capturedXiaohongshuRoomInput = nil
        capturedXiaohongshuRoomInputIsTrusted = false
        workbenchCaptureCount = 0
        isCopyingWorkbenchDiagnostics = false
    }

    private func handleNativeDanmuEvent(_ event: NativeDanmakuEvent, adapter: DanmakuDirectAdapterKind) {
        switch event.event {
        case .status:
            handleNativeStatus(event.status, adapter: adapter, content: event.content)
        case .chat:
            let messageId = event.messageId ?? event.eventId
            let userName = event.userName ?? "用户"
            let content = event.content ?? ""
            let rawText = DanmakuTestMessage.rawPayloadText(event.rawPayload)
            let userId = event.userId ?? ""
            guard !seenDanmuMessageIds.contains(messageId) else { return }
            seenDanmuMessageIds.insert(messageId)
            appendDanmuMessage(
                DanmakuTestMessage(
                    id: messageId,
                    messageId: messageId,
                    user: userName,
                    userId: userId,
                    content: content,
                    roomId: event.platformRoomId ?? event.roomId ?? "",
                    rawText: rawText
                )
            )
            danmuStatus = .open
            danmuStatusText = "\(adapter.displayName) native adapter 收到弹幕。"
            danmuStatusLevel = .success
        case .gift, .member, .like, .social, .control:
            let messageId = event.messageId ?? event.eventId
            guard !seenDanmuMessageIds.contains(messageId) else { return }
            seenDanmuMessageIds.insert(messageId)
            let content = event.content?.isEmpty == false
                ? event.content ?? ""
                : nativeEventLabel(event.event)
            appendDanmuMessage(
                DanmakuTestMessage(
                    id: messageId,
                    messageId: messageId,
                    user: event.userName ?? nativeEventLabel(event.event),
                    userId: event.userId ?? "",
                    content: content,
                    roomId: event.platformRoomId ?? event.roomId ?? "",
                    rawText: DanmakuTestMessage.rawPayloadText(event.rawPayload)
                )
            )
            danmuStatus = .open
            danmuStatusText = "\(adapter.displayName) native adapter 收到\(nativeEventLabel(event.event))。"
            danmuStatusLevel = .success
        case .error:
            danmuStatus = .error
            danmuStatusText = event.content ?? "\(adapter.displayName) native adapter 连接失败。"
            danmuStatusLevel = .error
            appendDanmuMessage(.system(danmuStatusText))
        }
    }

    private func nativeEventLabel(_ event: NativeDanmakuEventKind) -> String {
        switch event {
        case .status: return "状态"
        case .chat: return "弹幕"
        case .gift: return "礼物"
        case .member: return "进场"
        case .like: return "点赞"
        case .social: return "互动"
        case .control: return "控制"
        case .error: return "错误"
        }
    }

    private func handleNativeStatus(_ status: NativeDanmakuStatus?, adapter: DanmakuDirectAdapterKind, content: String? = nil) {
        let statusContent = content?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch status {
        case .connecting:
            danmuStatus = .connecting
            danmuStatusText = statusContent?.isEmpty == false ? statusContent ?? "" : "\(adapter.displayName) native adapter 正在连接平台弹幕。"
            danmuStatusLevel = .info
        case .living:
            danmuStatus = .open
            danmuStatusText = statusContent?.isEmpty == false ? statusContent ?? "" : "\(adapter.displayName) native adapter 已连上平台弹幕。"
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

private enum DanmakuWorkbenchDiagnosticsBuilder {
    static func build(platformName: String, payloads: [String], candidate: String?) -> String {
        let sampledPayloads = diagnosticSample(from: payloads).map { payload in
            payload.localizedCaseInsensitiveContains("websocket-")
                ? String(payload.prefix(24_000))
                : String(payload.prefix(10_000))
        }
        let sections = sampledPayloads.enumerated().map { index, payload in
            let masked = maskSensitiveText(payload)
            return """
            ## sample \(index + 1)
            \(diagnosticSnippet(from: masked))
            """
        }
        let output = """
        # \(platformName) Workbench Capture Diagnostic
        generated_at: \(ISO8601DateFormatter().string(from: Date()))
        captured_count: \(payloads.count)
        sampled_count: \(sampledPayloads.count)
        parsed_candidate: \(candidate ?? "nil")

        \(sections.joined(separator: "\n\n"))
        """
        return String(output.prefix(60_000))
    }

    private static func diagnosticSample(from payloads: [String]) -> [String] {
        var sampled: [String] = []
        var signatures = Set<String>()

        func add(_ payload: String) {
            let signature = String(payload.prefix(300))
            guard !signatures.contains(signature) else { return }
            signatures.insert(signature)
            sampled.append(payload)
        }

        let priorityPatterns = [
            "impaas.alicdn.com/live/message",
            "impaasgw.alicdn.com/live/message",
            "payloads",
            "dataSize",
            "pullInterval",
            "powermsg",
            "ws-msgacs.m.taobao.com",
            "qn-live-container",
            "taobao",
            "websocket-message-b64",
            "websocket-message",
            "live_center_control",
            "commentList",
            "comment_list",
            "customData",
            "xhsRoomId",
            "api/livepc/playinfo",
            "mmfinderassistant-bin/live/msg",
            "mmfinderassistant-bin/live/check_live_status",
            "msgList",
            "msg_list",
            "respJsonStr",
            "liveCookies",
            "finderUsername",
            "websocket-send-b64",
            "websocket-send",
            "frontier.snssdk.com",
            "__base64__",
            "\"room_id\"",
            "room_id"
        ]
        for pattern in priorityPatterns {
            for payload in payloads where payload.localizedCaseInsensitiveContains(pattern) {
                add(payload)
            }
        }
        for payload in payloads.suffix(12) {
            add(payload)
        }
        for pattern in ["ark.xiaohongshu.com", "xiaohongshu", "wechat", "douyin"] {
            for payload in payloads where payload.localizedCaseInsensitiveContains(pattern) {
                add(payload)
            }
        }
        return Array(sampled.prefix(16))
    }

    private static func maskSensitiveText(_ text: String) -> String {
        var output = text
        var base64Placeholders: [(String, String)] = []
        if let binaryRegex = try? NSRegularExpression(pattern: #"__base64__:[A-Za-z0-9+/=]{16,}"#) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            let matches = binaryRegex.matches(in: output, range: range).reversed()
            for (index, match) in matches.enumerated() {
                guard let matchRange = Range(match.range, in: output) else { continue }
                let value = String(output[matchRange])
                let marker = "__FAST_SORT_BINARY_FRAME_\(index)__"
                output.replaceSubrange(matchRange, with: marker)
                base64Placeholders.append((marker, value))
            }
        }

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
        for (marker, value) in base64Placeholders {
            output = output.replacingOccurrences(of: marker, with: value)
        }
        return output
    }

    private static func diagnosticSnippet(from text: String) -> String {
        if text.localizedCaseInsensitiveContains("websocket-") || text.contains("__base64__:") {
            return String(text.prefix(8_000))
        }

        let keywords = #"(?i)(room|webcast|live|anchor|douyin|wechat|weixin|channels|finder|msgList|respJsonStr|comment|message|chat|control|xiaohongshu|ark|xhs|customData|直播|中控|互动|视频号|小红书|评论)"#
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
            "\(text.count)",
            String(text.prefix(512)),
            String(text.suffix(512))
        ].joined(separator: "|")
    }
}

@MainActor
private final class DanmakuAuthWindowController: NSObject, NSWindowDelegate {
    private weak var viewModel: DanmakuCookieTestViewModel?
    private let onClose: () -> Void
    private var window: NSWindow?
    private var didClose = false

    var isClosed: Bool {
        didClose || window == nil
    }

    init(viewModel: DanmakuCookieTestViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
        super.init()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(viewModel.selectedPlatform.name) 登录窗口"
        window.minSize = NSSize(width: 900, height: 620)
        window.contentViewController = NSHostingController(
            rootView: DanmakuAuthStandaloneWindow(viewModel: viewModel)
        )
        window.delegate = self
        window.center()
        self.window = window
    }

    func show() {
        guard !isClosed else { return }
        if let viewModel {
            window?.title = "\(viewModel.selectedPlatform.name) 登录窗口"
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        onClose()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard !didClose else { return }
        didClose = true
        window?.delegate = nil
        window = nil
        DispatchQueue.main.async { [onClose] in
            onClose()
        }
    }
}

private struct DanmakuAuthStandaloneWindow: View {
    @ObservedObject var viewModel: DanmakuCookieTestViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.selectedPlatform.name) 登录窗口")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FastSortTheme.text)
                    Text(viewModel.currentURLText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(FastSortTheme.muted)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer()
                standaloneMatchBadge
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
        .frame(minWidth: 900, minHeight: 620)
        .background(FastSortTheme.background)
    }

    private var standaloneMatchBadge: some View {
        Label(viewModel.matchText, systemImage: viewModel.isPageMatched ? "checkmark.seal.fill" : "hourglass")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(viewModel.isPageMatched ? FastSortTheme.success : FastSortTheme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(viewModel.isPageMatched ? Color(hex: 0xe9f8ef) : FastSortTheme.surface)
            .clipShape(Capsule())
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
          const keywordPattern = /jinritemai|douyin|bytedance|webcast|room|live|anchor|comment|message|chat|control|taobao|tmall|alicdn|impaas|qn-live|qianniu|alimama|alibaba|channels\.weixin|mmfinderassistant|finder|msgList|msg_list|respJsonStr|liveCookies|weixin|wechat|xiaohongshu|ark|xhs|app-system|commentList|comment_list|customData|淘宝|千牛|视频号|小红书|评论|互动|直播|中控/i;
          const text = value => {
            if (value === undefined || value === null) return "";
            if (typeof value === "string") return value;
            if (value instanceof ArrayBuffer) return "";
            try { return JSON.stringify(value); } catch (_) { return String(value); }
          };
          const arrayBufferToBase64 = buffer => {
            try {
              const bytes = new Uint8Array(buffer);
              const size = Math.min(bytes.byteLength, 42000);
              let binary = "";
              for (let i = 0; i < size; i += 1) binary += String.fromCharCode(bytes[i]);
              return btoa(binary);
            } catch (_) {
              return "";
            }
          };
          const blobToBase64 = blob => new Promise(resolve => {
            try {
              if (blob && typeof blob.arrayBuffer === "function") {
                blob.arrayBuffer()
                  .then(buffer => resolve(arrayBufferToBase64(buffer)))
                  .catch(() => resolve(""));
                return;
              }
              const reader = new FileReader();
              reader.onloadend = () => {
                const result = String(reader.result || "");
                const comma = result.indexOf(",");
                resolve(comma >= 0 ? result.slice(comma + 1) : result);
              };
              reader.onerror = () => resolve("");
              reader.readAsDataURL(blob);
            } catch (_) {
              resolve("");
            }
          });
          const binaryValueToBase64 = value => {
            try {
              if (value instanceof ArrayBuffer) return arrayBufferToBase64(value);
              if (ArrayBuffer.isView(value)) {
                const view = value;
                return arrayBufferToBase64(view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength));
              }
            } catch (_) {}
            return "";
          };
          const postBinary = (kind, url, value) => {
            try {
              if (typeof value === "string") {
                post(kind, url, 0, value);
                return;
              }
              const base64 = binaryValueToBase64(value);
              if (base64) {
                post(`${kind}-b64`, url, 0, "__base64__:" + base64);
                return;
              }
              if (value && (typeof Blob !== "undefined") && value instanceof Blob) {
                blobToBase64(value).then(encoded => {
                  if (encoded) post(`${kind}-b64`, url, 0, "__base64__:" + encoded);
                });
              }
            } catch (_) {}
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
            const nativeSocketSend = NativeWebSocket.prototype && NativeWebSocket.prototype.send;
            if (typeof nativeSocketSend === "function" && !NativeWebSocket.prototype.__fastSortSendCaptured) {
              try {
                Object.defineProperty(NativeWebSocket.prototype, "__fastSortSendCaptured", { value: true });
                NativeWebSocket.prototype.send = function(data) {
                  try {
                    postBinary("websocket-send", this.__fastSortDanmakuURL || "", data);
                  } catch (_) {}
                  return nativeSocketSend.apply(this, arguments);
                };
              } catch (_) {}
            }
            const FastSortWebSocket = function(url, protocols) {
              post("websocket-open", url, 0, String(url || ""));
              const socket = protocols === undefined ? new NativeWebSocket(url) : new NativeWebSocket(url, protocols);
              try { socket.__fastSortDanmakuURL = String(url || ""); } catch (_) {}
              try {
                if (/frontier\.snssdk\.com|X-Ecom-Platform-Source=fxg/i.test(String(url || ""))) {
                  socket.binaryType = "arraybuffer";
                }
              } catch (_) {}
              try { post("websocket-binary-type", url, 0, String(socket.binaryType || "")); } catch (_) {}
              try {
                socket.addEventListener("message", event => {
                  postBinary("websocket-message", url, event.data);
                });
                socket.addEventListener("close", event => {
                  post("websocket-close", url, Number(event.code || 0), String(event.reason || ""));
                });
                socket.addEventListener("error", () => {
                  post("websocket-error", url, 0, String(url || ""));
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
    let userId: String
    let content: String
    let roomId: String
    let rawText: String
    let createdAt: Date

    var subtitleId: String {
        userId.isEmpty ? roomId : userId
    }

    var timeText: String {
        createdAt.formatted(date: .omitted, time: .standard)
    }

    init(id: String, messageId: String, user: String, userId: String = "", content: String, roomId: String, rawText: String = "", createdAt: Date = Date()) {
        self.id = id
        self.messageId = messageId
        self.user = user
        self.userId = userId
        self.content = content
        self.roomId = roomId
        self.rawText = rawText
        self.createdAt = createdAt
    }

    func updating(userId: String? = nil, rawText: String? = nil) -> DanmakuTestMessage {
        DanmakuTestMessage(
            id: id,
            messageId: messageId,
            user: user,
            userId: userId ?? self.userId,
            content: content,
            roomId: roomId,
            rawText: rawText ?? self.rawText,
            createdAt: createdAt
        )
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
            userId: Self.firstText(payload, keys: ["danmuUserId", "userId", "uid", "publisherId"]),
            content: content,
            roomId: roomId.isEmpty ? platformKey : roomId,
            rawText: Self.rawPayloadText(payload)
        )
    }

    static func system(_ text: String) -> DanmakuTestMessage {
        DanmakuTestMessage(
            id: "system-\(Date().timeIntervalSince1970)-\(UUID().uuidString)",
            messageId: "",
            user: "系统",
            content: text,
            roomId: "",
            rawText: ""
        )
    }

    static func rawPayloadText(_ payload: [String: Any]) -> String {
        guard !payload.isEmpty else { return "" }
        let normalized = normalizeJSONValue(payload)
        guard JSONSerialization.isValidJSONObject(normalized),
              let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return String(describing: payload)
        }
        return String(text.prefix(80_000))
    }

    private static func normalizeJSONValue(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.mapValues { normalizeJSONValue($0) }
        case let array as [Any]:
            return array.map { normalizeJSONValue($0) }
        case let number as NSNumber:
            return number
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case _ as NSNull:
            return NSNull()
        default:
            return String(describing: value)
        }
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
