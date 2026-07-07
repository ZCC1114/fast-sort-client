import Foundation
import SwiftUI

struct LiveRoomsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pageActivation: PageActivationState
    let navigate: ((AppRoute) -> Void)?

    @State private var activeLiveType = "0"
    @State private var searchText = ""
    @State private var rooms: [RoomListItem] = []
    @State private var selectedRoom: RoomListItem?
    @State private var liveRecordId = ""
    @State private var sortBatchId = ""
    @State private var socketStatus = "idle"
    @State private var roomStatusText = "未连接"
    @State private var printMode = "manual"
    @State private var isLoadingRooms = false
    @State private var isStarting = false
    @State private var errorText = ""
    @State private var toastText = ""
    @State private var hasLoaded = false

    @State private var comments: [LiveDanmuComment] = []
    @State private var pendingComments: [LiveDanmuComment] = []
    @State private var seenMessageIds = Set<String>()
    @State private var socketSession: DanmakuWebSocketSession?
    @State private var nativeDanmakuConnection: (any NativeDanmakuConnection)?
    @State private var nativePreparedSession: NativeDanmakuPreparedSession?
    @State private var socketLoopTask: Task<Void, Never>?
    @State private var heartbeatTask: Task<Void, Never>?
    @State private var reconnectTask: Task<Void, Never>?
    @State private var reconnectCount = 0
    @State private var isManualSocketClose = false

    @State private var showSettingsDialog = false

    @State private var onlyPrintFans = false
    @State private var uniqueMode = false
    @State private var bidModeEnabled = false
    @State private var nineGridModeEnabled = false
    @State private var repeatFilterEnabled = false
    @State private var commentFontSize = 14.0
    @State private var timeInterval = 5
    @State private var remainingNumber = 2
    @State private var repeatFilterSeconds = 5
    @State private var bidWaitSeconds = 5
    @State private var nineGridWindowSeconds = 30
    @State private var autoQueueCount = 0
    @State private var lastUniqueKey = ""
    @State private var hasRoomTemplate = false
    @State private var configRuleList: [TemplateRuleGroup] = []
    @State private var mappingRules: [DanmuMappingRule] = []
    @State private var printTagWidth = 40
    @State private var printTagHeight = 20
    @State private var connectedPrinterName = ""

    private let platforms = PlatformCatalog.all

    init(navigate: ((AppRoute) -> Void)? = nil) {
        self.navigate = navigate
    }

    private var filteredRooms: [RoomListItem] {
        rooms.filter { room in
            let sameType = (room.liveType?.value ?? "0") == activeLiveType
            guard sameType else { return false }
            let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return true }
            return room.displayName.localizedCaseInsensitiveContains(needle)
                || room.handle.localizedCaseInsensitiveContains(needle)
                || (room.roomNumber ?? "").localizedCaseInsensitiveContains(needle)
        }
    }

    private var activePlatformLabel: String {
        PlatformCatalog.label(for: selectedRoom?.liveType?.value ?? activeLiveType)
    }

    private var isSocketOpen: Bool {
        socketStatus == "open"
    }

    private var isPrinterConnected: Bool {
        !connectedPrinterName.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                HStack(alignment: .top, spacing: 18) {
                    roomList
                        .frame(width: 300)
                    livePanel
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.top, 20)
                .macPagePadding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if !toastText.isEmpty {
                Text(toastText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.72))
                    .clipShape(Capsule())
                    .padding(.bottom, 18)
            }
        }
        .sheet(isPresented: $showSettingsDialog) {
            settingsDialog
        }
        .task(id: pageActivation.isActive) {
            guard pageActivation.isActive, !hasLoaded else { return }
            guard await pageActivation.waitForFirstInteractiveFrame() else { return }
            await loadRooms(force: true)
        }
        .onChange(of: pageActivation.isActive) { _, isActive in
            guard isActive else { return }
            flushPendingComments()
        }
        .onDisappear {
            closeSocket(clearLiveState: false)
        }
    }

    private var roomList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("直播间列表")
                    .font(.system(size: 18, weight: .semibold))
                Text("(\(filteredRooms.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FastSortTheme.muted)
                Spacer()
                Button {
                    navigate?(.danmakuCookieTest)
                } label: {
                    Label("添加直播间", systemImage: "plus")
                }
                .buttonStyle(AccentOutlineButtonStyle())
            }

            platformTabs

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FastSortTheme.muted)
                TextField("按昵称/编号搜索", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(FastSortTheme.background)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(FastSortTheme.border)
            }

            if isLoadingRooms {
                ProgressView("加载直播间")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if filteredRooms.isEmpty {
                EmptyPanel(text: "暂无直播间")
                    .frame(minHeight: 120)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filteredRooms) { room in
                            roomRow(room)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 360)
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 13))
                    .foregroundStyle(FastSortTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .webCard()
    }

    private var platformTabs: some View {
        MacChoiceGroup("", selection: Binding(
            get: { activeLiveType },
            set: { next in setLiveType(next) }
        ), options: platforms.map { MacChoiceOption(label: $0.label, value: $0.liveType) }, minItemWidth: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func roomRow(_ room: RoomListItem) -> some View {
        let isActive = selectedRoom?.id == room.id
        return Button {
            selectRoom(room)
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    roomAvatar(room)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(room.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FastSortTheme.text)
                            .lineLimit(1)
                        Text(room.handle.isEmpty ? PlatformCatalog.label(for: room.liveType?.value ?? "0") : room.handle)
                            .font(.system(size: 12))
                            .foregroundStyle(FastSortTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)

                Image(systemName: isActive && !liveRecordId.isEmpty ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(FastSortTheme.accent)
                    .clipShape(Circle())
                    .shadow(color: FastSortTheme.accentShadow, radius: 6, x: 0, y: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(isActive ? FastSortTheme.accentSoft : FastSortTheme.background)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isActive ? FastSortTheme.accent.opacity(0.35) : FastSortTheme.border.opacity(0.55))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isStarting)
        .contextMenu {
            Button("删除直播间", role: .destructive) {
                Task { await deleteRoom(room) }
            }
        }
    }

    private func roomAvatar(_ room: RoomListItem) -> some View {
        ZStack {
            if let url = room.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        platformAvatarFallback(room.liveType?.value ?? "0")
                    }
                }
            } else {
                platformAvatarFallback(room.liveType?.value ?? "0")
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func platformAvatarFallback(_ liveType: String) -> some View {
        Text(String(PlatformCatalog.label(for: liveType).prefix(1)))
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(FastSortTheme.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FastSortTheme.accentSoft)
    }

    private var livePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    liveInfoCard
                    printerCard
                }
                VStack(spacing: 16) {
                    liveInfoCard
                    printerCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if printMode == "auto" {
                autoSummaryCard
            }

            commentsCard
        }
    }

    private var liveInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("当前直播间", systemImage: "video.fill")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                statusPill(socketStatusLabel, color: socketStatusColor)
            }

            infoRow(title: "平台", value: activePlatformLabel)
            infoRow(title: "直播间", value: selectedRoom?.displayName ?? "请选择直播间")
            infoRow(title: "房间号", value: selectedRoom?.roomNumber ?? "-")
            infoRow(title: "连接状态", value: roomStatusText)

            HStack {
                Text("打印模式")
                    .font(.system(size: 14))
                    .foregroundStyle(FastSortTheme.muted)
                Spacer()
                MacChoiceGroup("", selection: $printMode, options: [
                    MacChoiceOption(label: "手动", value: "manual"),
                    MacChoiceOption(label: "自动", value: "auto")
                ], minItemWidth: 76)
                .frame(width: 170)
                .onChange(of: printMode) { _, newValue in
                    applyPrintMode(newValue)
                }
            }

            HStack(spacing: 10) {
                Button(liveRecordId.isEmpty ? "开始直播" : "结束直播") {
                    Task {
                        if liveRecordId.isEmpty {
                            if let selectedRoom {
                                await startLive(room: selectedRoom)
                            }
                        } else {
                            await finishLive()
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedRoom == nil || isStarting)

                Button("刷新房间") {
                    Task { await loadRooms(force: true) }
                }
                .buttonStyle(AccentOutlineButtonStyle())

                Button("重连弹幕") {
                    refreshSocket()
                }
                .buttonStyle(AccentOutlineButtonStyle())
                .disabled(selectedRoom == nil || liveRecordId.isEmpty || socketStatus == "connecting")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .webCard()
    }

    private var printerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("打印机", systemImage: "printer.fill")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                statusPill(isPrinterConnected ? "已连接" : "未连接", color: isPrinterConnected ? FastSortTheme.success : FastSortTheme.muted)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(isPrinterConnected ? connectedPrinterName : "未连接本地打印机")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FastSortTheme.text)
                Text("标签尺寸 \(printTagWidth) x \(printTagHeight) mm")
                    .font(.system(size: 12))
                    .foregroundStyle(FastSortTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(FastSortTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 8) {
                Button("搜索设备") {
                    connectedPrinterName = "本地打印机待选择"
                    showToast("本地打印设备枚举会接 macOS 打印模块")
                }
                .buttonStyle(AccentOutlineButtonStyle())
                Button("断开连接") {
                    connectedPrinterName = ""
                }
                .buttonStyle(AccentOutlineButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .webCard()
    }

    private var autoSummaryCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(autoModeTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FastSortTheme.accent)
                Text(autoModeHeadline)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(FastSortTheme.text)
                Text("队列 \(autoQueueCount) 条，重复过滤 \(repeatFilterEnabled ? "\(repeatFilterSeconds)s" : "关闭")")
                    .font(.system(size: 12))
                    .foregroundStyle(FastSortTheme.muted)
            }
            Spacer()
            metricBlock(label: "间隔", value: "\(timeInterval)s")
            metricBlock(label: "每轮数量", value: "\(remainingNumber)")
            metricBlock(label: bidModeEnabled ? "竞拍等待" : "九宫格", value: bidModeEnabled ? "\(bidWaitSeconds)s" : "\(nineGridWindowSeconds)s")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .webCard()
    }

    private var commentsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                statusPill(danmuStatusLabel, color: socketStatusColor)
                Spacer()
                switchChip("仅粉丝打印", isOn: $onlyPrintFans, disabled: printMode != "auto")
                switchChip("去重模式", isOn: $uniqueMode, disabled: printMode != "auto")
                switchChip("竞拍模式", isOn: $bidModeEnabled, disabled: printMode != "auto") { enabled in
                    if enabled { nineGridModeEnabled = false }
                }
                switchChip("九宫格模式", isOn: $nineGridModeEnabled, disabled: printMode != "auto") { enabled in
                    if enabled { bidModeEnabled = false }
                }
                Button {
                    showSettingsDialog = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(IconCircleButtonStyle())
                Button {
                    refreshSocket()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(IconCircleButtonStyle())
                Button {
                    closeSocket(clearLiveState: true)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(IconCircleButtonStyle(tint: FastSortTheme.danger))
            }
            .padding(18)
            .overlay(alignment: .bottom) {
                Rectangle().fill(FastSortTheme.border).frame(height: 1)
            }

            if printMode == "auto" && !isPrinterConnected {
                Text("未连接打印机，自动打印队列将暂停")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FastSortTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(FastSortTheme.accentSoft.opacity(0.65))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if comments.isEmpty {
                            EmptyPanel(text: liveRecordId.isEmpty ? "开始直播后显示实时弹幕" : "暂无弹幕")
                                .padding(20)
                        } else {
                            ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                                commentRow(comment, index: index)
                                    .id(comment.id)
                            }
                        }
                    }
                }
                .frame(minHeight: 420)
                .onChange(of: comments.count) { _, _ in
                    guard pageActivation.isActive else { return }
                    guard let last = comments.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .webCard()
    }

    private func commentRow(_ comment: LiveDanmuComment, index: Int) -> some View {
        Button {
            Task { await handleManualPrint(comment) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if !comment.orderNumber.isEmpty {
                            badge(comment.orderNumber, color: FastSortTheme.accent)
                        }
                        if comment.blackLevel > 0 {
                            badge("Lv\(comment.blackLevel)", color: FastSortTheme.danger)
                        }
                        if comment.fansStatus == "1" {
                            badge("粉丝", color: FastSortTheme.success)
                        }
                        Text("\(comment.user):")
                            .font(.system(size: commentFontSize, weight: .semibold))
                            .foregroundStyle(FastSortTheme.text)
                    }
                    Text(comment.content)
                        .font(.system(size: commentFontSize))
                        .foregroundStyle(FastSortTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                commentStatus(comment)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(commentBackground(comment, index: index))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var settingsDialog: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("弹幕设置")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button {
                    showSettingsDialog = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconCircleButtonStyle())
            }

            VStack(alignment: .leading, spacing: 16) {
                sliderRow("弹幕字号", value: $commentFontSize, range: 10...40, display: "\(Int(commentFontSize))")
                stepperRow("自动间隔", value: $timeInterval, range: 1...120, suffix: "秒")
                stepperRow("自动数量", value: $remainingNumber, range: 1...99, suffix: "条")
                Toggle("开启重复过滤", isOn: $repeatFilterEnabled)
                    .toggleStyle(.checkbox)
                stepperRow("重复过滤时间", value: $repeatFilterSeconds, range: 5...300, suffix: "秒")
                stepperRow("竞拍等待时间", value: $bidWaitSeconds, range: 5...300, suffix: "秒")
                stepperRow("九宫格时间范围", value: $nineGridWindowSeconds, range: 1...600, suffix: "秒")
            }
            .padding(18)
            .webCard(cornerRadius: 14)

            HStack {
                Spacer()
                Button("应用") {
                    showSettingsDialog = false
                    applyFrequencySettings()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(FastSortTheme.background)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(FastSortTheme.muted)
            Spacer()
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FastSortTheme.text)
                .lineLimit(1)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(FastSortTheme.text)
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(FastSortTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func metricBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(FastSortTheme.muted)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(FastSortTheme.text)
        }
        .frame(width: 110, alignment: .leading)
        .padding(12)
        .background(FastSortTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func switchChip(
        _ title: String,
        isOn: Binding<Bool>,
        disabled: Bool,
        onChange: ((Bool) -> Void)? = nil
    ) -> some View {
        Button {
            guard !disabled else { return }
            isOn.wrappedValue.toggle()
            onChange?(isOn.wrappedValue)
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn.wrappedValue ? FastSortTheme.accent : FastSortTheme.border)
                    .frame(width: 30, height: 16)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .padding(2)
                    }
            }
            .foregroundStyle(disabled ? FastSortTheme.muted.opacity(0.55) : FastSortTheme.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(FastSortTheme.background)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .contentShape(Capsule())
        .buttonStyle(.plain)
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 120, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            Text(display)
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(FastSortTheme.muted)
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack {
            Text(title)
                .frame(width: 120, alignment: .leading)
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue) \(suffix)")
                    .foregroundStyle(FastSortTheme.muted)
            }
        }
    }

    private func commentStatus(_ comment: LiveDanmuComment) -> some View {
        if comment.isWaiting {
            return AnyView(statusPill("等待", color: FastSortTheme.accent))
        }
        if comment.printed {
            return AnyView(statusPill("已打印", color: FastSortTheme.success))
        }
        if comment.printFailed {
            return AnyView(statusPill("失败", color: FastSortTheme.danger))
        }
        if comment.checked {
            return AnyView(statusPill("已选", color: FastSortTheme.accent))
        }
        return AnyView(EmptyView())
    }

    private func commentBackground(_ comment: LiveDanmuComment, index: Int) -> Color {
        if comment.blackBgShow {
            return FastSortTheme.danger.opacity(0.10)
        }
        if comment.printFailed {
            return FastSortTheme.danger.opacity(0.08)
        }
        if comment.printed {
            return FastSortTheme.success.opacity(0.08)
        }
        if comment.isWaiting || comment.checked {
            return FastSortTheme.accentSoft.opacity(0.85)
        }
        return index.isMultiple(of: 2) ? FastSortTheme.surface : FastSortTheme.background.opacity(0.65)
    }

    private var socketStatusLabel: String {
        switch socketStatus {
        case "connecting": return "连接中"
        case "open": return "已连接"
        case "closed": return "已断开"
        case "error": return "连接异常"
        default: return "未连接"
        }
    }

    private var danmuStatusLabel: String {
        switch socketStatus {
        case "connecting": return "弹幕连接中"
        case "open": return "弹幕已开启"
        case "closed": return "弹幕已关闭"
        case "error": return "弹幕异常"
        default: return "弹幕已断开"
        }
    }

    private var socketStatusColor: Color {
        switch socketStatus {
        case "open": return FastSortTheme.success
        case "connecting": return FastSortTheme.accent
        case "error": return FastSortTheme.danger
        default: return FastSortTheme.muted
        }
    }

    private var autoModeTitle: String {
        if bidModeEnabled { return "竞拍模式" }
        if nineGridModeEnabled { return "九宫格模式" }
        return "自动打印"
    }

    private var autoModeHeadline: String {
        if bidModeEnabled { return "\(bidWaitSeconds)s 后打印本轮最高出价" }
        if nineGridModeEnabled { return "\(nineGridWindowSeconds)s 内相同命中弹幕只打印第一条" }
        return "\(timeInterval)s 一轮，每轮最多 \(remainingNumber) 条"
    }

    private func setLiveType(_ value: String) {
        activeLiveType = value
        selectedRoom = nil
        comments = []
        pendingComments = []
        closeSocket(clearLiveState: true)
    }

    private func selectRoom(_ room: RoomListItem) {
        selectedRoom = room
        roomStatusText = "已选择，未连接"
        comments = []
        pendingComments = []
        lastUniqueKey = ""
        Task { await loadRoomPrintConfig(roomId: room.id ?? "") }
    }

    private func showToast(_ message: String) {
        toastText = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                if toastText == message {
                    toastText = ""
                }
            }
        }
    }

    private func loadRooms(force: Bool = false) async {
        guard force || !hasLoaded else { return }
        guard !appState.currentUserId.isEmpty else {
            errorText = "缺少用户信息，请重新登录"
            return
        }
        isLoadingRooms = true
        errorText = ""
        defer {
            isLoadingRooms = false
            hasLoaded = true
        }
        do {
            rooms = try await LiveRoomsService(apiClient: appState.makeAPIClient())
                .queryRoomsByUserId(appState.currentUserId)
            if let selectedRoom, !rooms.contains(where: { $0.id == selectedRoom.id }) {
                self.selectedRoom = nil
            }
            if selectedRoom == nil {
                self.selectedRoom = filteredRooms.first
                if let roomId = self.selectedRoom?.id {
                    await loadRoomPrintConfig(roomId: roomId)
                }
            }
        } catch {
            rooms = []
            errorText = error.localizedDescription
        }
    }

    private func deleteRoom(_ room: RoomListItem) async {
        guard let id = room.id else { return }
        do {
            try await LiveRoomsService(apiClient: appState.makeAPIClient()).deleteRoom(id: id)
            if selectedRoom?.id == id {
                selectedRoom = nil
                closeSocket(clearLiveState: true)
            }
            showToast("已删除直播间")
            await loadRooms(force: true)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func toggleRoomLive(_ room: RoomListItem) async {
        if selectedRoom?.id == room.id, !liveRecordId.isEmpty {
            await finishLive()
            return
        }
        selectedRoom = room
        await startLive(room: room)
    }

    private func startLive(room: RoomListItem) async {
        guard let roomId = room.id else {
            errorText = "缺少直播间 ID"
            return
        }
        guard !appState.currentUserId.isEmpty else {
            errorText = "缺少用户信息，请重新登录"
            return
        }
        if !appState.isVipActive && platformKey(for: room) != "kuaishou" {
            showToast("当前平台开播需要 VIP")
            return
        }
        isStarting = true
        errorText = ""
        defer { isStarting = false }
        do {
            let service = LiveRoomsService(apiClient: appState.makeAPIClient())
            let hasConfig = await loadRoomPrintConfig(roomId: roomId)
            if !hasConfig {
                showToast("当前直播间未配置弹幕模板")
                return
            }
            guard try await checkRoomStatus(roomId: roomId, service: service) else {
                return
            }

            let preparedSession = try await NativeDanmakuSessionCoordinator().prepare(room: room)
            let targetRoom = preparedSession.room
            comments = []
            pendingComments = []
            seenMessageIds = []
            selectedRoom = targetRoom
            let result = try await service
                .startLive(userId: appState.currentUserId, userRoomId: roomId, liveTitle: targetRoom.displayName)
            liveRecordId = result.id ?? ""
            sortBatchId = result.sortBatchId ?? ""
            connectNativeDanmaku(preparedSession)
        } catch {
            errorText = error.localizedDescription
            showToast(error.localizedDescription)
        }
    }

    private func checkRoomStatus(roomId: String, service: LiveRoomsService) async throws -> Bool {
        let status = try await service.getUserRoomStatus(roomId)
        if status.value == 4 {
            roomStatusText = "未开播"
            showToast("当前直播间未开播")
            return false
        }
        return true
    }

    private func finishLive() async {
        let recordId = liveRecordId
        closeSocket(clearLiveState: true)
        guard !recordId.isEmpty else { return }
        isStarting = true
        errorText = ""
        defer { isStarting = false }
        do {
            try await LiveRoomsService(apiClient: appState.makeAPIClient()).finishLive(id: recordId)
            showToast("直播已结束")
        } catch {
            errorText = error.localizedDescription
        }
    }

    @discardableResult
    private func loadRoomPrintConfig(roomId: String) async -> Bool {
        guard !roomId.isEmpty else { return false }
        do {
            let result = try await LiveRoomsService(apiClient: appState.makeAPIClient())
                .getUserRoomPostage(userRoomId: roomId)
            parseTemplateLayout(result.templateLayout)
            configRuleList = result.templateJsonVos ?? []
            mappingRules = parseMappingRules(result.danmuMappingVos ?? [])
            hasRoomTemplate = !(result.templateLayout ?? "").isEmpty || !configRuleList.isEmpty
            return hasRoomTemplate
        } catch {
            hasRoomTemplate = false
            configRuleList = []
            mappingRules = []
            return false
        }
    }

    private func parseTemplateLayout(_ raw: String?) {
        guard
            let raw,
            let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let width = object["tagWidth"] as? Int {
            printTagWidth = width
        } else if let width = object["tagWidth"] as? Double {
            printTagWidth = Int(width)
        }
        if let height = object["tagHeight"] as? Int {
            printTagHeight = height
        } else if let height = object["tagHeight"] as? Double {
            printTagHeight = Int(height)
        }
    }

    private func parseMappingRules(_ items: [DanmuMappingItem]) -> [DanmuMappingRule] {
        items.flatMap { item -> [DanmuMappingRule] in
            guard
                let raw = item.danmuMappingElement,
                let data = raw.data(using: .utf8),
                let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return [] }
            return rows.compactMap { row in
                let text = "\(row["text"] ?? row["key"] ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
                let value = "\(row["value"] ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return DanmuMappingRule(text: text, value: value)
            }
        }
    }

    private func connectNativeDanmaku(_ preparedSession: NativeDanmakuPreparedSession) {
        closeSocket(clearLiveState: false)
        nativePreparedSession = preparedSession
        isManualSocketClose = false
        socketStatus = "connecting"
        roomStatusText = "连接中"
        let coordinator = NativeDanmakuSessionCoordinator()
        socketLoopTask = Task {
            do {
                let connection = try await coordinator.connect(
                    preparedSession: preparedSession,
                    onEvent: { event in
                        guard isCurrentNativeSession(preparedSession) else { return }
                        handleNativeDanmakuEvent(event)
                    }
                )
                guard isCurrentNativeSession(preparedSession) else {
                    connection.cancel()
                    return
                }
                nativeDanmakuConnection = connection
                if socketStatus == "connecting" {
                    socketStatus = "open"
                    roomStatusText = "弹幕已连接"
                    reconnectCount = 0
                }
            } catch {
                guard isCurrentNativeSession(preparedSession) else { return }
                socketStatus = isManualSocketClose ? "idle" : "error"
                roomStatusText = isManualSocketClose ? "已断开" : "连接失败"
                errorText = error.localizedDescription
                showToast(error.localizedDescription)
                if !isManualSocketClose {
                    scheduleReconnect()
                }
            }
        }
    }

    private func closeSocket(clearLiveState: Bool) {
        isManualSocketClose = true
        socketLoopTask?.cancel()
        socketLoopTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        socketSession?.cancel()
        socketSession = nil
        nativeDanmakuConnection?.cancel()
        nativeDanmakuConnection = nil
        nativePreparedSession = nil
        reconnectCount = 0
        socketStatus = "idle"
        roomStatusText = "未连接"
        if clearLiveState {
            liveRecordId = ""
            sortBatchId = ""
            autoQueueCount = 0
        }
    }

    private func refreshSocket() {
        guard let selectedRoom, !liveRecordId.isEmpty else {
            showToast("请先开始直播")
            return
        }
        guard socketStatus != "connecting" else {
            showToast("弹幕正在连接")
            return
        }
        Task {
            await prepareAndConnectNativeDanmaku(selectedRoom)
        }
    }

    private func scheduleReconnect() {
        guard reconnectCount < 3, let room = selectedRoom, !liveRecordId.isEmpty else {
            socketStatus = "error"
            roomStatusText = "重连失败"
            return
        }
        reconnectCount += 1
        let delaySeconds = min(pow(2.0, Double(reconnectCount)), 10.0)
        roomStatusText = "第 \(reconnectCount) 次重连"
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            await MainActor.run {
                guard selectedRoom?.id == room.id else { return }
                refreshSocket()
            }
        }
    }

    private func prepareAndConnectNativeDanmaku(_ room: RoomListItem) async {
        do {
            let preparedSession = try await NativeDanmakuSessionCoordinator().prepare(room: room)
            connectNativeDanmaku(preparedSession)
        } catch {
            socketStatus = "error"
            roomStatusText = "连接失败"
            errorText = error.localizedDescription
            showToast(error.localizedDescription)
        }
    }

    private func isCurrentNativeSession(_ preparedSession: NativeDanmakuPreparedSession) -> Bool {
        nativePreparedSession?.request.platformKey == preparedSession.request.platformKey
            && nativePreparedSession?.request.roomId == preparedSession.request.roomId
            && nativePreparedSession?.request.displayName == preparedSession.request.displayName
    }

    private func handleNativeDanmakuEvent(_ event: NativeDanmakuEvent) {
        switch event.event {
        case .status:
            handleNativeStatus(event.status)
        case .chat:
            guard let comment = buildComment(from: event) else { return }
            if !comment.messageId.isEmpty {
                guard !seenMessageIds.contains(comment.messageId) else { return }
                seenMessageIds.insert(comment.messageId)
                if seenMessageIds.count > 500 {
                    seenMessageIds.remove(seenMessageIds.first ?? "")
                }
            }
            appendCommentForCurrentVisibility(comment)
            if printMode == "auto" {
                handleAutoPrint(comment)
            }
        case .error:
            socketStatus = "error"
            roomStatusText = event.content ?? "连接失败"
            if let content = event.content {
                showToast(content)
            }
        case .gift, .member, .like, .social, .control:
            break
        }
    }

    private func handleNativeStatus(_ status: NativeDanmakuStatus?) {
        switch status {
        case .connecting:
            socketStatus = "connecting"
            roomStatusText = "连接中"
        case .living:
            socketStatus = "open"
            roomStatusText = "直播中"
        case .stopped:
            roomStatusText = "直播已关闭"
            closeSocket(clearLiveState: true)
        case .disconnected:
            roomStatusText = "已断开"
            closeSocket(clearLiveState: false)
        case .loginExpired:
            socketStatus = "error"
            roomStatusText = "登录失效"
            closeSocket(clearLiveState: false)
        case .notStarted:
            roomStatusText = "未开播"
        case .error:
            socketStatus = "error"
            roomStatusText = "连接失败"
        case .none:
            break
        }
    }

    private func buildComment(from event: NativeDanmakuEvent) -> LiveDanmuComment? {
        let payload = event.rawPayload
        let content = (event.content ?? firstText(payload, keys: ["danmuContent", "content", "text"]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let messageId = (event.messageId ?? firstText(payload, keys: ["msgId", "dyMsgId", "tbMsgId", "xhsMsgId", "wxMsgId", "ksMsgId"]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackId = "\(Date().timeIntervalSince1970)-\(UUID().uuidString)"
        return LiveDanmuComment(
            id: messageId.isEmpty ? fallbackId : messageId,
            messageId: messageId,
            user: event.userName ?? firstText(payload, keys: ["danmuUserName", "nickname", "userName"], fallback: "用户"),
            content: content,
            orderNumber: firstText(payload, keys: ["orderNumber", "orderNo"]),
            danmuUserId: event.userId ?? firstText(payload, keys: ["danmuUserId", "userId", "danmuUserID"]),
            shortId: firstText(payload, keys: ["shortId", "short_id"]),
            roomId: event.platformRoomId ?? event.roomId ?? firstText(payload, keys: ["dyRoomId", "tbRoomId", "xhsRoomId", "wxRoomId", "ksRoomId", "roomId"]),
            fansStatus: firstText(payload, keys: ["fansStatus"], fallback: "0"),
            blackLevel: Int(firstText(payload, keys: ["blackLevel"], fallback: "0")) ?? 0,
            isMyBlack: isCurrentUserInCreatedUsers(payload["createdUsers"])
        )
    }

    private func appendCommentForCurrentVisibility(_ comment: LiveDanmuComment) {
        if pageActivation.isActive {
            comments = Array((comments + [comment]).suffix(80))
        } else {
            pendingComments = Array((pendingComments + [comment]).suffix(80))
        }
    }

    private func flushPendingComments() {
        guard !pendingComments.isEmpty else { return }
        comments = Array((comments + pendingComments).suffix(80))
        pendingComments = []
    }

    private func firstText(_ payload: [String: Any], keys: [String], fallback: String = "") -> String {
        for key in keys {
            if let value = payload[key], !(value is NSNull) {
                return "\(value)"
            }
        }
        return fallback
    }

    private func isCurrentUserInCreatedUsers(_ value: Any?) -> Bool {
        guard !appState.currentUserId.isEmpty, let value else { return false }
        if let values = value as? [Any] {
            return values.map { "\($0)" }.contains(appState.currentUserId)
        }
        if let raw = value as? String,
           let data = raw.data(using: .utf8),
           let values = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return values.map { "\($0)" }.contains(appState.currentUserId)
        }
        return false
    }

    private func applyPrintMode(_ mode: String) {
        if mode == "manual" {
            autoQueueCount = 0
            lastUniqueKey = ""
        } else {
            applyFrequencySettings()
        }
    }

    private func applyFrequencySettings() {
        timeInterval = max(1, timeInterval)
        remainingNumber = max(1, remainingNumber)
        repeatFilterSeconds = max(5, repeatFilterSeconds)
        bidWaitSeconds = max(5, bidWaitSeconds)
        nineGridWindowSeconds = max(1, nineGridWindowSeconds)
    }

    private func handleAutoPrint(_ comment: LiveDanmuComment) {
        if comment.blackLevel > 0 && comment.isMyBlack {
            updateComment(comment.id) { item in
                item.blackBgShow = true
            }
            return
        }
        if onlyPrintFans && comment.fansStatus != "1" {
            return
        }
        guard let amount = printableAmount(for: comment.content) else {
            return
        }
        if uniqueMode && amount == lastUniqueKey {
            showToast("去重模式已跳过重复弹幕")
            return
        }
        if uniqueMode {
            lastUniqueKey = amount
        }
        if !isPrinterConnected {
            autoQueueCount += 1
            updateComment(comment.id) { item in
                item.isWaiting = true
            }
            showToast("未连接打印机，自动打印已暂停")
            return
        }
        updateComment(comment.id) { item in
            item.printed = true
        }
    }

    private func handleManualPrint(_ comment: LiveDanmuComment) async {
        guard !liveRecordId.isEmpty else {
            showToast("请先开始直播")
            return
        }
        guard let amount = printableAmount(for: comment.content), !amount.isEmpty else {
            showToast("当前弹幕不符合打印规则")
            return
        }
        guard isPrinterConnected else {
            updateComment(comment.id) { item in
                item.printFailed = true
            }
            showToast("请先连接打印机")
            return
        }
        updateComment(comment.id) { item in
            item.checked = true
            item.isWaiting = false
            item.printed = true
            item.printFailed = false
        }
        showToast("已加入打印队列")
    }

    private func updateComment(_ id: String, mutate: (inout LiveDanmuComment) -> Void) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        mutate(&comments[index])
    }

    private func printableAmount(for content: String) -> String? {
        if let mapping = mappingRules.first(where: { $0.text == content.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            return "\(mapping.text)-\(mapping.value)"
        }
        if configRuleList.isEmpty {
            return firstNumber(in: content)
        }
        for group in configRuleList where matchRuleGroup(group, content: content) {
            return content
        }
        return nil
    }

    private func matchRuleGroup(_ group: TemplateRuleGroup, content: String) -> Bool {
        var remaining = content
        for rule in group {
            let type = rule.templateElement ?? ""
            let value = rule.elementValue ?? ""
            if remaining.isEmpty { return false }
            if type == "TEXT" {
                guard remaining.lowercased().hasPrefix(value.lowercased()) else { return false }
                remaining.removeFirst(min(value.count, remaining.count))
            } else if type == "NUMBER" {
                guard let number = firstLeadingNumber(in: remaining) else { return false }
                if rule.numberType == "fixed", !value.isEmpty, Double(number) != Double(value) {
                    return false
                }
                remaining.removeFirst(number.count)
            } else if type == "SYMBOL" {
                let length = rule.maxLength?.value ?? 0
                if length == 0 {
                    remaining = ""
                } else {
                    guard remaining.count >= length else { return false }
                    let prefix = String(remaining.prefix(length))
                    guard prefix.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
                    remaining.removeFirst(length)
                }
            }
        }
        return remaining.isEmpty
    }

    private func firstNumber(in text: String) -> String? {
        let pattern = #"\d+(?:\.\d*)?|\.\d+"#
        return text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
    }

    private func firstLeadingNumber(in text: String) -> String? {
        let pattern = #"^-?(?:\d+(?:\.\d+)?|\.\d+)"#
        return text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
    }

    private func platformKey(for room: RoomListItem) -> String {
        DanmakuPlatformRegistry.clientPlatformKey(forLiveType: room.liveType?.value)
    }
}

struct PlatformCatalog: Identifiable {
    let label: String
    let liveType: String
    var id: String { liveType }

    static let all = [
        PlatformCatalog(label: "抖音", liveType: "0"),
        PlatformCatalog(label: "淘宝", liveType: "1"),
        PlatformCatalog(label: "小红书", liveType: "2"),
        PlatformCatalog(label: "微信", liveType: "3"),
        PlatformCatalog(label: "快手", liveType: "4")
    ]

    static func label(for liveType: String) -> String {
        all.first { $0.liveType == liveType }?.label ?? "-"
    }
}

struct LiveDanmuComment: Identifiable, Equatable {
    let id: String
    let messageId: String
    let user: String
    let content: String
    let orderNumber: String
    let danmuUserId: String
    let shortId: String
    let roomId: String
    let fansStatus: String
    let blackLevel: Int
    let isMyBlack: Bool
    var checked = false
    var isWaiting = false
    var printed = false
    var printFailed = false
    var blackBgShow = false
}

struct DanmuMappingRule: Equatable {
    let text: String
    let value: String
}

struct IconCircleButtonStyle: ButtonStyle {
    var tint: Color = FastSortTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(FastSortTheme.accentSoft.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(Circle())
            .contentShape(Circle())
    }
}

struct EmptyPanel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(FastSortTheme.muted)
            .frame(maxWidth: .infinity, minHeight: 90)
            .webPanel(cornerRadius: 12)
    }
}
