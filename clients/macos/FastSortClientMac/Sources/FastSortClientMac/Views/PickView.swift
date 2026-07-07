import SwiftUI

struct PickView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pageActivation: PageActivationState
    @State private var activeTab: PickBatchTab = .current
    @State private var liveType = "0"
    @State private var currentBatches: [SortBatchItem] = []
    @State private var historyBatches: [SortBatchItem] = []
    @State private var selectedBatch: SortBatchItem?
    @State private var rows: [LiveTagItem] = []
    @State private var searchKey = ""
    @State private var pageIndex = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var historyPageIndex = 1
    @State private var historyPageSize = 10
    @State private var historyTotal = 0
    @State private var historyTotalPages = 1
    @State private var refreshIndexNumber = false
    @State private var pendingCompleteBatch: SortBatchItem?
    @State private var blacklistDraft = PickBlacklistDraft()
    @State private var toastText = ""
    @State private var isSubmittingBlacklist = false
    @State private var isLoadingBatches = false
    @State private var isLoadingRows = false
    @State private var errorText = ""
    @State private var hasLoaded = false

    private var displayBatches: [SortBatchItem] {
        activeTab == .current ? currentBatches : historyBatches
    }

    private var batchBaseIndex: Int {
        activeTab == .history ? (historyPageIndex - 1) * historyPageSize : 0
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(total) / Double(pageSize))))
    }

    private var canCompleteSelectedBatch: Bool {
        activeTab == .current
            && selectedBatch?.id?.isEmpty == false
            && (selectedBatch?.sortStatus?.value ?? "0") == "0"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        batchColumn
                            .frame(width: 300)
                            .frame(maxHeight: .infinity)
                        tagTable
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundStyle(FastSortTheme.danger)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 20)
                .macPagePadding()
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
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
        .confirmationDialog(
            "确认重置编号",
            isPresented: Binding(
                get: { pendingCompleteBatch != nil },
                set: { if !$0 { pendingCompleteBatch = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingCompleteBatch
        ) { batch in
            Button("确认", role: .destructive) {
                Task { await completeBatch(batch) }
            }
            Button("取消", role: .cancel) {
                pendingCompleteBatch = nil
            }
        } message: { _ in
            Text("确认将该批次完成并重置编号？")
        }
        .sheet(isPresented: Binding(
            get: { blacklistDraft.row != nil },
            set: { if !$0 { blacklistDraft = PickBlacklistDraft() } }
        )) {
            blacklistDialog
        }
        .task(id: pageActivation.isActive) {
            guard pageActivation.isActive, !hasLoaded else { return }
            guard await pageActivation.waitForFirstInteractiveFrame() else { return }
            await loadSortSetting()
            await loadBatches()
            hasLoaded = true
        }
    }

    private var batchModePicker: some View {
        MacChoiceGroup("", selection: Binding(
            get: { activeTab },
            set: { next in Task { await setBatchTab(next) } }
        ), options: [
            MacChoiceOption(label: "当前批次", value: PickBatchTab.current),
            MacChoiceOption(label: "历史批次", value: PickBatchTab.history)
        ], minItemWidth: 78)
        .frame(width: 164)
    }

    private var platformPicker: some View {
        MacChoiceGroup("", selection: Binding(
            get: { liveType },
            set: { next in Task { await setLiveType(next) } }
        ), options: PlatformCatalog.all.map { MacChoiceOption(label: $0.label, value: $0.liveType) }, minItemWidth: 62)
        .frame(width: 318)
    }

    private var tagToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                platformPicker
                Spacer(minLength: 16)
                searchControls
                    .frame(maxWidth: 640)
            }

            VStack(alignment: .leading, spacing: 12) {
                platformPicker
                searchControls
            }
        }
    }

    private var searchControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FastSortTheme.muted)
                TextField("搜索昵称/编号", text: $searchKey)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await searchRows() }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(FastSortTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(FastSortTheme.border, lineWidth: 1)
            }

            Button("搜索") {
                Task { await searchRows() }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var batchColumn: some View {
        GeometryReader { proxy in
            let listHeight = max(140, proxy.size.height - (activeTab == .history ? 148 : 80))
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Text(activeTab == .current ? "当前批次" : "历史批次")
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    batchModePicker
                }
                batchListHeader
                batchListContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(height: listHeight)
                    .layoutPriority(1)
                if activeTab == .history {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                        Text("历史共 \(historyTotal) 条，本页 \(historyBatches.count) 条")
                            .font(.system(size: 12))
                            .foregroundStyle(FastSortTheme.muted)
                        HStack(spacing: 8) {
                            Button {
                                Task { await changeBatchPage(historyPageIndex - 1) }
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .buttonStyle(AccentOutlineButtonStyle())
                            .help("上一页")
                            .disabled(historyPageIndex <= 1)
                            Text("\(historyPageIndex) / \(historyTotalPages)")
                                .font(.system(size: 12))
                                .foregroundStyle(FastSortTheme.muted)
                            MacSelect(selection: $historyPageSize, options: [
                                MacSelectOption(label: "10", value: 10),
                                MacSelectOption(label: "20", value: 20),
                                MacSelectOption(label: "50", value: 50)
                            ], width: 72)
                            .onChange(of: historyPageSize) { _, _ in
                                Task { await changeHistoryPageSize() }
                            }
                            Button {
                                Task { await changeBatchPage(historyPageIndex + 1) }
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(AccentOutlineButtonStyle())
                            .help("下一页")
                            .disabled(historyPageIndex >= historyTotalPages)
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(minHeight: 420)
        .webCard()
    }

    private var batchListHeader: some View {
        HStack(spacing: 10) {
            Text("序号")
                .frame(width: 36, alignment: .leading)
            Text("批次信息")
            Spacer()
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(FastSortTheme.muted)
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var batchListContent: some View {
        ZStack {
            if displayBatches.isEmpty {
                EmptyPanel(text: "暂无批次")
                    .opacity(isLoadingBatches ? 0 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 10) {
                        ForEach(Array(displayBatches.enumerated()), id: \.offset) { index, batch in
                            batchRow(batch, index: batchBaseIndex + index)
                        }
                    }
                }
                .scrollIndicators(.visible)
            }

            if isLoadingBatches {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FastSortTheme.surface.opacity(0.58))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func batchRow(_ batch: SortBatchItem, index: Int) -> some View {
        Button {
            Task { await selectBatch(batch) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FastSortTheme.muted)
                    .frame(width: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text(batch.batchName?.isEmpty == false ? batch.batchName! : "未命名批次")
                        .font(.system(size: 14, weight: .semibold))
                    Text(formatDate(batch.createdTime))
                        .font(.system(size: 12))
                        .foregroundStyle(FastSortTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedBatch?.id == batch.id ? FastSortTheme.accentSoft : FastSortTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .buttonStyle(.plain)
    }

    private var tagTable: some View {
        GeometryReader { proxy in
            let footerHeight: CGFloat = canCompleteSelectedBatch ? 94 : 56
            let listHeight = max(220, proxy.size.height - footerHeight - 98)
            VStack(alignment: .leading, spacing: 14) {
                tagToolbar

                ZStack {
                    if rows.isEmpty {
                        EmptyPanel(text: selectedBatch == nil ? "请选择批次" : "暂无标签明细")
                            .opacity(isLoadingRows ? 0 : 1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        tagTableScrollArea
                    }
                    if isLoadingRows {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(FastSortTheme.surface.opacity(0.58))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: listHeight)
                .layoutPriority(1)

                VStack(spacing: 10) {
                    Divider()
                    HStack {
                        Text("\(pageIndex) / \(totalPages)")
                            .font(.system(size: 12))
                            .foregroundStyle(FastSortTheme.muted)
                        Text("共 \(total) 条，本页 \(rows.count) 条")
                            .font(.system(size: 12))
                            .foregroundStyle(FastSortTheme.muted)
                        MacSelect(selection: $pageSize, options: [
                            MacSelectOption(label: "10 / 页", value: 10),
                            MacSelectOption(label: "20 / 页", value: 20),
                            MacSelectOption(label: "50 / 页", value: 50)
                        ], width: 110)
                        .onChange(of: pageSize) { _, _ in
                            Task { await changePageSize() }
                        }
                        Spacer()
                        Button("上一页") {
                            Task { await changePage(pageIndex - 1) }
                        }
                        .buttonStyle(AccentOutlineButtonStyle())
                        .disabled(pageIndex <= 1)
                        Button("下一页") {
                            Task { await changePage(pageIndex + 1) }
                        }
                        .buttonStyle(AccentOutlineButtonStyle())
                        .disabled(pageIndex >= totalPages)
                    }

                    if canCompleteSelectedBatch {
                        HStack {
                            Toggle("重置序号", isOn: $refreshIndexNumber)
                                .toggleStyle(.checkbox)
                            Spacer()
                            Button("重置编号") {
                                pendingCompleteBatch = selectedBatch
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(16)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(minHeight: 420)
        .webCard()
    }

    private var tagTableScrollArea: some View {
        GeometryReader { proxy in
            let tableWidth = max(proxy.size.width, 900)
            let headerHeight: CGFloat = 42
            ScrollView(.horizontal, showsIndicators: tableWidth > proxy.size.width + 1) {
                VStack(spacing: 0) {
                    tableHeader(width: tableWidth)
                        .frame(height: headerHeight)
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                tagTableRow(row, index: index, width: tableWidth)
                            }
                        }
                        .frame(width: tableWidth, alignment: .topLeading)
                    }
                    .scrollIndicators(.visible)
                    .frame(width: tableWidth, height: max(0, proxy.size.height - headerHeight), alignment: .topLeading)
                }
                .frame(width: tableWidth, height: proxy.size.height, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
        }
        .frame(minHeight: 260)
    }

    private var blacklistDialog: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("加入黑名单")
                        .font(.system(size: 22, weight: .bold))
                    Text(blacklistDraft.row?.orderName ?? "-")
                        .font(.system(size: 13))
                        .foregroundStyle(FastSortTheme.muted)
                }
                Spacer()
                Button {
                    blacklistDraft = PickBlacklistDraft()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconCircleButtonStyle())
            }

            MacChoiceGroup("", selection: $blacklistDraft.type, options: [
                MacChoiceOption(label: "恶意下单", value: "3"),
                MacChoiceOption(label: "跑单", value: "1")
            ], minItemWidth: 96)

            if blacklistDraft.type == "1" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("跑单金额")
                        .font(.system(size: 13, weight: .semibold))
                    TextField("请输入跑单金额", text: $blacklistDraft.runNumber)
                        .webTextInput()
                    Text("金额不可超过该用户当前总金额")
                        .font(.system(size: 12))
                        .foregroundStyle(FastSortTheme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.system(size: 13, weight: .semibold))
                TextEditor(text: $blacklistDraft.comment)
                    .frame(height: 110)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FastSortTheme.border)
                    }
            }

            HStack {
                Spacer()
                Button("取消") {
                    blacklistDraft = PickBlacklistDraft()
                }
                .buttonStyle(AccentOutlineButtonStyle())
                Button(isSubmittingBlacklist ? "提交中..." : "加入") {
                    Task { await submitBlacklist() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSubmittingBlacklist)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(FastSortTheme.background)
    }

    private func tableHeader(width: CGFloat) -> some View {
        let widths = pickColumnWidths(totalWidth: width)
        return HStack(spacing: 10) {
            tableCell("序号", width: widths[0], weight: .semibold)
            tableCell("昵称", width: widths[1], weight: .semibold)
            tableCell("编号", width: widths[2], weight: .semibold)
            tableCell("总金额", width: widths[3], weight: .semibold)
            tableCell("数量", width: widths[4], weight: .semibold)
            tableCell("创建时间", width: widths[5], weight: .semibold)
            tableCell("更新时间", width: widths[6], weight: .semibold)
            Text("操作")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FastSortTheme.muted)
                .frame(width: widths[7], alignment: .trailing)
        }
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FastSortTheme.border).frame(height: 1)
        }
    }

    private func tagTableRow(_ row: LiveTagItem, index: Int, width: CGFloat) -> some View {
        let widths = pickColumnWidths(totalWidth: width)
        return HStack(spacing: 10) {
            tableCell("\((pageIndex - 1) * pageSize + index + 1)", width: widths[0])
            tableCell(row.orderName ?? "-", width: widths[1], weight: .semibold)
            tableCell(row.orderNumber?.value ?? "-", width: widths[2])
            tableCell(row.orderAmounts?.value ?? "0", width: widths[3])
            tableCell(row.orderCount?.value ?? "0", width: widths[4])
            tableCell(formatDate(row.createdTime), width: widths[5])
            tableCell(formatDate(row.updatedTime), width: widths[6])
            Button(row.isBackList == true ? "已拉黑" : "加入黑名单") {
                openBlacklistDialog(row)
            }
            .buttonStyle(AccentOutlineButtonStyle())
            .disabled(row.isBackList == true)
            .frame(width: widths[7], alignment: .trailing)
        }
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FastSortTheme.border).frame(height: 1)
        }
    }

    private func pickColumnWidths(totalWidth: CGFloat) -> [CGFloat] {
        let base: [CGFloat] = [48, 140, 70, 80, 60, 130, 130, 120]
        let spacing: CGFloat = 10 * CGFloat(base.count - 1)
        let extra = max(0, totalWidth - base.reduce(0, +) - spacing)
        let weights: [CGFloat] = [0, 0.24, 0.08, 0.10, 0.08, 0.25, 0.25, 0]
        return zip(base, weights).map { width, weight in
            width + extra * weight
        }
    }

    private func tableCell(_ text: String, width: CGFloat, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.system(size: 12, weight: weight))
            .foregroundStyle(weight == .semibold ? FastSortTheme.text : FastSortTheme.muted)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }

    private func setBatchTab(_ tab: PickBatchTab) async {
        activeTab = tab
        selectedBatch = nil
        rows = []
        total = 0
        pageIndex = 1
        historyPageIndex = 1
        await loadBatches()
    }

    private func changeBatchPage(_ nextPage: Int) async {
        let safePage = min(max(1, nextPage), historyTotalPages)
        guard safePage != historyPageIndex else { return }
        historyPageIndex = safePage
        await loadBatches()
    }

    private func changeHistoryPageSize() async {
        historyPageIndex = 1
        await loadBatches()
    }

    private func setLiveType(_ value: String) async {
        liveType = value
        selectedBatch = nil
        rows = []
        total = 0
        pageIndex = 1
        historyPageIndex = 1
        await loadBatches()
    }

    private func selectBatch(_ batch: SortBatchItem) async {
        selectedBatch = batch
        pageIndex = 1
        await loadRows()
    }

    private func searchRows() async {
        pageIndex = 1
        await loadRows()
    }

    private func changePage(_ nextPage: Int) async {
        pageIndex = min(max(1, nextPage), totalPages)
        await loadRows()
    }

    private func changePageSize() async {
        pageIndex = 1
        await loadRows()
    }

    private func openBlacklistDialog(_ row: LiveTagItem) {
        guard row.isBackList != true else { return }
        blacklistDraft = PickBlacklistDraft(row: row)
    }

    private func showToast(_ message: String) {
        toastText = message
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run {
                if toastText == message {
                    toastText = ""
                }
            }
        }
    }

    private func submitBlacklist() async {
        guard let row = blacklistDraft.row else { return }
        let comment = blacklistDraft.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if comment.count > 1000 {
            showToast("备注不能超过 1000 字")
            return
        }
        var amount = "0"
        if blacklistDraft.type == "1" {
            guard !blacklistDraft.runNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showToast("请输入跑单金额")
                return
            }
            amount = blacklistDraft.runNumber
            let runAmount = Double(amount) ?? 0
            let totalAmount = Double(row.orderAmounts?.value ?? "0") ?? 0
            if runAmount > totalAmount {
                showToast("跑单金额不可超过总金额")
                return
            }
        }
        guard let tagId = row.tagId ?? row.id, !tagId.isEmpty else {
            showToast("缺少标签 ID")
            return
        }
        isSubmittingBlacklist = true
        defer { isSubmittingBlacklist = false }
        do {
            try await PickService(apiClient: appState.makeAPIClient()).addBlack(
                userId: appState.currentUserId,
                liveType: liveType,
                tagId: tagId,
                blackType: blacklistDraft.type,
                blackRemark: comment,
                skipBillAmount: amount
            )
            blacklistDraft = PickBlacklistDraft()
            showToast("已加入黑名单")
            await loadRows()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func completeBatch(_ batch: SortBatchItem) async {
        pendingCompleteBatch = nil
        guard let id = batch.id, !id.isEmpty else { return }
        do {
            try await PickService(apiClient: appState.makeAPIClient())
                .completeSortBatch(id: id, isRefreshIndexNumber: refreshIndexNumber)
            selectedBatch = nil
            rows = []
            total = 0
            showToast("已重置编号")
            await loadBatches()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadSortSetting() async {
        do {
            let result = try await PickService(apiClient: appState.makeAPIClient()).getSortSetting()
            refreshIndexNumber = result.isRefreshIndexNumber?.value == 1
        } catch {
            refreshIndexNumber = false
        }
    }

    private func loadBatches() async {
        guard !appState.currentUserId.isEmpty else {
            errorText = "缺少用户信息，请重新登录"
            return
        }
        isLoadingBatches = true
        errorText = ""
        defer { isLoadingBatches = false }
        do {
            let result = try await PickService(apiClient: appState.makeAPIClient())
                .getAllSortBatchList(
                    pageIndex: historyPageIndex,
                    pageSize: historyPageSize,
                    userId: appState.currentUserId,
                    liveType: liveType
                )
            currentBatches = result.notComplete.map { [$0] } ?? []
            let historyPage = result.historyCompletedPage
            historyTotal = historyPage?.totalValue ?? 0
            historyBatches = Array((historyPage?.list ?? []).prefix(historyPageSize))
            let calculatedHistoryPages = Int(ceil(Double(historyTotal) / Double(historyPageSize)))
            historyTotalPages = max(1, max(historyPage?.pagesValue ?? 0, calculatedHistoryPages))
            if historyPageIndex > historyTotalPages {
                historyPageIndex = historyTotalPages
                await loadBatches()
                return
            }
            if selectedBatch == nil {
                if activeTab == .current, let first = currentBatches.first {
                    await selectBatch(first)
                } else if activeTab == .history, let first = historyBatches.first {
                    await selectBatch(first)
                }
            }
        } catch {
            currentBatches = []
            historyBatches = []
            errorText = error.localizedDescription
        }
    }

    private func loadRows() async {
        guard let batchId = selectedBatch?.id, !batchId.isEmpty else {
            rows = []
            total = 0
            return
        }
        isLoadingRows = true
        errorText = ""
        defer { isLoadingRows = false }
        do {
            let result = try await PickService(apiClient: appState.makeAPIClient())
                .getLiveTags(
                    pageIndex: pageIndex,
                    pageSize: pageSize,
                    userId: appState.currentUserId,
                    sortBatchId: batchId,
                    searchKey: searchKey
                )
            rows = Array((result.list ?? []).prefix(pageSize))
            total = result.totalValue
        } catch {
            rows = []
            total = 0
            errorText = error.localizedDescription
        }
    }

    private func formatDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value
    }
}

enum PickBatchTab: Hashable {
    case current
    case history
}

struct PickBlacklistDraft {
    var row: LiveTagItem?
    var type = "1"
    var runNumber = ""
    var comment = ""
}
