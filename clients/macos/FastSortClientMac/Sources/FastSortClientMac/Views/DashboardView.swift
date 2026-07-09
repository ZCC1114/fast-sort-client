import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pageActivation: PageActivationState
    let onRouteRequested: (AppRoute) -> Void

    @State private var isLoading = false
    @State private var errorText = ""
    @State private var stats = DashboardStats()
    @State private var trend = TrendResponse(legend: [], xAxis: [], series: [])
    @State private var quickRange = 7
    @State private var startDate = ""
    @State private var endDate = ""
    @State private var rooms: [RoomListItem] = []
    @State private var batches: [DashboardBatchRow] = []
    @State private var blacklist: [BlacklistItem] = []
    @State private var blacklistTotal = 0
    @State private var blacklistScope: BlacklistScope = .mine
    @State private var pendingCompleteBatch: DashboardBatchRow?
    @State private var hasLoaded = false

    init(onRouteRequested: @escaping (AppRoute) -> Void = { _ in }) {
        self.onRouteRequested = onRouteRequested
    }

    private let platforms = [
        PlatformOption(label: "抖音", liveType: "0"),
        PlatformOption(label: "淘宝", liveType: "1"),
        PlatformOption(label: "小红书", liveType: "2"),
        PlatformOption(label: "微信", liveType: "3"),
        PlatformOption(label: "快手", liveType: "4")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statGrid
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 13))
                        .foregroundStyle(FastSortTheme.danger)
                }
                dashboardGrid
            }
            .macPagePadding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .overlay {
            if isLoading && !hasLoaded {
                ProgressView("加载首页数据")
                    .padding(18)
                    .background(FastSortTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .confirmationDialog(
            "确认操作",
            isPresented: Binding(
                get: { pendingCompleteBatch != nil },
                set: { if !$0 { pendingCompleteBatch = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingCompleteBatch
        ) { batch in
            Button("确认重置编号", role: .destructive) {
                Task { await completeBatch(batch) }
            }
            Button("取消", role: .cancel) {
                pendingCompleteBatch = nil
            }
        } message: { _ in
            Text("确认将该批次完成并重置编号？")
        }
        .task(id: pageActivation.isActive) {
            guard pageActivation.isActive, !hasLoaded else { return }
            guard await pageActivation.waitForFirstInteractiveFrame() else { return }
            setDefaultRange()
            await loadDashboard()
        }
    }

    private var statGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 160), spacing: 12), count: 5),
            spacing: 12
        ) {
            StatCard(title: "已打印标签", value: stats.printedTagCount, icon: "printer.fill") {
                onRouteRequested(.pick)
            }
            StatCard(title: "扣数总用户数", value: stats.orderCount, icon: "person.2.fill") {
                onRouteRequested(.pick)
            }
            StatCard(title: "直播间", value: stats.userRoomCount, icon: "play.rectangle.fill") {
                onRouteRequested(.liveRooms)
            }
            StatCard(title: "标签模板", value: stats.tagTemplateCount, icon: "doc.text.fill") {
                onRouteRequested(.settings)
            }
            StatCard(title: "黑名单", value: stats.blackListCount, icon: "person.crop.circle.badge.xmark") {
                onRouteRequested(.blacklist)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var dashboardGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    chartCard
                    batchesCard
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    roomsCard
                    blacklistCard
                }
                .frame(width: 340)
            }

            VStack(spacing: 16) {
                chartCard
                batchesCard
                roomsCard
                blacklistCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var chartCard: some View {
        DashboardCard {
            HStack {
                Text("打印报表")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("7 天") {
                    Task { await applyQuickRange(7) }
                }
                .buttonStyle(FilterPillStyle(active: quickRange == 7))
                Button("30 天") {
                    Task { await applyQuickRange(30) }
                }
                .buttonStyle(FilterPillStyle(active: quickRange == 30))
                Text(startDate)
                    .datePill()
                Text("-")
                    .font(.system(size: 12))
                    .foregroundStyle(FastSortTheme.muted)
                Text(endDate)
                    .datePill()
            }
            TrendLineChart(response: trend)
                .frame(height: 310)
        }
    }

    private var batchesCard: some View {
        DashboardCard {
            Text("最新理货批次")
                .font(.system(size: 18, weight: .semibold))
            VStack(spacing: 10) {
                ForEach(batches) { batch in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(batch.platform)
                                .font(.system(size: 14, weight: .semibold))
                            Text(batch.batchName)
                                .foregroundStyle(FastSortTheme.muted)
                            Text("创建：\(formatDate(batch.createdTime))")
                                .font(.system(size: 12))
                                .foregroundStyle(FastSortTheme.muted)
                        }
                        Spacer()
                        Text(batch.statusLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(batch.isCompleted ? FastSortTheme.success : FastSortTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(batch.isCompleted ? FastSortTheme.success.opacity(0.12) : FastSortTheme.accentSoft)
                            .clipShape(Capsule())
                        if batch.canComplete {
                            Button("重置编号") {
                                pendingCompleteBatch = batch
                            }
                            .buttonStyle(OutlineTinyButtonStyle())
                        }
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onRouteRequested(.pick)
                    }
                    Divider()
                        .background(FastSortTheme.border)
                }
                if batches.isEmpty {
                    EmptyState(text: "暂无理货批次")
                }
            }
        }
    }

    private var roomsCard: some View {
        DashboardCard {
            HStack {
                Text("直播间")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("查看全部") {
                    onRouteRequested(.liveRooms)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Capsule())
                .foregroundStyle(FastSortTheme.accent)
            }
            VStack(spacing: 10) {
                ForEach(rooms.prefix(5)) { room in
                    HStack(spacing: 10) {
                        AsyncImage(url: URL(string: room.roomUrl ?? "")) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundStyle(FastSortTheme.accent)
                        }
                        .frame(width: 42, height: 42)
                        .background(FastSortTheme.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(room.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(room.handle.isEmpty ? platformLabel(room.liveType?.value) : room.handle)
                                .font(.system(size: 12))
                                .foregroundStyle(FastSortTheme.muted)
                        }
                        Spacer()
                        Text(platformLabel(room.liveType?.value))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(platformForeground(room.liveType?.value))
                            .background(platformBackground(room.liveType?.value))
                            .clipShape(Capsule())
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onRouteRequested(.liveRooms)
                    }
                }
                if rooms.isEmpty {
                    EmptyState(text: "暂无直播间")
                }
            }
        }
    }

    private var blacklistCard: some View {
        DashboardCard {
            HStack {
                Text("黑名单")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("查看全部") {
                    onRouteRequested(.blacklist)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Capsule())
                .foregroundStyle(FastSortTheme.accent)
            }
            HStack(spacing: 18) {
                Button("我的黑名单") {
                    Task { await setBlacklistScope(.mine) }
                }
                .buttonStyle(TabUnderlineButtonStyle(active: blacklistScope == .mine))

                Button("全局黑名单") {
                    Task { await setBlacklistScope(.global) }
                }
                .buttonStyle(TabUnderlineButtonStyle(active: blacklistScope == .global))
                .disabled(!appState.isVipActive)
            }
            VStack(spacing: 10) {
                ForEach(blacklist.prefix(5)) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.orderName ?? "-")
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(platformLabel(item.liveType?.value)) · \(blackTypeLabel(item.blackType?.value)) · \(formatDate(item.createdTime))")
                                .font(.system(size: 12))
                                .foregroundStyle(FastSortTheme.muted)
                        }
                        Spacer()
                        Text("LV\(item.blackLevel?.value ?? 1)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FastSortTheme.accent)
                    }
                    .padding(.vertical, 4)
                }
                if blacklist.isEmpty {
                    EmptyState(text: "未查询到数据")
                }
            }
        }
    }

    private func loadDashboard() async {
        isLoading = true
        errorText = ""
        defer {
            isLoading = false
            hasLoaded = true
        }

        let service = DashboardService(apiClient: appState.makeAPIClient())

        do {
            let statsResult = try await service.getCurrentUserStats()
            stats = DashboardStats(stats: statsResult)
        } catch {
            errorText = error.localizedDescription
        }

        do {
            trend = try await service.getUserTagTrend(startTime: startDate, endTime: endDate)
        } catch {
            trend = TrendResponse(legend: [], xAxis: [], series: [])
        }

        do {
            rooms = appState.currentUserId.isEmpty ? [] : try await service.queryRoomsByUserId(appState.currentUserId)
        } catch {
            rooms = []
        }

        batches = await loadLatestBatches(service: service)
        await loadBlacklist()
    }

    private func loadBlacklist() async {
        do {
            let page = try await DashboardService(apiClient: appState.makeAPIClient()).getBlackPage(
                pageIndex: 1,
                pageSize: 5,
                userId: blacklistScope == .mine && !appState.currentUserId.isEmpty ? appState.currentUserId : nil
            )
            blacklist = page.list ?? []
            blacklistTotal = page.total?.value ?? page.totalCount?.value ?? page.count?.value ?? 0
        } catch {
            blacklist = []
            blacklistTotal = 0
            errorText = error.localizedDescription
        }
    }

    private func loadLatestBatches(service: DashboardService) async -> [DashboardBatchRow] {
        var rows: [DashboardBatchRow] = []
        for platform in platforms {
            do {
                let result = try await service.getAllSortBatchList(liveType: platform.liveType)
                let batch = result.notComplete ?? result.historyCompletedPage?.list?.first
                rows.append(DashboardBatchRow(platform: platform.label, liveType: platform.liveType, batch: batch))
            } catch {
                rows.append(DashboardBatchRow(platform: platform.label, liveType: platform.liveType, batch: nil))
            }
        }
        return rows
    }

    private func setBlacklistScope(_ scope: BlacklistScope) async {
        if scope == .global && !appState.isVipActive {
            errorText = "开通 VIP 后可查看全局黑名单"
            return
        }
        blacklistScope = scope
        await loadBlacklist()
    }

    private func completeBatch(_ batch: DashboardBatchRow) async {
        pendingCompleteBatch = nil
        guard let id = batch.batchId, !id.isEmpty else { return }
        do {
            try await DashboardService(apiClient: appState.makeAPIClient())
                .completeSortBatch(id: id, refreshIndexNumber: 1)
            batches = await loadLatestBatches(service: DashboardService(apiClient: appState.makeAPIClient()))
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func applyQuickRange(_ days: Int) async {
        quickRange = days
        let formatter = Self.dateFormatter
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        startDate = formatter.string(from: start)
        endDate = formatter.string(from: end)
        do {
            trend = try await DashboardService(apiClient: appState.makeAPIClient())
                .getUserTagTrend(startTime: startDate, endTime: endDate)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func setDefaultRange() {
        let formatter = Self.dateFormatter
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -6, to: end) ?? end
        startDate = formatter.string(from: start)
        endDate = formatter.string(from: end)
    }

    private func platformLabel(_ liveType: String?) -> String {
        platforms.first { $0.liveType == (liveType ?? "0") }?.label ?? "-"
    }

    private func blackTypeLabel(_ value: String?) -> String {
        value == "2" ? "跑单" : "恶意"
    }

    private func platformForeground(_ liveType: String?) -> Color {
        switch liveType ?? "0" {
        case "0": return Color(hex: 0xff3b30)
        case "1": return Color(hex: 0x5856d6)
        case "2": return Color(hex: 0xaf52de)
        case "3": return Color(hex: 0x34c759)
        case "4": return Color(hex: 0x007aff)
        default: return FastSortTheme.accent
        }
    }

    private func platformBackground(_ liveType: String?) -> Color {
        switch liveType ?? "0" {
        case "0": return Color(hex: 0xff3b30, opacity: 0.10)
        case "1": return Color(hex: 0x5856d6, opacity: 0.10)
        case "2": return Color(hex: 0xaf52de, opacity: 0.10)
        case "3": return Color(hex: 0x34c759, opacity: 0.12)
        case "4": return Color(hex: 0x007aff, opacity: 0.10)
        default: return FastSortTheme.accentSoft
        }
    }

    private func formatDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct DashboardStats {
    var printedTagCount = "0"
    var orderCount = "0"
    var userRoomCount = "0"
    var tagTemplateCount = "0"
    var blackListCount = "0"

    init() {}

    init(stats: UserStatsResponse) {
        printedTagCount = String(stats.printedTagCount?.value ?? 0)
        orderCount = String(stats.orderCount?.value ?? 0)
        userRoomCount = String(stats.userRoomCount?.value ?? 0)
        tagTemplateCount = String(stats.tagTemplateCount?.value ?? 0)
        blackListCount = String(stats.blackListCount?.value ?? 0)
    }
}

private struct PlatformOption {
    let label: String
    let liveType: String
}

private enum BlacklistScope {
    case mine
    case global
}

private struct DashboardBatchRow: Identifiable {
    let id = UUID()
    let batchId: String?
    let platform: String
    let liveType: String
    let batchName: String
    let statusLabel: String
    let createdTime: String?
    let isCompleted: Bool
    let canComplete: Bool

    init(platform: String, liveType: String, batch: SortBatchItem?) {
        batchId = batch?.id
        self.platform = platform
        self.liveType = liveType
        batchName = batch?.batchName?.isEmpty == false ? batch?.batchName ?? "-" : "-"
        let completed = batch?.sortStatus?.value == "1"
        isCompleted = completed
        canComplete = batch?.id?.isEmpty == false && !completed
        statusLabel = completed ? "已完成" : (batch == nil ? "-" : "进行中")
        createdTime = batch?.createdTime
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FastSortTheme.accent)
                    .frame(width: 46, height: 46)
                    .background(FastSortTheme.accentSoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(FastSortTheme.text)
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(FastSortTheme.muted)
                }
                Spacer()
            }
            .padding(18)
            .frame(minHeight: 86)
            .webCard(cornerRadius: 14)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .buttonStyle(.plain)
    }
}

private struct DashboardCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .webCard()
    }
}

