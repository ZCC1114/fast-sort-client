import Foundation
import SwiftUI

struct LiveRoomsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pageActivation: PageActivationState

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
    @State private var isAddingRoom = false
    @State private var errorText = ""
    @State private var toastText = ""
    @State private var hasLoaded = false

    @State private var comments: [LiveDanmuComment] = []
    @State private var pendingComments: [LiveDanmuComment] = []
    @State private var seenMessageIds = Set<String>()
    @State private var socketSession: DanmakuWebSocketSession?
    @State private var socketLoopTask: Task<Void, Never>?
    @State private var heartbeatTask: Task<Void, Never>?
    @State private var reconnectTask: Task<Void, Never>?
    @State private var reconnectCount = 0
    @State private var isManualSocketClose = false

    @State private var showAddRoomDialog = false
    @State private var addRoomType = "0"
    @State private var addRoomInput = ""
    @State private var addRoomCookie = ""
    @State private var addRoomCover = ""
    @State private var showSettingsDialog = false
    @State private var showTaobaoLinkDialog = false
    @State private var taobaoLinkInput = ""
    @State private var pendingTaobaoRoom: RoomListItem?

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
        .sheet(isPresented: $showAddRoomDialog) {
            addRoomDialog
        }
        .sheet(isPresented: $showSettingsDialog) {
            settingsDialog
        }
        .sheet(isPresented: $showTaobaoLinkDialog) {
            taobaoLinkDialog
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
                    openAddRoomDialog()
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

    private var addRoomDialog: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("添加直播间")
                        .font(.system(size: 22, weight: .bold))
                    Text("按 Web 端相同接口创建直播间，创建后自动刷新列表")
                        .font(.system(size: 13))
                        .foregroundStyle(FastSortTheme.muted)
                }
                Spacer()
                Button {
                    closeAddRoomDialog()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconCircleButtonStyle())
            }

            platformTabsForAddRoom

            addRoomFields

            HStack {
                Spacer()
                Button("取消") {
                    closeAddRoomDialog()
                }
                .buttonStyle(AccentOutlineButtonStyle())
                Button(isAddingRoom ? "添加中..." : "添加") {
                    Task { await submitAddRoom() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isAddingRoom || addRoomSubmitDisabled)
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(FastSortTheme.background)
    }

    private var platformTabsForAddRoom: some View {
        MacChoiceGroup("平台", selection: Binding(
            get: { addRoomType },
            set: { next in
                addRoomType = next
                addRoomInput = ""
                addRoomCookie = ""
                addRoomCover = ""
            }
        ), options: platforms.map { MacChoiceOption(label: $0.label, value: $0.liveType) }, minItemWidth: 58)
    }

    @ViewBuilder
    private var addRoomFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            if addRoomType == "0" {
                fieldLabel("抖音直播间号")
                TextField("请输入抖音直播间号", text: $addRoomInput)
                    .webTextInput()
                helperText("对应 Web 端 addFsUserRoom/{roomNumber} 接口")
            } else if addRoomType == "1" {
                fieldLabel("淘宝直播间名称")
                TextField("请输入淘宝直播间名称", text: $addRoomInput)
                    .webTextInput()
                fieldLabel("千牛 Cookie")
                TextEditor(text: $addRoomCookie)
                    .frame(height: 110)
                    .font(.system(size: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FastSortTheme.border)
                    }
                helperText("保存到 liveSession，开播时由本机 helper 用千牛 Cookie 解析当前直播间")
            } else if addRoomType == "2" {
                fieldLabel("小红书 Cookie")
                TextEditor(text: $addRoomCookie)
                    .frame(height: 110)
                    .font(.system(size: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FastSortTheme.border)
                    }
                helperText("按弹幕捕手只保存 ark 工作台 Cookie；小红书本机弹幕 collector 待补齐")
            } else if addRoomType == "3" {
                fieldLabel("微信视频号直播间名称")
                TextField("请输入直播间名称", text: $addRoomInput)
                    .webTextInput()
                fieldLabel("微信会话 JSON")
                TextEditor(text: $addRoomCookie)
                    .frame(height: 100)
                    .font(.system(size: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FastSortTheme.border)
                    }
                fieldLabel("封面地址")
                TextField("可选，直播间封面 URL", text: $addRoomCover)
                    .webTextInput()
                helperText("Web 端是扫码获取 session；原生页先接同一 addFsUserWXRoom 后台接口")
            } else {
                fieldLabel("快手直播间号")
                TextField("请输入快手直播间号", text: $addRoomInput)
                    .webTextInput()
                fieldLabel("快手 Cookie")
                TextEditor(text: $addRoomCookie)
                    .frame(height: 110)
                    .font(.system(size: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FastSortTheme.border)
                    }
                helperText("对应 Web 端 addUpdateFsUserKuaishouRoom 接口")
            }
        }
        .padding(16)
        .webCard(cornerRadius: 14)
    }

    private var addRoomSubmitDisabled: Bool {
        let input = addRoomInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cookie = addRoomCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        switch addRoomType {
        case "0":
            return input.isEmpty
        case "1":
            return input.isEmpty || cookie.isEmpty
        case "2":
            return cookie.isEmpty
        case "3", "4":
            return input.isEmpty || cookie.isEmpty
        default:
            return true
        }
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

    private var taobaoLinkDialog: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("淘宝 roomId/链接兜底")
                        .font(.system(size: 22, weight: .bold))
                    Text(pendingTaobaoRoom?.displayName ?? "可选输入淘宝 roomId 或直播间分享链接")
                        .font(.system(size: 13))
                        .foregroundStyle(FastSortTheme.muted)
                }
                Spacer()
                Button {
                    closeTaobaoLinkDialog()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconCircleButtonStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("直播链接")
                TextField("粘贴淘宝直播间分享链接", text: $taobaoLinkInput)
                    .webTextInput()
                helperText("进入淘宝直播前会用该链接连接本机 /tb-ws adapter，不再连接后台弹幕服务。")
            }
            .padding(16)
            .webCard(cornerRadius: 14)

            HStack {
                Spacer()
                Button("取消") {
                    closeTaobaoLinkDialog()
                }
                .buttonStyle(AccentOutlineButtonStyle())
                Button("进入直播间") {
                    confirmTaobaoLinkDialog()
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

    private func helperText(_ text: String) -> some View {
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

    private func openAddRoomDialog() {
        addRoomType = activeLiveType
        addRoomInput = ""
        addRoomCookie = ""
        addRoomCover = ""
        showAddRoomDialog = true
    }

    private func closeAddRoomDialog() {
        showAddRoomDialog = false
        addRoomInput = ""
        addRoomCookie = ""
        addRoomCover = ""
        isAddingRoom = false
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

    private func submitAddRoom() async {
        guard !addRoomSubmitDisabled else { return }
        isAddingRoom = true
        errorText = ""
        defer { isAddingRoom = false }
        let service = LiveRoomsService(apiClient: appState.makeAPIClient())
        let input = addRoomInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cookie = addRoomCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch addRoomType {
            case "0":
                try await service.addDouyinRoom(roomNumber: input)
            case "1":
                try await service.addTaobaoRoom(roomName: input, liveSession: cookie)
            case "2":
                try await service.addOrUpdateXiaohongshuRoom(cookies: cookie)
            case "3":
                try await service.addWeChatRoom(roomName: input, cookies: cookie, roomUrl: addRoomCover)
            case "4":
                try await service.addOrUpdateKuaishouRoom(roomNumber: input, cookies: cookie)
            default:
                return
            }
            closeAddRoomDialog()
            showToast("添加成功")
            await loadRooms(force: true)
        } catch {
            errorText = error.localizedDescription
            showToast("添加直播间失败")
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

            var targetRoom = room
            let platform = platformKey(for: room)
            if platform == "xiaohongshu" {
                guard let preparedRoom = await prepareLocalXhsRoom(room) else {
                    return
                }
                targetRoom = preparedRoom
            } else if platform == "kuaishou" {
                guard let preparedRoom = await prepareLocalKuaishouRoom(room) else {
                    return
                }
                targetRoom = preparedRoom
            } else if platform == "taobao" {
                guard let preparedRoom = await prepareLocalTaobaoRoom(room) else {
                    return
                }
                targetRoom = preparedRoom
            } else if platform == "wechat" {
                try await LocalDanmakuHelperManager.shared.ensureRunning(.wechat)
            }
            comments = []
            pendingComments = []
            seenMessageIds = []
            selectedRoom = targetRoom
            let result = try await service
                .startLive(userId: appState.currentUserId, userRoomId: roomId, liveTitle: targetRoom.displayName)
            liveRecordId = result.id ?? ""
            sortBatchId = result.sortBatchId ?? ""
            connectSocket(targetRoom)
        } catch {
            errorText = error.localizedDescription
            showToast("开播失败")
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

    private func prepareLocalXhsRoom(_ room: RoomListItem) async -> RoomListItem? {
        let cookie = cookieHeader(from: room)
        guard !cookie.isEmpty else {
            showToast("小红书需要先保存 ark 工作台 Cookie")
            return nil
        }
        errorText = "小红书不能再走旧登录态方案。后续应使用 ark 工作台 Cookie，并在客户端侧 adapter 使用这段登录态解析直播和拉取弹幕；迅拣需要补齐同类本机 adapter 后才能本地开播。"
        showToast("小红书本机 collector 待补齐")
        return nil
    }

    private func prepareLocalKuaishouRoom(_ room: RoomListItem) async -> RoomListItem? {
        let roomId = (room.eid ?? room.roomNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cookie = cookieHeader(from: room)
        guard !cookie.isEmpty else {
            showToast("快手本机弹幕需要房间 liveSession 返回 Cookie")
            return nil
        }
        do {
            try await LocalDanmakuHelperManager.shared.ensureRunning(.kuaishou)
        } catch {
            showToast("快手本机弹幕组件启动失败：\(error.localizedDescription)")
            return nil
        }
        if roomId.isEmpty {
            do {
                let result = try await checkAndStartLocalLive(
                    portKey: "kuaishou",
                    defaultPort: 8301,
                    sessionId: "ks-\(room.id ?? UUID().uuidString)",
                    cookie: cookie,
                    roomId: nil
                )
                guard let resolvedRoomId = result.roomId?.trimmingCharacters(in: .whitespacesAndNewlines), !resolvedRoomId.isEmpty else {
                    showToast("快手当前账号未开播")
                    return nil
                }
                let updated = RoomListItem(
                    id: room.id,
                    roomName: result.title ?? room.roomName,
                    roomNumber: resolvedRoomId,
                    roomUrl: result.cover ?? room.roomUrl,
                    liveType: room.liveType,
                    liveSession: room.liveSession,
                    eid: resolvedRoomId,
                    ksWsPath: result.wsPath ?? room.ksWsPath,
                    wsPath: room.wsPath
                )
                replaceRoom(updated)
                return updated
            } catch {
                showToast("快手本机弹幕组件解析失败：\(error.localizedDescription)")
                return nil
            }
        }
        let updated = RoomListItem(
            id: room.id,
            roomName: room.roomName,
            roomNumber: room.roomNumber?.isEmpty == false ? room.roomNumber : roomId,
            roomUrl: room.roomUrl,
            liveType: room.liveType,
            liveSession: room.liveSession,
            eid: roomId,
            ksWsPath: room.ksWsPath,
            wsPath: room.wsPath
        )
        replaceRoom(updated)
        return updated
    }

    private func replaceRoom(_ updated: RoomListItem) {
        rooms = rooms.map { $0.id == updated.id ? updated : $0 }
    }

    private func prepareLocalTaobaoRoom(_ room: RoomListItem) async -> RoomListItem? {
        let cookie = cookieHeader(from: room)
        let storedLink = taobaoLink(for: room)
        let explicitRoomId = taobaoExplicitRoomId(from: room.roomNumber ?? "")
            ?? taobaoExplicitRoomId(from: storedLink)
        let sourceURL = explicitRoomId == nil ? storedLink : ""
        guard !cookie.isEmpty || !sourceURL.isEmpty || explicitRoomId != nil else {
            showToast("淘宝本机弹幕需要房间 liveSession 返回千牛 Cookie")
            return nil
        }
        do {
            try await LocalDanmakuHelperManager.shared.ensureRunning(.taobao)
            let result = try await checkAndStartLocalLive(
                portKey: "taobao",
                defaultPort: 8201,
                sessionId: "tb-\(room.id ?? UUID().uuidString)",
                cookie: cookie,
                roomId: explicitRoomId,
                sourceURL: sourceURL
            )
            guard let roomId = result.roomId?.trimmingCharacters(in: .whitespacesAndNewlines), !roomId.isEmpty else {
                showToast(result.message ?? "淘宝当前账号未开播或未解析到 roomId")
                return nil
            }
            let updated = RoomListItem(
                id: room.id,
                roomName: result.title ?? room.roomName,
                roomNumber: roomId,
                roomUrl: result.cover ?? room.roomUrl,
                liveType: room.liveType,
                liveSession: room.liveSession,
                eid: room.eid,
                ksWsPath: room.ksWsPath,
                wsPath: result.wsPath ?? room.wsPath
            )
            replaceRoom(updated)
            return updated
        } catch {
            showToast("淘宝本机弹幕组件解析失败：\(error.localizedDescription)")
            return nil
        }
    }

    private func taobaoLink(for room: RoomListItem) -> String {
        let key = taobaoLinkStorageKey(for: room)
        let stored = key.flatMap { UserDefaults.standard.string(forKey: $0) } ?? ""
        let raw = stored.isEmpty ? (room.roomNumber ?? "") : stored
        return extractHttpLink(raw)
    }

    private func taobaoExplicitRoomId(from value: String) -> String? {
        let text = decodePercentRepeatedly(value)
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let roomId = queryValue(in: text, name: "wh_cid") {
            return roomId
        }
        if let roomId = queryValue(in: text, name: "roomId") ?? queryValue(in: text, name: "liveId") {
            return roomId
        }
        if let roomId = firstRegexCapture(in: text, pattern: #"liveplatform/([A-Fa-f0-9\-]{16,})___"#) {
            return roomId
        }
        if let roomId = firstRegexCapture(in: text, pattern: #"wh_cid=([^&"' <>\n]+)"#) {
            return decodePercentRepeatedly(roomId)
        }
        if text.range(of: #"^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$"#, options: .regularExpression) != nil {
            return text
        }
        if text.range(of: #"^[A-Za-z0-9_\-]{6,80}$"#, options: .regularExpression) != nil {
            return text
        }
        return nil
    }

    private func openTaobaoLinkDialog(_ room: RoomListItem) {
        pendingTaobaoRoom = room
        let key = taobaoLinkStorageKey(for: room)
        taobaoLinkInput = key.flatMap { UserDefaults.standard.string(forKey: $0) } ?? room.roomNumber ?? ""
        showTaobaoLinkDialog = true
    }

    private func closeTaobaoLinkDialog() {
        showTaobaoLinkDialog = false
        pendingTaobaoRoom = nil
        taobaoLinkInput = ""
    }

    private func confirmTaobaoLinkDialog() {
        guard let room = pendingTaobaoRoom else {
            closeTaobaoLinkDialog()
            return
        }
        let link = extractHttpLink(taobaoLinkInput)
        guard !link.isEmpty else {
            showToast("无效链接，请重新输入")
            return
        }
        if let key = taobaoLinkStorageKey(for: room) {
            UserDefaults.standard.set(link, forKey: key)
        }
        closeTaobaoLinkDialog()
        let updated = RoomListItem(
            id: room.id,
            roomName: room.roomName,
            roomNumber: link,
            roomUrl: room.roomUrl,
            liveType: room.liveType,
            liveSession: room.liveSession,
            eid: room.eid,
            ksWsPath: room.ksWsPath,
            wsPath: room.wsPath
        )
        replaceRoom(updated)
        Task { await startLive(room: updated) }
    }

    private func taobaoLinkStorageKey(for room: RoomListItem) -> String? {
        guard let id = room.id, !id.isEmpty else { return nil }
        return "\(id)-TB"
    }

    private func extractHttpLink(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: #"https?://[^\s]+"#, options: .regularExpression) else {
            return ""
        }
        return String(text[range])
    }

    private func queryValue(in text: String, name: String) -> String? {
        if let url = URL(string: text),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name == name })?.value,
           !value.isEmpty {
            return decodePercentRepeatedly(value)
        }
        let escaped = NSRegularExpression.escapedPattern(for: name)
        if let value = firstRegexCapture(in: text, pattern: "\(escaped)=([^&\"' <>\\n]+)") {
            return decodePercentRepeatedly(value)
        }
        return nil
    }

    private func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private func decodePercentRepeatedly(_ value: String) -> String {
        var result = value
        for _ in 0..<3 {
            guard let decoded = result.removingPercentEncoding, decoded != result else { break }
            result = decoded
        }
        return result
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

    private func connectSocket(_ room: RoomListItem) {
        closeSocket(clearLiveState: false)
        guard let request = socketRequest(for: room) else {
            socketStatus = "error"
            roomStatusText = "缺少连接信息"
            showToast("缺少弹幕连接信息")
            return
        }
        isManualSocketClose = false
        socketStatus = "connecting"
        roomStatusText = "连接中"
        let session = DanmakuWebSocketSession()
        socketSession = session
        socketLoopTask = Task {
            do {
                try await session.run(
                    request: request,
                    onOpen: {},
                    onMessage: { message in
                        guard socketSession === session else { return }
                        handleSocketMessage(message)
                    }
                )
            } catch {
                guard socketSession === session else { return }
                socketStatus = isManualSocketClose ? "idle" : "closed"
                roomStatusText = isManualSocketClose ? "已断开" : "连接断开"
                if !isManualSocketClose {
                    scheduleReconnect()
                }
            }
        }
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await MainActor.run {
                    guard socketSession === session else { return }
                    session.sendPing()
                }
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                if socketSession === session && socketStatus == "connecting" {
                    socketStatus = "open"
                    roomStatusText = "弹幕已连接"
                    reconnectCount = 0
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
        connectSocket(selectedRoom)
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
                connectSocket(room)
            }
        }
    }

    private func handleSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        guard let text = DanmakuSocketMessageParser.text(from: message), !text.isEmpty else { return }
        if let status = DanmakuSocketMessageParser.status(fromText: text) {
            handleSocketStatus(status)
            return
        }
        guard
            let data = text.data(using: .utf8),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let liveStatus = payload["liveStatus"] {
            handleLiveStatusValue(liveStatus)
            return
        }
        guard let comment = buildComment(from: payload) else { return }
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

    private func handleSocketStatus(_ status: DanmakuSocketTextStatus) {
        switch status {
        case .pong:
            break
        case .connecting:
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
        case .paused:
            roomStatusText = "暂停"
        case .ended:
            roomStatusText = "已结束"
            closeSocket(clearLiveState: true)
        case .loginExpired:
            socketStatus = "error"
            roomStatusText = "登录失效"
            closeSocket(clearLiveState: false)
        case .notStarted:
            roomStatusText = "未开播"
        }
    }

    private func handleLiveStatusValue(_ value: Any) {
        switch DanmakuSocketMessageParser.liveStatus(from: value) {
        case .living:
            roomStatusText = "直播中"
        case .notStarted:
            roomStatusText = "未开播"
        case .paused:
            roomStatusText = "暂停"
        case .ended:
            roomStatusText = "已结束"
        case .loginExpired:
            socketStatus = "error"
            roomStatusText = "登录失效"
        case .none, .pong, .connecting, .stopped, .disconnected:
            break
        }
    }

    private func buildComment(from payload: [String: Any]) -> LiveDanmuComment? {
        let content = firstText(payload, keys: ["danmuContent", "content", "text"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let platform = selectedRoom.map(platformKey(for:)) ?? ""
        let messageIdKeys = platform == "wechat"
            ? ["wxMsgId"]
            : ["ksMsgId", "msgId", "dyMsgId", "tbMsgId", "xhsMsgId", "wxMsgId"]
        return LiveDanmuComment(
            id: firstText(payload, keys: messageIdKeys).isEmpty ? "\(Date().timeIntervalSince1970)-\(UUID().uuidString)" : firstText(payload, keys: messageIdKeys),
            messageId: firstText(payload, keys: messageIdKeys),
            user: firstText(payload, keys: ["danmuUserName", "nickname", "userName"], fallback: "用户"),
            content: content,
            orderNumber: firstText(payload, keys: ["orderNumber", "orderNo"]),
            danmuUserId: firstText(payload, keys: ["danmuUserId", "userId", "danmuUserID"]),
            shortId: firstText(payload, keys: ["shortId", "short_id"]),
            roomId: firstText(payload, keys: ["dyRoomId", "tbRoomId", "xhsRoomId", "wxRoomId", "ksRoomId", "roomId"]),
            fansStatus: firstText(payload, keys: ["fansStatus"], fallback: "0"),
            blackLevel: Int(firstText(payload, keys: ["blackLevel"], fallback: "0")) ?? 0,
            isMyBlack: isCurrentUserInCreatedUsers(payload["createdUsers"])
        )
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

    private func socketRequest(for room: RoomListItem) -> URLRequest? {
        guard let url = socketURL(for: room) else { return nil }
        var request = URLRequest(url: url)
        let platform = platformKey(for: room)
        let cookie = cookieHeader(from: room)
        if platform == "kuaishou", !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "x-kuaishou-cookie")
        }
        return request
    }

    private func socketURL(for room: RoomListItem) -> URL? {
        let platform = platformKey(for: room)
        let roomNumber = (room.roomNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedRoomNumber = Self.pathComponent(roomNumber)
        let cookie = cookieHeader(from: room)
        switch platform {
        case "taobao":
            guard !encodedRoomNumber.isEmpty else { return nil }
            return localWebSocketURL(
                portKey: "taobao",
                defaultPort: 8201,
                path: "/tb-ws/\(encodedRoomNumber)"
            )
        case "xiaohongshu":
            return nil
        case "wechat":
            guard let session = DanmakuCookieSessionParser.wechatSession(fromLiveSession: room.liveSession) else { return nil }
            return localWebSocketURL(
                portKey: "wechat",
                defaultPort: 8000,
                path: "/wx-ws",
                queryItems: [
                    URLQueryItem(name: "sessionid", value: session.sessionid),
                    URLQueryItem(name: "wxuin", value: session.wxuin)
                ]
            )
        case "kuaishou":
            if let wsPath = [room.ksWsPath, room.wsPath].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                if wsPath.hasPrefix("ws://") || wsPath.hasPrefix("wss://") {
                    return localWebSocketURL(fromConfiguredWebSocket: wsPath, portKey: "kuaishou", defaultPort: 8301)
                }
                return localWebSocketURL(
                    portKey: "kuaishou",
                    defaultPort: 8301,
                    path: wsPath.hasPrefix("/") ? wsPath : "/\(wsPath)"
                )
            }
            let roomId = Self.pathComponent(room.eid ?? room.roomNumber ?? "")
            guard !roomId.isEmpty else { return nil }
            return localWebSocketURL(
                portKey: "kuaishou",
                defaultPort: 8301,
                path: "/ks-ws/\(roomId)"
            )
        case "tiktok":
            guard !encodedRoomNumber.isEmpty else { return nil }
            return localWebSocketURL(
                portKey: "tiktok",
                defaultPort: 8765,
                path: "/ws/\(encodedRoomNumber)"
            )
        case "shopee":
            guard !roomNumber.isEmpty else { return nil }
            if roomNumber.allSatisfy(\.isNumber) {
                return localWebSocketURL(
                    portKey: "shopee",
                    defaultPort: 8001,
                    path: "/shopee/ws",
                    queryItems: [URLQueryItem(name: "session_id", value: roomNumber)]
                )
            }
            return localWebSocketURL(
                portKey: "shopee",
                defaultPort: 8001,
                path: "/shopee/ws",
                queryItems: [URLQueryItem(name: "share_url", value: roomNumber)]
            )
        default:
            guard !encodedRoomNumber.isEmpty else { return nil }
            let cookieItems = cookie.isEmpty
                ? []
                : [URLQueryItem(name: "cookie_b64", value: Data(cookie.utf8).base64EncodedString())]
            return localWebSocketURL(
                portKey: "douyin",
                defaultPort: 8865,
                path: "/ws/events/\(encodedRoomNumber)",
                queryItems: cookieItems
            )
        }
    }

    private func localWebSocketURL(
        portKey: String,
        defaultPort: Int,
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        DanmakuLocalConnectionBuilder.webSocketURL(
            portKey: portKey,
            defaultPort: defaultPort,
            path: path,
            queryItems: queryItems
        )
    }

    private func localHTTPURL(
        portKey: String,
        defaultPort: Int,
        path: String
    ) -> URL? {
        DanmakuLocalConnectionBuilder.httpURL(
            portKey: portKey,
            defaultPort: defaultPort,
            path: path
        )
    }

    private func checkAndStartLocalLive(
        portKey: String,
        defaultPort: Int,
        sessionId: String,
        cookie: String,
        roomId: String?,
        sourceURL: String? = nil
    ) async throws -> LocalLivePrepareData {
        guard let url = localHTTPURL(portKey: portKey, defaultPort: defaultPort, path: "/api/live/check_and_start") else {
            throw LocalLivePrepareError("本机 helper URL 构造失败")
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
            throw LocalLivePrepareError("本机 helper HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(LocalLivePrepareResponse.self, from: data)
        guard decoded.success != false else {
            throw LocalLivePrepareError(decoded.msg ?? decoded.message ?? "本机 helper 返回失败")
        }
        let fallbackMessage = decoded.msg ?? decoded.message
        return decoded.data?.withFallbackMessage(fallbackMessage)
            ?? LocalLivePrepareData(status: nil, roomId: nil, title: nil, cover: nil, wsPath: nil, message: fallbackMessage)
    }

    private func localWebSocketURL(
        fromConfiguredWebSocket raw: String,
        portKey: String,
        defaultPort: Int
    ) -> URL? {
        DanmakuLocalConnectionBuilder.webSocketURL(
            fromConfiguredWebSocket: raw,
            portKey: portKey,
            defaultPort: defaultPort
        )
    }

    private func cookieHeader(from room: RoomListItem) -> String {
        DanmakuCookieSessionParser.cookieHeader(fromLiveSession: room.liveSession)
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
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

struct LocalLivePrepareResponse: Decodable {
    let code: Int?
    let success: Bool?
    let msg: String?
    let message: String?
    let data: LocalLivePrepareData?
}

struct LocalLivePrepareData: Decodable {
    let status: Int?
    let roomId: String?
    let title: String?
    let cover: String?
    let wsPath: String?
    let message: String?

    func withFallbackMessage(_ fallback: String?) -> LocalLivePrepareData {
        guard message == nil, let fallback else { return self }
        return LocalLivePrepareData(status: status, roomId: roomId, title: title, cover: cover, wsPath: wsPath, message: fallback)
    }

    enum CodingKeys: String, CodingKey {
        case status
        case roomId = "room_id"
        case title
        case cover
        case wsPath = "ws_path"
        case message
    }
}

struct LocalLivePrepareError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
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