private struct EmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(FastSortTheme.muted)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(FastSortTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct TrendLineChart: View {
    let response: TrendResponse

    private var visibleSeries: [TrendSeries] {
        (response.series ?? []).filter { ($0.data ?? []).contains { $0 > 0 } }
    }

    private var labels: [String] {
        response.xAxis ?? []
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawGrid(context: context, size: size)
                drawLines(series: visibleSeries, context: context, size: size)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    ForEach(Array(labels.prefix(7).enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(FastSortTheme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
            }
            .overlay {
                if visibleSeries.isEmpty {
                    EmptyState(text: "暂无趋势数据")
                        .frame(width: max(0, proxy.size.width - 16), height: 70)
                }
            }
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let rows = 4
        for index in 0...rows {
            let y = size.height * CGFloat(index) / CGFloat(rows)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(FastSortTheme.border), lineWidth: 1)
        }
    }

    private func drawLines(series: [TrendSeries], context: GraphicsContext, size: CGSize) {
        let allValues = series.flatMap { $0.data ?? [] }
        guard let maxValue = allValues.max(), maxValue > 0 else { return }
        let plotHeight = max(20, size.height - 36)
        let colors: [Color] = [
            FastSortTheme.accent,
            FastSortTheme.success,
            Color(hex: 0xff9500),
            Color(hex: 0xaf52de),
            Color(hex: 0xff3b30)
        ]

        for (seriesIndex, item) in series.enumerated() {
            let points = item.data ?? []
            guard points.count > 1 else { continue }
            let widthStep = size.width / CGFloat(points.count - 1)
            var path = Path()
            for (index, point) in points.enumerated() {
                let x = CGFloat(index) * widthStep
                let y = plotHeight - (CGFloat(point / maxValue) * (plotHeight - 24)) + 12
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            let color = colors[seriesIndex % colors.count]
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct FilterPillStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? .white : FastSortTheme.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(active ? FastSortTheme.accent : FastSortTheme.accentSoft.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(Capsule())
            .contentShape(Capsule())
    }
}

private struct OutlineTinyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(FastSortTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(FastSortTheme.surface.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FastSortTheme.accent.opacity(0.35), lineWidth: 1)
            }
    }
}

private struct TabUnderlineButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 5) {
            configuration.label
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? FastSortTheme.accent : FastSortTheme.muted)
            Rectangle()
                .fill(active ? FastSortTheme.accent : Color.clear)
                .frame(height: 2)
        }
        .frame(minWidth: 72, minHeight: 28)
        .contentShape(Rectangle())
        .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private extension View {
    func datePill() -> some View {
        self
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(FastSortTheme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(FastSortTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FastSortTheme.border, lineWidth: 1)
            }
    }
}
