import AppKit
import SwiftUI

struct BlacklistView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pageActivation: PageActivationState
    @State private var scope = "mine"
    @State private var searchKey = ""
    @State private var blackLevel = ""
    @State private var liveType = ""
    @State private var pageIndex = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var list: [BlacklistItem] = []
    @State private var selected: BlacklistItem?
    @State private var details: [BlacklistDetailItem] = []
    @State private var isLoading = false
    @State private var errorText = ""
    @State private var hasLoaded = false

    private var totalPages: Int {
        max(1, Int(ceil(Double(total) / Double(pageSize))))
    }

    var body: some View {
        GeometryReader { proxy in
            let panelHeight = max(420, proxy.size.height - 126)
            VStack(alignment: .leading, spacing: 14) {
                blacklistFilterToolbar

                HStack(alignment: .top, spacing: 16) {
                    listPanel
                        .frame(width: 380)
                        .frame(maxHeight: .infinity)
                    detailPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(height: panelHeight)
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
        .task(id: pageActivation.isActive) {
            guard pageActivation.isActive, !hasLoaded else { return }
            guard await pageActivation.waitForFirstInteractiveFrame() else { return }
            await loadBlacklist()
            hasLoaded = true
        }
    }

    private var blacklistFilterToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                blacklistScopeControl
                    .frame(width: 210)
                blacklistSearchFields
                Spacer(minLength: 12)
                blacklistSearchButton
            }

            VStack(alignment: .leading, spacing: 12) {
                blacklistScopeControl
                    .frame(width: 210)
                HStack(spacing: 10) {
                    blacklistSearchFields
                    Spacer(minLength: 0)
                    blacklistSearchButton
                }
            }
        }
        .padding(12)
        .webCard()
    }

    private var blacklistSearchFields: some View {
        HStack(spacing: 10) {
            TextField("搜索订单名", text: $searchKey)
                .webTextInput(width: 220)
                .onSubmit { Task { await search() } }
            MacSelect("等级", selection: $blackLevel, options: [
                MacSelectOption(label: "全部等级", value: "")
            ] + (1...5).map { level in
                MacSelectOption(label: "LV\(level)", value: "\(level)")
            }, width: 154)
            MacSelect("平台", selection: $liveType, options: [
                MacSelectOption(label: "全部平台", value: "")
            ] + PlatformCatalog.all.map { platform in
                MacSelectOption(label: platform.label, value: platform.liveType)
            }, width: 168)
        }
    }

    private var blacklistScopeControl: some View {
        MacChoiceGroup("", selection: Binding(
            get: { scope },
            set: { next in Task { await setScope(next) } }
        ), options: [
            MacChoiceOption(label: "我的黑名单", value: "mine"),
            MacChoiceOption(label: "全网黑名单", value: "global")
        ], minItemWidth: 88)
    }

    private var blacklistSearchButton: some View {
        Button("搜索") { Task { await search() } }
            .buttonStyle(PrimaryButtonStyle())
    }

    private var listPanel: some View {
        GeometryReader { proxy in
            let listHeight = max(190, proxy.size.height - 134)
            VStack(alignment: .leading, spacing: 12) {
                Text("黑名单列表")
                    .font(.system(size: 18, weight: .semibold))
                blacklistListHeader
                blacklistListContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(height: listHeight)
                    .layoutPriority(1)
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text("共 \(total) 条，本页 \(list.count) 条")
                        .font(.system(size: 12))
                        .foregroundStyle(FastSortTheme.muted)
                    HStack(spacing: 8) {
                        Text("\(pageIndex) / \(totalPages)")
                            .font(.system(size: 12))
                            .foregroundStyle(FastSortTheme.muted)
                        MacSelect(selection: $pageSize, options: [
                            MacSelectOption(label: "10", value: 10),
                            MacSelectOption(label: "20", value: 20),
                            MacSelectOption(label: "50", value: 50)
                        ], width: 72)
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
                }
            }
            .padding(16)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(minHeight: 420)
        .webCard()
    }

    private var blacklistListHeader: some View {
        HStack(spacing: 10) {
            Text("序号")
                .frame(width: 36, alignment: .leading)
            Text("黑名单信息")
            Spacer()
            Text("等级")
                .frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(FastSortTheme.muted)
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var blacklistListContent: some View {
        ZStack {
            if list.isEmpty {
                EmptyPanel(text: "暂无黑名单")
                    .opacity(isLoading ? 0 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 10) {
                        ForEach(Array(list.enumerated()), id: \.offset) { index, item in
                            Button {
                                Task { await select(item) }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\((pageIndex - 1) * pageSize + index + 1)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(FastSortTheme.muted)
                                        .frame(width: 36, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.orderName ?? "-")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("\(PlatformCatalog.label(for: item.liveType?.value ?? "")) · \(blackTypeLabel(item.blackType?.value)) · \(item.createdTime ?? "-")")
                                            .font(.system(size: 12))
                                            .foregroundStyle(FastSortTheme.muted)
                                    }
                                    Spacer()
                                    Text("LV\(item.blackLevel?.value ?? 1)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(FastSortTheme.accent)
                                        .frame(width: 44, alignment: .trailing)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected?.id == item.id ? FastSortTheme.accentSoft : FastSortTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.visible)
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FastSortTheme.surface.opacity(0.58))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("详情")
                .font(.system(size: 18, weight: .semibold))
            HStack(spacing: 12) {
                metric("等级", "LV\(selected?.blackLevel?.value ?? 0)")
                metric("跑单次数", "\(selected?.skipBillCount?.value ?? 0)")
                metric("恶意行为", "\(details.count)")
                metric("总跑单金额", selected?.skipBillAmount?.value ?? "0")
            }
            if details.isEmpty {
                EmptyPanel(text: selected == nil ? "请选择黑名单" : "暂无详情")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 10) {
                        ForEach(details) { detail in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(detail.orderName ?? "-")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("\(blackTypeLabel(detail.blackType?.value)) · 金额 \(detail.skipBillAmount?.value ?? "-")")
                                    .foregroundStyle(FastSortTheme.muted)
                                Text(detail.blackRemark ?? "-")
                                    .foregroundStyle(FastSortTheme.muted)
                                Text("\(detail.createdUser ?? "-") · \(detail.updatedTime ?? "-")")
                                    .font(.system(size: 12))
                                    .foregroundStyle(FastSortTheme.muted)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FastSortTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .webCard()
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(FastSortTheme.muted)
            Text(value).font(.system(size: 18, weight: .bold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FastSortTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func search() async {
        pageIndex = 1
        await loadBlacklist()
    }

    private func changePage(_ nextPage: Int) async {
        pageIndex = min(max(1, nextPage), totalPages)
        await loadBlacklist()
    }

    private func changePageSize() async {
        pageIndex = 1
        await loadBlacklist()
    }

    private func setScope(_ next: String) async {
        if next == "global", !appState.isPaidVip {
            errorText = "全网黑名单需要 VIP"
            return
        }
        scope = next
        pageIndex = 1
        await loadBlacklist()
    }

    private func loadBlacklist() async {
        isLoading = true
        errorText = ""
        defer { isLoading = false }
        do {
            let userId = scope == "mine" ? appState.currentUserId : nil
            let result = try await BlacklistService(apiClient: appState.makeAPIClient())
                .getBlackPage(pageIndex: pageIndex, pageSize: pageSize, userId: userId, orderName: searchKey, blackLevel: blackLevel, liveType: liveType)
            list = Array((result.list ?? []).prefix(pageSize))
            total = result.totalValue
            let calculatedPages = Int(ceil(Double(total) / Double(pageSize)))
            let pages = max(1, max(result.pagesValue, calculatedPages))
            if pageIndex > pages {
                pageIndex = pages
                await loadBlacklist()
                return
            }
            if let first = list.first {
                await select(first)
            } else {
                selected = nil
                details = []
            }
        } catch {
            list = []
            details = []
            total = 0
            errorText = error.localizedDescription
        }
    }

    private func select(_ item: BlacklistItem) async {
        selected = item
        guard let id = item.id else {
            details = item.blackDetailVoListde ?? item.blackDetailVoList ?? []
            return
        }
        do {
            let result = try await BlacklistService(apiClient: appState.makeAPIClient()).getBlackById(id)
            selected = result
            details = result.blackDetailVoListde ?? result.blackDetailVoList ?? []
        } catch {
            details = item.blackDetailVoListde ?? item.blackDetailVoList ?? []
        }
    }

    private func blackTypeLabel(_ value: String?) -> String {
        if value == "2" { return "跑单" }
        if value == "1" { return "恶意" }
        return value ?? "-"
    }
}

struct VipOrderView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pageActivation: PageActivationState
    @State private var activeStatus = "paid"
    @State private var orders: [VipOrderItem] = []
    @State private var pageIndex = 1
    @State private var pageSize = 20
    @State private var total = 0
    @State private var isLoading = false
    @State private var errorText = ""
    @State private var hasLoaded = false

    private let statuses = [
        VipStatusTab(key: "all", label: "全部", code: nil),
        VipStatusTab(key: "paid", label: "已支付", code: 1),
        VipStatusTab(key: "pending", label: "待支付", code: 0),
        VipStatusTab(key: "canceled", label: "已取消", code: 2),
        VipStatusTab(key: "failed", label: "支付失败", code: 3)
    ]

    private var totalPages: Int {
        max(1, Int(ceil(Double(total) / Double(pageSize))))
    }

    var body: some View {
        GeometryReader { proxy in
            let tableHeight = max(420, proxy.size.height - 44)
            let listHeight = max(220, tableHeight - 204)
            VStack(alignment: .leading, spacing: 14) {
                AdaptiveHorizontalTable(minimumWidth: 1120, minHeight: tableHeight) { tableWidth in
                    VStack(spacing: 0) {
                        vipOrderToolbar(width: tableWidth - 32)
                        orderHeader(width: tableWidth - 32)
                        vipOrderListContent(width: tableWidth - 32)
                            .frame(width: tableWidth - 32)
                            .frame(maxHeight: .infinity)
                            .frame(height: listHeight)
                            .layoutPriority(1)
                        vipOrderFooter(width: tableWidth - 32)
                    }
                    .padding(16)
                    .frame(width: tableWidth, height: tableHeight, alignment: .topLeading)
                    .webCard()
                }
                .frame(height: tableHeight)
                if !errorText.isEmpty {
                    Text(errorText).foregroundStyle(FastSortTheme.danger)
                }
            }
            .padding(.top, 20)
            .macPagePadding()
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .task(id: pageActivation.isActive) {
            guard pageActivation.isActive, !hasLoaded else { return }
            guard await pageActivation.waitForFirstInteractiveFrame() else { return }
            await loadOrders()
            hasLoaded = true
        }
    }

    private func vipOrderToolbar(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("订单列表")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FastSortTheme.text)
                Text("共 \(total) 条")
                    .font(.system(size: 12))
                    .foregroundStyle(FastSortTheme.muted)
            }
            Spacer(minLength: 16)
            MacChoiceGroup("订单状态", selection: Binding(
                get: { activeStatus },
                set: { next in Task { await setStatus(next) } }
            ), options: statuses.map { MacChoiceOption(label: $0.label, value: $0.key) }, minItemWidth: 64)
        }
        .frame(width: width, alignment: .leading)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FastSortTheme.border.opacity(0.75)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func vipOrderListContent(width: CGFloat) -> some View {
        ZStack {
            if orders.isEmpty {
                EmptyPanel(text: "暂无充值记录")
                    .opacity(isLoading ? 0 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(orders.enumerated()), id: \.offset) { index, order in
                            orderRow(order, index: index, width: width)
                        }
                    }
                }
                .scrollIndicators(.visible)
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FastSortTheme.surface.opacity(0.58))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func vipOrderFooter(width: CGFloat) -> some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 10) {
                Text("\(pageIndex) / \(totalPages)")
                    .font(.system(size: 12))
                    .foregroundStyle(FastSortTheme.muted)
                Text("共 \(total) 条，本页 \(orders.count) 条")
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
        }
        .frame(width: width, alignment: .leading)
    }

    private func orderHeader(width: CGFloat) -> some View {
        let widths = vipOrderColumnWidths(totalWidth: width)
        return HStack(spacing: 10) {
            cell("序号", widths[0], .semibold)
            cell("套餐", widths[1], .semibold)
            cell("时长", widths[2], .semibold)
            cell("开通方式", widths[3], .semibold)
            cell("开始时间", widths[4], .semibold)
            cell("结束时间", widths[5], .semibold)
            cell("支付金额", widths[6], .semibold)
            cell("状态", widths[7], .semibold)
            cell("创建时间", widths[8], .semibold)
        }
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(FastSortTheme.border).frame(height: 1) }
    }

    private func orderRow(_ order: VipOrderItem, index: Int, width: CGFloat) -> some View {
        let widths = vipOrderColumnWidths(totalWidth: width)
        return HStack(spacing: 10) {
            cell("\((pageIndex - 1) * pageSize + index + 1)", widths[0])
            cell(order.vipInfoName ?? "-", widths[1], .semibold)
            cell(order.vipInfoDuration?.value ?? "-", widths[2])
            cell(order.vipAddType ?? "充值", widths[3])
            cell(order.vipStartTime ?? "-", widths[4])
            cell(order.vipEndTime ?? "-", widths[5])
            cell("￥\(order.paymentPrice?.value ?? "-")", widths[6])
            cell(statusLabel(order.paymentStatus?.value), widths[7], .semibold)
            cell(order.createdTime ?? "-", widths[8])
        }
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(FastSortTheme.border).frame(height: 1) }
    }

    private func vipOrderColumnWidths(totalWidth: CGFloat) -> [CGFloat] {
        let base: [CGFloat] = [44, 150, 80, 90, 150, 150, 90, 80, 150]
        let spacing: CGFloat = 10 * CGFloat(base.count - 1)
        let extra = max(0, totalWidth - base.reduce(0, +) - spacing)
        let weights: [CGFloat] = [0, 0.20, 0.04, 0.07, 0.18, 0.18, 0.08, 0.05, 0.20]
        return zip(base, weights).map { width, weight in
            width + extra * weight
        }
    }

    private func cell(_ text: String, _ width: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.system(size: 12, weight: weight))
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .foregroundStyle(weight == .semibold ? FastSortTheme.text : FastSortTheme.muted)
    }

    private func setStatus(_ key: String) async {
        activeStatus = key
        pageIndex = 1
        await loadOrders()
    }

    private func changePage(_ nextPage: Int) async {
        let safePage = min(max(1, nextPage), totalPages)
        guard safePage != pageIndex else { return }
        pageIndex = safePage
        await loadOrders()
    }

    private func changePageSize() async {
        pageIndex = 1
        await loadOrders()
    }

    private func loadOrders() async {
        guard !appState.currentUserId.isEmpty else { return }
        isLoading = true
        errorText = ""
        defer { isLoading = false }
        do {
            let status = statuses.first { $0.key == activeStatus }?.code
            let result = try await VipService(apiClient: appState.makeAPIClient())
                .getPaymentOrders(pageIndex: pageIndex, pageSize: pageSize, userId: appState.currentUserId, paymentStatus: status)
            orders = Array((result.list ?? []).prefix(pageSize))
            total = result.totalValue
            let calculatedPages = Int(ceil(Double(total) / Double(pageSize)))
            let pages = max(1, max(result.pagesValue, calculatedPages))
            if pageIndex > pages {
                pageIndex = pages
                await loadOrders()
                return
            }
        } catch {
            orders = []
            total = 0
            errorText = error.localizedDescription
        }
    }

    private func statusLabel(_ code: Int?) -> String {
        switch code {
        case 1: return "已支付"
        case 2: return "已取消"
        case 3: return "支付失败"
        default: return "待支付"
        }
    }
}

private struct VipStatusTab: Identifiable {
    let key: String
    let label: String
    let code: Int?
    var id: String { key }
}

struct PaymentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pageActivation: PageActivationState
    @State private var plans: [VipInfoItem] = []
    @State private var selectedPlanId = ""
    @State private var isLoading = false
    @State private var message = ""
    @State private var hasLoaded = false

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    benefitsPanel
                    plansPanel
                }
                VStack(spacing: 16) {
                    benefitsPanel
                    plansPanel
                }
            }
            .padding(.top, 20)
            .macPagePadding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: pageActivation.isActive) {
            guard pageActivation.isActive, !hasLoaded else { return }
            guard await pageActivation.waitForFirstInteractiveFrame() else { return }
            await loadPlans()
            hasLoaded = true
        }
    }

    private var benefitsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("VIP 权益")
                .font(.system(size: 18, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                benefit("实时弹幕打印", "直播间弹幕识别后快速生成标签")
                benefit("共享编号", "跨平台理货批次统一编号")
                benefit("快速理货", "标签、黑名单、备注串联")
                benefit("自动重连", "直播和打印异常自动恢复")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .webCard()
    }

    private var plansPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("选择套餐")
                .font(.system(size: 18, weight: .semibold))
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(plans) { plan in
                    Button {
                        selectedPlanId = plan.id ?? ""
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(plan.vipName ?? "VIP")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("\(plan.duration?.value ?? 0) 个月")
                                    .foregroundStyle(FastSortTheme.muted)
                            }
                            Spacer()
                            Text("￥\(plan.discountedPrice?.value ?? plan.price?.value ?? "0")")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(FastSortTheme.accent)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedPlanId == plan.id ? FastSortTheme.accentSoft : FastSortTheme.groupedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .buttonStyle(.plain)
                }
            }
            Button("立即支付") {
                Task { await payNow() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedPlanId.isEmpty)
            Text("到期时间：\(appState.vipStatusText)")
                .font(.system(size: 12))
                .foregroundStyle(FastSortTheme.muted)
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(FastSortTheme.muted)
            }
        }
        .padding(16)
        .frame(width: 360)
        .webCard()
    }

    private func benefit(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(FastSortTheme.accent)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(desc).font(.system(size: 12)).foregroundStyle(FastSortTheme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FastSortTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func loadPlans() async {
        isLoading = true
        defer { isLoading = false }
        do {
            plans = try await VipService(apiClient: appState.makeAPIClient()).getVipInfoList()
            selectedPlanId = plans.first?.id ?? ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func payNow() async {
        do {
            let html = try await VipService(apiClient: appState.makeAPIClient()).createPcOrder(vipInfoId: selectedPlanId)
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("xunjian-pay-\(UUID().uuidString).html")
            try html.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(fileURL)
            message = "已打开支付宝支付页面"
        } catch {
            message = error.localizedDescription
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pageActivation: PageActivationState
    @State private var activeTab = "about"
    @State private var profile: ProfileResponse?
    @State private var nickname = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var newPhone = ""
    @State private var phoneCaptcha = ""
    @State private var cancelCaptcha = ""
    @State private var phoneCountdown = 0
    @State private var cancelCountdown = 0
    @State private var confirmDeleteAccount = false
    @State private var message = ""
    @State private var hasLoaded = false

    private let tabs = [
        ProfileTab(key: "about", label: "关于账号"),
        ProfileTab(key: "nickname", label: "修改昵称"),
        ProfileTab(key: "password", label: "修改密码"),
        ProfileTab(key: "phone", label: "修改手机号"),
        ProfileTab(key: "delete", label: "注销账号")
    ]

    private var countdownIsRunning: Bool {
        pageActivation.isActive && (phoneCountdown > 0 || cancelCountdown > 0)
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tabs) { tab in
                        Button {
                            activeTab = tab.key
                        } label: {
                            Text(tab.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(MacSidebarButtonStyle(active: activeTab == tab.key))
                    }
                }
                .padding(12)
                .frame(width: 180)
                .webCard()

                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.top, 20)
            .macPagePadding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: pageActivation.isActive) {
            guard pageActivation.isActive, !hasLoaded else { return }
            guard await pageActivation.waitForFirstInteractiveFrame() else { return }
            await loadProfile()
            hasLoaded = true
        }
        .task(id: countdownIsRunning) {
            guard countdownIsRunning else { return }
            while !Task.isCancelled && countdownIsRunning {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, countdownIsRunning else { return }
                if phoneCountdown > 0 { phoneCountdown -= 1 }
                if cancelCountdown > 0 { cancelCountdown -= 1 }
            }
        }
        .confirmationDialog("确认注销账号", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("确认注销", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("注销后当前账号将无法继续使用，请确认验证码已填写正确。")
        }
    }

    @ViewBuilder private var content: some View {
        if activeTab == "about" {
            card {
                info("昵称", profile?.user?.displayName ?? appState.profileName)
                info("手机号", profile?.user?.phone ?? "-")
                info("VIP 状态", appState.vipStatusText)
                info("邀请码", profile?.vip?.invitationCode ?? "-")
                info("联系邮箱", "dh_technology@163.com")
                info("备案", "苏ICP备2025175795号-1A")
                Button("检查更新") { Task { await loadProfile() } }
                    .buttonStyle(AccentOutlineButtonStyle())
            }
        } else if activeTab == "nickname" {
            card {
                TextField("输入新昵称", text: $nickname)
                    .webTextInput(width: 320)
                Button("保存") { Task { await saveNickname() } }
                    .buttonStyle(PrimaryButtonStyle())
            }
        } else if activeTab == "password" {
            card {
                SecureField("输入新密码", text: $newPassword)
                    .webTextInput(width: 320)
                SecureField("确认新密码", text: $confirmPassword)
                    .webTextInput(width: 320)
                Button("保存") { Task { await savePassword() } }
                    .buttonStyle(PrimaryButtonStyle())
            }
        } else if activeTab == "phone" {
            card {
                info("当前手机号", profile?.user?.phone ?? profile?.user?.username ?? "-")
                TextField("输入新手机号", text: $newPhone)
                    .webTextInput(width: 320)
                HStack {
                    TextField("输入验证码", text: $phoneCaptcha)
                        .webTextInput(width: 200)
                    Button(phoneCountdown > 0 ? "\(phoneCountdown)s" : "发送验证码") {
                        Task { await sendPhoneCaptcha() }
                    }
                    .buttonStyle(AccentOutlineButtonStyle())
                    .disabled(phoneCountdown > 0)
                }
                Button("保存") { Task { await savePhone() } }
                    .buttonStyle(PrimaryButtonStyle())
            }
        } else if activeTab == "delete" {
            card {
                info("手机号", profile?.user?.phone ?? profile?.user?.username ?? "-")
                HStack {
                    TextField("输入验证码", text: $cancelCaptcha)
                        .webTextInput(width: 200)
                    Button(cancelCountdown > 0 ? "\(cancelCountdown)s" : "发送验证码") {
                        Task { await sendCancelCaptcha() }
                    }
                    .buttonStyle(AccentOutlineButtonStyle())
                    .disabled(cancelCountdown > 0)
                }
                Button("注销账号") {
                    confirmDeleteAccount = true
                }
                .buttonStyle(AccentOutlineButtonStyle())
                .foregroundStyle(FastSortTheme.danger)
            }
        } else {
            card {
                Text("请选择个人中心功能。")
                    .foregroundStyle(FastSortTheme.muted)
            }
        }
        if !message.isEmpty {
            Text(message).font(.system(size: 13)).foregroundStyle(FastSortTheme.muted)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .webCard()
    }

    private func info(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(FastSortTheme.muted).frame(width: 90, alignment: .leading)
            Text(value).font(.system(size: 14, weight: .semibold))
        }
    }

    private func loadProfile() async {
        do {
            profile = try await ProfileService(apiClient: appState.makeAPIClient()).getProfile()
            nickname = profile?.user?.displayName ?? ""
            message = ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveNickname() async {
        guard !appState.currentUserId.isEmpty, !nickname.isEmpty else { return }
        do {
            try await ProfileService(apiClient: appState.makeAPIClient()).updateNickname(userId: appState.currentUserId, nickname: nickname)
            await loadProfile()
            message = "昵称已更新"
        } catch {
            message = error.localizedDescription
        }
    }

    private func savePassword() async {
        guard !appState.currentUserId.isEmpty else { return }
        guard !newPassword.isEmpty else {
            message = "请输入新密码"
            return
        }
        guard newPassword == confirmPassword else {
            message = "两次密码不一致"
            return
        }
        guard (6...20).contains(newPassword.count), newPassword.canBeConverted(to: .isoLatin1) else {
            message = "密码需为 6-20 位半角字符"
            return
        }
        do {
            try await ProfileService(apiClient: appState.makeAPIClient())
                .updatePassword(userId: appState.currentUserId, password: newPassword)
            message = "密码已更新，请重新登录"
            newPassword = ""
            confirmPassword = ""
            await appState.logout()
        } catch {
            message = error.localizedDescription
        }
    }

    private func sendPhoneCaptcha() async {
        guard !newPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请输入新手机号"
            return
        }
        if newPhone == (profile?.user?.phone ?? profile?.user?.username ?? "") {
            message = "新手机号不能与当前手机号相同"
            return
        }
        do {
            try await ProfileService(apiClient: appState.makeAPIClient()).generateCaptcha(phone: newPhone, captchaType: "2")
            phoneCountdown = 60
            message = "验证码已发送"
        } catch {
            message = error.localizedDescription
        }
    }

    private func savePhone() async {
        guard !appState.currentUserId.isEmpty else { return }
        guard !newPhone.isEmpty, !phoneCaptcha.isEmpty else {
            message = "请输入手机号和验证码"
            return
        }
        do {
            try await ProfileService(apiClient: appState.makeAPIClient())
                .updatePhone(userId: appState.currentUserId, phone: newPhone, captcha: phoneCaptcha)
            message = "手机号已更新，请重新登录"
            newPhone = ""
            phoneCaptcha = ""
            await appState.logout()
        } catch {
            message = error.localizedDescription
        }
    }

    private func sendCancelCaptcha() async {
        let phone = profile?.user?.phone ?? profile?.user?.username ?? ""
        guard !phone.isEmpty else { return }
        do {
            try await ProfileService(apiClient: appState.makeAPIClient()).generateCaptcha(phone: phone, captchaType: "3")
            cancelCountdown = 60
            message = "验证码已发送"
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        let phone = profile?.user?.phone ?? profile?.user?.username ?? ""
        guard !phone.isEmpty, !cancelCaptcha.isEmpty else {
            message = "请输入验证码"
            return
        }
        do {
            try await ProfileService(apiClient: appState.makeAPIClient())
                .accountCancel(phone: phone, captcha: cancelCaptcha)
            message = "账号已注销"
            cancelCaptcha = ""
            await appState.logout()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct ProfileTab: Identifiable {
    let key: String
    let label: String
    var id: String { key }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pageActivation: PageActivationState
    var openPrinterTest: () -> Void = {}
    @State private var activeTab = "live-room"
    @State private var rooms: [RoomListItem] = []
    @State private var tagTemplates: [TagTemplateItem] = []
    @State private var danmuTemplates: [DanmuTemplateItem] = []
    @State private var mappings: [DanmuMappingItem] = []
    @State private var sortSetting: SortSettingResponse?
    @State private var blackSetting: BlacklistUserSettingResponse?
    @State private var message = ""
    @State private var hasLoaded = false

    private let tabs = [
        SettingTab(key: "live-room", label: "直播间设置"),
        SettingTab(key: "template", label: "标签模板"),
        SettingTab(key: "comment", label: "弹幕模板"),
        SettingTab(key: "danmu-mapping", label: "弹幕映射"),
        SettingTab(key: "pick-end", label: "理货端设置"),
        SettingTab(key: "blacklist", label: "黑名单设置")
    ]

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        Button {
                            activeTab = tab.key
                        } label: {
                            Text(tab.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(MacSidebarButtonStyle(active: activeTab == tab.key))
                    }
                    Divider().padding(.vertical, 8)
                    Button("打开打印测试") {
                        openPrinterTest()
                    }
                    .buttonStyle(AccentOutlineButtonStyle())
                }
                .padding(16)
                .frame(width: 190)
                .webCard()

                settingsContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.top, 20)
            .macPagePadding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: pageActivation.isActive) {
            guard pageActivation.isActive, !hasLoaded else { return }
            guard await pageActivation.waitForFirstInteractiveFrame() else { return }
            await loadSettings()
            hasLoaded = true
        }
    }

    @ViewBuilder private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tabs.first { $0.key == activeTab }?.label ?? "设置")
                .font(.system(size: 18, weight: .semibold))
            if activeTab == "live-room" {
                ForEach(rooms) { room in
                    roomRow(room)
                }
                if rooms.isEmpty { EmptyPanel(text: "暂无直播间") }
            } else if activeTab == "template" {
                HStack {
                    Text("模板数量：\(tagTemplates.count)")
                    Spacer()
                    Button("新增模板") {}
                        .buttonStyle(AccentOutlineButtonStyle())
                }
                ForEach(tagTemplates) { template in listLine(template.tagTemplateName ?? "未命名模板", template.id ?? "-") }
            } else if activeTab == "comment" {
                ForEach(danmuTemplates) { item in listLine(item.danmuTemplateName ?? "未命名弹幕模板", item.id ?? "-") }
                if danmuTemplates.isEmpty { EmptyPanel(text: "暂无弹幕模板") }
            } else if activeTab == "danmu-mapping" {
                ForEach(mappings) { item in listLine(item.danmuMappingName ?? "未命名映射", item.danmuMappingElement ?? "-") }
                if mappings.isEmpty { EmptyPanel(text: "暂无弹幕映射") }
            } else if activeTab == "pick-end" {
                listLine("是否完成后重置编号", sortSetting?.isRefreshIndexNumber?.value == 1 ? "是" : "否")
                listLine("货架编号区间", sortSetting?.shelfNumberRange ?? "-")
            } else {
                listLine("打印过滤黑名单", blackSetting?.isPrintFlag?.value == 1 ? "开启" : "只过滤我的黑名单")
                listLine("全局等级阈值", "LV\(blackSetting?.blackLevel?.value ?? 1)")
            }
            if !message.isEmpty {
                Text(message).font(.system(size: 13)).foregroundStyle(FastSortTheme.danger)
            }
        }
        .padding(16)
        .webCard()
    }

    private func roomRow(_ room: RoomListItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(room.displayName).font(.system(size: 14, weight: .semibold))
                Text("\(PlatformCatalog.label(for: room.liveType?.value ?? "0")) · \(room.handle)")
                    .font(.system(size: 12))
                    .foregroundStyle(FastSortTheme.muted)
            }
            Spacer()
            Button("配置") {}
                .buttonStyle(AccentOutlineButtonStyle())
        }
        .padding(12)
        .background(FastSortTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func listLine(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(FastSortTheme.muted).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FastSortTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func loadSettings() async {
        guard !appState.currentUserId.isEmpty else { return }
        let service = SettingsService(apiClient: appState.makeAPIClient())
        do {
            async let roomResult = service.getRooms(userId: appState.currentUserId)
            async let tagResult = service.getTagTemplates(userId: appState.currentUserId)
            async let danmuResult = service.getDanmuTemplates()
            async let mappingResult = service.getDanmuMappings(userId: appState.currentUserId)
            async let sortResult = service.getSortSetting()
            async let blackResult = service.getBlackUserSetting(userId: appState.currentUserId)
            rooms = try await roomResult
            let tagPage = try await tagResult
            tagTemplates = tagPage.list ?? []
            danmuTemplates = try await danmuResult
            let mappingPage = try await mappingResult
            mappings = mappingPage.list ?? []
            sortSetting = try await sortResult
            blackSetting = try await blackResult
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct SettingTab: Identifiable {
    let key: String
    let label: String
    var id: String { key }
}

struct EntertainmentModeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pageActivation: PageActivationState
    @State private var rooms: [RoomListItem] = []
    @State private var selectedRoom: RoomListItem?
    @State private var roomSearch = ""
    @State private var activeFilter = "all"
    @State private var printOptions: Set<String> = ["gift", "member", "like"]
    @State private var voiceOptions: Set<String> = ["gift"]
    @State private var socketStatus = "idle"
    @State private var roomStatusText = "未连接"
    @State private var liveRecordId = ""
    @State private var events: [EntertainmentEventItem] = []
    @State private var pendingEvents: [EntertainmentEventItem] = []
    @State private var giftStats: [String: EntertainmentGiftStat] = [:]
    @State private var seenEventIds = Set<String>()
    @State private var socketSession: DanmakuWebSocketSession?
    @State private var socketLoopTask: Task<Void, Never>?
    @State private var heartbeatTask: Task<Void, Never>?
    @State private var message = ""
    @State private var hasLoaded = false

    private var douyinRooms: [RoomListItem] {
        let needle = roomSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return rooms.filter { ($0.liveType?.value ?? "0") == "0" }
            .filter { room in
                needle.isEmpty
                    || room.displayName.localizedCaseInsensitiveContains(needle)
                    || (room.roomNumber ?? "").localizedCaseInsensitiveContains(needle)
            }
    }

    private var visibleEvents: [EntertainmentEventItem] {
        activeFilter == "all" ? events : events.filter { $0.type == activeFilter }
    }

    private var statusColor: Color {
        switch socketStatus {
        case "open": return FastSortTheme.success
        case "connecting": return FastSortTheme.accent
        case "error": return FastSortTheme.danger
        default: return FastSortTheme.muted
        }
    }

    private var statusLabel: String {
        switch socketStatus {
        case "open": return "已连接"
        case "connecting": return "连接中"
        case "error": return "连接异常"
        case "closed": return "已关闭"
        default: return "未连接"
        }
    }

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    roomsPanel
                    entertainmentWorkspace
                }
                VStack(spacing: 16) {
                    roomsPanel
                    entertainmentWorkspace
                }
            }
            .padding(.top, 20)
            .macPagePadding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: pageActivation.isActive) {
            guard pageActivation.isActive, !hasLoaded else { return }
            guard await pageActivation.waitForFirstInteractiveFrame() else { return }
            await loadRooms()
            hasLoaded = true
        }
        .onChange(of: pageActivation.isActive) { _, isActive in
            guard isActive else { return }
            flushPendingEntertainmentEvents()
        }
        .onDisappear {
            closeEntertainmentSocket(clearRecord: false)
        }
    }

    private var roomsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("直播间")
                        .font(.system(size: 18, weight: .semibold))
                    Text("\(douyinRooms.count) 个房间")
                        .font(.system(size: 12))
                        .foregroundStyle(FastSortTheme.muted)
                }
                Spacer()
            }
            Text("如需新增娱乐房间，请先在直播间页添加抖音房间并保存登录 Cookie。")
                .font(.system(size: 12))
                .foregroundStyle(FastSortTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("搜索名称或房间号", text: $roomSearch)
                .webTextInput()
            ForEach(douyinRooms) { room in
                entertainmentRoomRow(room)
            }
            if douyinRooms.isEmpty {
                EmptyPanel(text: "暂无可用抖音房间")
            }
        }
        .padding(16)
        .frame(width: 300)
        .webCard()
    }

    private var entertainmentWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    roomStatusPanel
                    controlPanel
                }
                VStack(spacing: 16) {
                    roomStatusPanel
                    controlPanel
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            messagePanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var roomStatusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前房间").font(.system(size: 12)).foregroundStyle(FastSortTheme.muted)
                    Text(selectedRoom?.displayName ?? "请选择直播间")
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                statusPill(statusLabel, color: statusColor)
            }
            HStack(spacing: 12) {
                metric("平台", "抖音")
                metric("房间号", selectedRoom?.roomNumber ?? "-")
                metric("礼物种类", "\(giftStats.count)")
                metric("状态", roomStatusText)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("互动输出")
                    .font(.system(size: 14, weight: .semibold))
                ForEach(EntertainmentOutputOption.all) { option in
                    HStack {
                        Text(option.label).frame(width: 60, alignment: .leading)
                        Toggle("打印", isOn: outputBinding(option.key, target: .print))
                            .toggleStyle(.checkbox)
                        Toggle("播报", isOn: outputBinding(option.key, target: .voice))
                            .toggleStyle(.checkbox)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .webCard()
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("控制").font(.system(size: 18, weight: .semibold))
            Button(liveRecordId.isEmpty ? "进入直播间" : "断开直播间") {
                Task {
                    if liveRecordId.isEmpty {
                        if let selectedRoom { await enterRoom(selectedRoom) }
                    } else {
                        await leaveRoom()
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedRoom == nil || socketStatus == "connecting")
            Button("清空弹幕区域") {
                events = []
                pendingEvents = []
                giftStats = [:]
                seenEventIds = []
            }
            .buttonStyle(AccentOutlineButtonStyle())
            Button("测试播报") {
                message = "这是一条测试播报，感谢迅拣测试送出1个小心心"
            }
            .buttonStyle(AccentOutlineButtonStyle())
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(FastSortTheme.muted)
            }
        }
        .padding(16)
        .frame(width: 260)
        .webCard()
    }

    private var messagePanel: some View {
        VStack(spacing: 0) {
            HStack {
                statusPill(socketStatus == "open" ? "弹幕已开启" : "弹幕已断开", color: statusColor)
                Spacer()
                MacChoiceGroup("消息类型", selection: $activeFilter, options: EntertainmentEventFilter.all.map { MacChoiceOption(label: $0.label, value: $0.key) }, minItemWidth: 48)
                    .frame(width: 340)
            }
            .padding(18)
            .overlay(alignment: .bottom) {
                Rectangle().fill(FastSortTheme.border).frame(height: 1)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if visibleEvents.isEmpty {
                            EmptyPanel(text: socketStatus == "open" ? "等待直播间消息" : "进入直播间后显示弹幕、进房、点赞和礼物")
                                .padding(20)
                        } else {
                            ForEach(visibleEvents) { item in
                                entertainmentEventRow(item)
                                    .id(item.id)
                            }
                        }
                    }
                }
                .frame(minHeight: 360)
                .onChange(of: events.count) { _, _ in
                    guard pageActivation.isActive else { return }
                    guard let last = visibleEvents.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .webCard()
    }

    private func entertainmentRoomRow(_ room: RoomListItem) -> some View {
        HStack(spacing: 10) {
            Button {
                selectedRoom = room
            } label: {
                HStack(spacing: 10) {
                    roomAvatar(room)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(room.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FastSortTheme.text)
                            .lineLimit(1)
                        Text(room.handle)
                            .font(.system(size: 12))
                            .foregroundStyle(FastSortTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task {
                    if selectedRoom?.id == room.id, !liveRecordId.isEmpty {
                        await leaveRoom()
                    } else {
                        selectedRoom = room
                        await enterRoom(room)
                    }
                }
            } label: {
                Image(systemName: selectedRoom?.id == room.id && !liveRecordId.isEmpty ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FastSortTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(FastSortTheme.accentSoft)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 38, height: 38)
            .contentShape(Circle())
        }
        .padding(12)
        .background(selectedRoom?.id == room.id ? FastSortTheme.accentSoft : FastSortTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func entertainmentEventRow(_ item: EntertainmentEventItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(item.userInitial)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FastSortTheme.accent)
                .frame(width: 34, height: 34)
                .background(FastSortTheme.accentSoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.userName)
                        .font(.system(size: 14, weight: .semibold))
                    statusPill(item.typeLabel, color: item.tint)
                    Text(item.time)
                        .font(.system(size: 12))
                        .foregroundStyle(FastSortTheme.muted)
                }
                if !item.text.isEmpty {
                    Text(item.text)
                        .foregroundStyle(FastSortTheme.text)
                }
                if !item.giftName.isEmpty {
                    Text("送出 \(item.giftName) x\(item.giftCount)\(item.giftDiamond > 0 ? " · \(item.giftDiamond) 抖币" : "")")
                        .foregroundStyle(FastSortTheme.muted)
                }
                if !item.extra.isEmpty {
                    Text(item.extra)
                        .font(.system(size: 12))
                        .foregroundStyle(FastSortTheme.muted)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(item.tint.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(FastSortTheme.border.opacity(0.6)).frame(height: 1)
        }
    }

    private func roomAvatar(_ room: RoomListItem) -> some View {
        ZStack {
            if let url = room.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Text(String(room.displayName.prefix(1)))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(FastSortTheme.accent)
                    }
                }
            } else {
                Text(String(room.displayName.prefix(1)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(FastSortTheme.accent)
            }
        }
        .frame(width: 42, height: 42)
        .background(FastSortTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(FastSortTheme.muted)
            Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FastSortTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func outputBinding(_ key: String, target: EntertainmentOutputTarget) -> Binding<Bool> {
        Binding {
            switch target {
            case .print: return printOptions.contains(key)
            case .voice: return voiceOptions.contains(key)
            }
        } set: { isOn in
            switch target {
            case .print:
                if isOn { printOptions.insert(key) } else { printOptions.remove(key) }
            case .voice:
                if isOn { voiceOptions.insert(key) } else { voiceOptions.remove(key) }
            }
        }
    }

    private func loadRooms() async {
        guard !appState.currentUserId.isEmpty else { return }
        do {
            rooms = try await LiveRoomsService(apiClient: appState.makeAPIClient()).queryRoomsByUserId(appState.currentUserId)
            selectedRoom = rooms.first { ($0.liveType?.value ?? "0") == "0" }
        } catch {
            message = error.localizedDescription
        }
    }

    private func enterRoom(_ room: RoomListItem) async {
        guard let roomId = room.id else { return }
        do {
            let result = try await LiveRoomsService(apiClient: appState.makeAPIClient())
                .startLive(userId: appState.currentUserId, userRoomId: roomId, liveTitle: room.displayName)
            liveRecordId = result.id ?? ""
            selectedRoom = room
            events = []
            pendingEvents = []
            giftStats = [:]
            seenEventIds = []
            connectEntertainmentSocket(room)
        } catch {
            message = error.localizedDescription
        }
    }

    private func leaveRoom() async {
        let id = liveRecordId
        closeEntertainmentSocket(clearRecord: true)
        guard !id.isEmpty else { return }
        try? await LiveRoomsService(apiClient: appState.makeAPIClient()).finishLive(id: id)
    }

    private func connectEntertainmentSocket(_ room: RoomListItem) {
        closeEntertainmentSocket(clearRecord: false)
        guard let url = entertainmentSocketURL(for: room) else {
            socketStatus = "error"
            roomStatusText = "信息不完整"
            return
        }
        socketStatus = "connecting"
        roomStatusText = "连接中"
        let session = DanmakuWebSocketSession()
        socketSession = session
        socketLoopTask = Task {
            do {
                try await session.run(
                    request: URLRequest(url: url),
                    onOpen: {},
                    onMessage: { message in
                        guard socketSession === session else { return }
                        handleEntertainmentSocketMessage(message)
                    }
                )
            } catch {
                guard socketSession === session else { return }
                socketStatus = "error"
                roomStatusText = "已断开"
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
                    roomStatusText = "直播中"
                }
            }
        }
    }

    private func closeEntertainmentSocket(clearRecord: Bool) {
        socketLoopTask?.cancel()
        socketLoopTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socketSession?.cancel()
        socketSession = nil
        socketStatus = "idle"
        roomStatusText = "未连接"
        if clearRecord {
            liveRecordId = ""
        }
    }

    private func handleEntertainmentSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        guard let text = DanmakuSocketMessageParser.text(from: message), !text.isEmpty else { return }
        if let status = DanmakuSocketMessageParser.status(fromText: text) {
            handleEntertainmentSocketStatus(status)
            return
        }
        guard
            let data = text.data(using: .utf8),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let statusEvent = payload["event"] as? String, statusEvent == "status" {
            roomStatusText = "\(payload["status"] ?? "-")"
            return
        }
        guard let item = normalizeEntertainmentEvent(payload) else { return }
        guard !seenEventIds.contains(item.id) else { return }
        seenEventIds.insert(item.id)
        appendEntertainmentEventForCurrentVisibility(item)
        if item.type == "gift" {
            let key = item.giftId.isEmpty ? item.giftName : item.giftId
            if !key.isEmpty {
                let current = giftStats[key] ?? EntertainmentGiftStat(name: item.giftName, count: 0)
                giftStats[key] = EntertainmentGiftStat(name: current.name.isEmpty ? item.giftName : current.name, count: current.count + item.giftCount)
            }
        }
    }

    private func handleEntertainmentSocketStatus(_ status: DanmakuSocketTextStatus) {
        switch status {
        case .pong:
            break
        case .living:
            socketStatus = "open"
            roomStatusText = "直播中"
        case .connecting:
            roomStatusText = "连接中"
        case .disconnected:
            socketStatus = "error"
            roomStatusText = "已断开"
        case .loginExpired:
            socketStatus = "error"
            roomStatusText = "登录失效"
        case .stopped, .ended:
            socketStatus = "closed"
            roomStatusText = "直播已结束"
        case .paused:
            roomStatusText = "暂停"
        case .notStarted:
            roomStatusText = "未开播"
        }
    }

    private func appendEntertainmentEventForCurrentVisibility(_ item: EntertainmentEventItem) {
        if pageActivation.isActive {
            events = Array((events + [item]).suffix(120))
        } else {
            pendingEvents = Array((pendingEvents + [item]).suffix(120))
        }
    }

    private func flushPendingEntertainmentEvents() {
        guard !pendingEvents.isEmpty else { return }
        events = Array((events + pendingEvents).suffix(120))
        pendingEvents = []
    }

    private func normalizeEntertainmentEvent(_ payload: [String: Any]) -> EntertainmentEventItem? {
        let type = "\(payload["event"] ?? "unknown")"
        let data = payload["data"] as? [String: Any] ?? [:]
        let rawData = payload["rawData"] as? [String: Any] ?? [:]
        let user = payload["user"] as? [String: Any] ?? [:]
        let userName = "\(user["nickName"] ?? user["nickname"] ?? "游客")"
        let eventId = "\(payload["eventId"] ?? payload["dyMsgId"] ?? UUID().uuidString)"
        let baseText: String
        var giftName = ""
        var giftId = ""
        var giftCount = 1
        var giftDiamond = 0
        switch type {
        case "chat":
            baseText = "\(data["content"] ?? "")"
        case "member":
            baseText = "\(userName) 进入直播间"
        case "like":
            baseText = "\(userName) 点赞 \(data["count"] ?? 1) 次"
        case "gift":
            giftName = "\(data["giftName"] ?? rawData["giftName"] ?? "礼物")"
            giftId = "\(data["giftId"] ?? rawData["giftId"] ?? "")"
            giftCount = Int("\(data["repeatCount"] ?? data["comboCount"] ?? data["totalCount"] ?? 1)") ?? 1
            giftDiamond = Int("\(data["diamondCount"] ?? 0)") ?? 0
            baseText = ""
        default:
            baseText = extractReadableEntertainmentText(payload) ?? "\(payload["method"] ?? "收到直播间消息")"
        }
        return EntertainmentEventItem(
            id: eventId,
            type: normalizeEntertainmentType(type),
            typeLabel: entertainmentTypeLabel(type),
            userName: userName,
            userInitial: String(userName.prefix(1)),
            time: formatEntertainmentTime(payload["createTime"]),
            text: baseText,
            extra: "\(payload["method"] ?? "")",
            giftId: giftId,
            giftName: giftName,
            giftCount: max(1, giftCount),
            giftDiamond: giftDiamond
        )
    }

    private func normalizeEntertainmentType(_ type: String) -> String {
        if ["chat", "member", "like", "gift"].contains(type) { return type }
        if ["social", "fansclub", "common_text", "reward_event", "interactive_event"].contains(type) { return "social" }
        if ["room_rank", "room_user_seq", "rank_event"].contains(type) { return "rank" }
        return "system"
    }

    private func entertainmentTypeLabel(_ type: String) -> String {
        switch normalizeEntertainmentType(type) {
        case "chat": return "弹幕"
        case "member": return "进房"
        case "like": return "点赞"
        case "gift": return "礼物"
        case "social": return "互动"
        case "rank": return "榜单"
        default: return "系统"
        }
    }

    private func extractReadableEntertainmentText(_ payload: [String: Any]) -> String? {
        let data = payload["data"] as? [String: Any] ?? [:]
        for key in ["content", "text", "displayText", "description", "title"] {
            if let value = data[key], !(value is NSNull), !"\(value)".isEmpty {
                return "\(value)"
            }
        }
        return nil
    }

    private func formatEntertainmentTime(_ value: Any?) -> String {
        let raw = Double("\(value ?? "")") ?? Date().timeIntervalSince1970
        let seconds = raw > 1_000_000_000_000 ? raw / 1000 : raw
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private func entertainmentSocketURL(for room: RoomListItem) -> URL? {
        guard let roomNumber = room.roomNumber, !roomNumber.isEmpty else { return nil }
        let cookie = DanmakuCookieSessionParser.cookieHeader(fromLiveSession: room.liveSession)
        let queryItems = cookie.isEmpty
            ? []
            : [URLQueryItem(name: "cookie_b64", value: Data(cookie.utf8).base64EncodedString())]
        return DanmakuLocalConnectionBuilder.webSocketURL(
            portKey: "douyin",
            defaultPort: 8865,
            path: "/ws/events/\(DanmakuLocalConnectionBuilder.pathComponent(roomNumber))",
            queryItems: queryItems
        )
    }

    private static func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private enum EntertainmentOutputTarget {
    case print
    case voice
}

private struct EntertainmentOutputOption: Identifiable {
    let key: String
    let label: String
    var id: String { key }

    static let all = [
        EntertainmentOutputOption(key: "chat", label: "弹幕"),
        EntertainmentOutputOption(key: "member", label: "进房"),
        EntertainmentOutputOption(key: "like", label: "点赞"),
        EntertainmentOutputOption(key: "gift", label: "送礼")
    ]
}

private struct EntertainmentEventFilter: Identifiable {
    let key: String
    let label: String
    var id: String { key }

    static let all = [
        EntertainmentEventFilter(key: "all", label: "全部"),
        EntertainmentEventFilter(key: "chat", label: "弹幕"),
        EntertainmentEventFilter(key: "member", label: "进房"),
        EntertainmentEventFilter(key: "gift", label: "礼物"),
        EntertainmentEventFilter(key: "like", label: "点赞")
    ]
}

private struct EntertainmentGiftStat {
    let name: String
    let count: Int
}

private struct EntertainmentEventItem: Identifiable {
    let id: String
    let type: String
    let typeLabel: String
    let userName: String
    let userInitial: String
    let time: String
    let text: String
    let extra: String
    let giftId: String
    let giftName: String
    let giftCount: Int
    let giftDiamond: Int

    var tint: Color {
        switch type {
        case "gift": return FastSortTheme.accent
        case "member": return FastSortTheme.success
        case "like": return Color(hex: 0xe85d75)
        case "chat": return Color(hex: 0x4b82f1)
        case "rank": return Color(hex: 0x8e5cf4)
        default: return FastSortTheme.muted
        }
    }
}

struct DouyinRemarkView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pageActivation: PageActivationState
    @State private var activePlatform = "0"
    @State private var activeTab: PickBatchTab = .current
    @State private var batches: [SortBatchItem] = []
    @State private var selectedBatch: SortBatchItem?
    @State private var rows: [LiveTagItem] = []
    @State private var fields: Set<String> = ["orderName", "orderNumber", "orderCount", "orderAmounts"]
    @State private var isRunningRemark = false
    @State private var message = ""
    @State private var hasLoaded = false

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    remarkBatchPanel
                    remarkWorkspace
                }
                VStack(spacing: 16) {
                    remarkBatchPanel
                    remarkWorkspace
                }
            }
            .padding(.top, 20)
            .macPagePadding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: pageActivation.isActive) {
            guard pageActivation.isActive, !hasLoaded else { return }
            guard await pageActivation.waitForFirstInteractiveFrame() else { return }
            await loadBatches()
            hasLoaded = true
        }
    }

    private var remarkBatchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacChoiceGroup("平台", selection: Binding(
                get: { activePlatform },
                set: { next in Task { await setPlatform(next) } }
            ), options: [
                MacChoiceOption(label: "抖音", value: "0"),
                MacChoiceOption(label: "小红书", value: "2")
            ], minItemWidth: 72)
            MacChoiceGroup("批次", selection: Binding(
                get: { activeTab },
                set: { next in Task { await setTab(next) } }
            ), options: [
                MacChoiceOption(label: "当前批次", value: PickBatchTab.current),
                MacChoiceOption(label: "历史批次", value: PickBatchTab.history)
            ], minItemWidth: 82)
            ForEach(batches) { batch in
                Button {
                    Task { await selectBatch(batch) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(batch.batchName ?? "未命名批次").font(.system(size: 14, weight: .semibold))
                        Text(batch.createdTime ?? "-").font(.system(size: 12)).foregroundStyle(FastSortTheme.muted)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedBatch?.id == batch.id ? FastSortTheme.accentSoft : FastSortTheme.groupedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .buttonStyle(.plain)
            }
            if batches.isEmpty { EmptyPanel(text: "暂无批次") }
        }
        .padding(16)
        .frame(width: 300)
        .webCard()
    }

    private var remarkWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("备注字段")
                .font(.system(size: 18, weight: .semibold))
            HStack {
                fieldToggle("昵称", "orderName")
                fieldToggle("编号", "orderNumber")
                fieldToggle("序号", "orderIndex")
                fieldToggle("数量", "orderCount")
                fieldToggle("金额", "orderAmounts")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("标签明细预览").font(.system(size: 18, weight: .semibold))
                HStack(spacing: 12) {
                    Text("序号").frame(width: 48, alignment: .leading)
                    Text("昵称").frame(width: 160, alignment: .leading)
                    Text("备注内容").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FastSortTheme.muted)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(FastSortTheme.border).frame(height: 1) }
                ForEach(Array(rows.prefix(12).enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").frame(width: 48, alignment: .leading)
                        Text(row.orderName ?? "-").frame(width: 160, alignment: .leading)
                        Text(generatedRemark(row)).foregroundStyle(FastSortTheme.muted)
                        Spacer()
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(FastSortTheme.border).frame(height: 1) }
                }
                if rows.isEmpty { EmptyPanel(text: selectedBatch == nil ? "请选择批次" : "暂无标签明细") }
            }
            .padding(16)
            .background(FastSortTheme.groupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Button("生成备注映射") { message = "已生成 \(rows.count) 条备注映射" }
                    .buttonStyle(PrimaryButtonStyle())
                Button(isRunningRemark ? "执行中..." : "执行批次") {
                    Task { await runRemarkBatch() }
                }
                .buttonStyle(AccentOutlineButtonStyle())
                .disabled(selectedBatch == nil || isRunningRemark)
                Button("打开商家后台") {
                    openShopPage()
                }
                .buttonStyle(AccentOutlineButtonStyle())
            }
            if !message.isEmpty { Text(message).foregroundStyle(FastSortTheme.muted) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .webCard()
    }

    private func fieldToggle(_ title: String, _ key: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { fields.contains(key) },
            set: { isOn in
                if isOn { fields.insert(key) } else if fields.count > 1 { fields.remove(key) }
            }
        ))
        .toggleStyle(.checkbox)
    }

    private func setPlatform(_ value: String) async {
        activePlatform = value
        selectedBatch = nil
        rows = []
        await loadBatches()
    }

    private func setTab(_ tab: PickBatchTab) async {
        activeTab = tab
        selectedBatch = nil
        rows = []
        await loadBatches()
    }

    private func loadBatches() async {
        guard !appState.currentUserId.isEmpty else { return }
        do {
            let result = try await PickService(apiClient: appState.makeAPIClient())
                .getAllSortBatchList(pageIndex: 1, pageSize: 20, userId: appState.currentUserId, liveType: activePlatform)
            batches = activeTab == .current ? (result.notComplete.map { [$0] } ?? []) : (result.historyCompletedPage?.list ?? [])
            if let first = batches.first { await selectBatch(first) }
        } catch {
            message = error.localizedDescription
        }
    }

    private func selectBatch(_ batch: SortBatchItem) async {
        selectedBatch = batch
        guard let id = batch.id else { return }
        do {
            let result = try await PickService(apiClient: appState.makeAPIClient())
                .getLiveTags(pageIndex: 1, pageSize: 50, userId: appState.currentUserId, sortBatchId: id, searchKey: "")
            rows = result.list ?? []
        } catch {
            rows = []
            message = error.localizedDescription
        }
    }

    private func generatedRemark(_ row: LiveTagItem) -> String {
        var parts: [String] = []
        if fields.contains("orderName") { parts.append(row.orderName ?? "") }
        if fields.contains("orderNumber") { parts.append("#\(row.orderNumber?.value ?? "")") }
        if fields.contains("orderIndex") { parts.append("@\(row.orderIndex?.value ?? "")") }
        if fields.contains("orderCount") { parts.append("x\(row.orderCount?.value ?? "")") }
        if fields.contains("orderAmounts") { parts.append("￥\(row.orderAmounts?.value ?? "")") }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func runRemarkBatch() async {
        guard let batchId = selectedBatch?.id, !batchId.isEmpty else { return }
        isRunningRemark = true
        defer { isRunningRemark = false }
        do {
            var allRows: [LiveTagItem] = []
            var page = 1
            let size = 100
            var totalPages = 1
            repeat {
                let result = try await PickService(apiClient: appState.makeAPIClient())
                    .getLiveTags(pageIndex: page, pageSize: size, userId: appState.currentUserId, sortBatchId: batchId, searchKey: "")
                allRows.append(contentsOf: result.list ?? [])
                let total = result.totalValue
                totalPages = max(1, Int(ceil(Double(total) / Double(size))))
                page += 1
            } while page <= totalPages

            let entries = allRows.map(remarkEntry(for:))
            guard !entries.isEmpty else {
                message = "当前批次没有可执行的备注数据"
                return
            }
            let payload: [String: Any] = [
                "platform": remarkPlatformKey,
                "batchId": batchId,
                "generatedAt": ISO8601DateFormatter().string(from: Date()),
                "remarkMap": entries
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("xunjian-remark-\(UUID().uuidString).json")
            try data.write(to: fileURL)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            openShopPage()
            message = "已生成 \(entries.count) 条备注执行数据，并打开商家后台"
        } catch {
            message = error.localizedDescription
        }
    }

    private func remarkEntry(for row: LiveTagItem) -> [String: String] {
        [
            "buyer": resolveBuyerId(row),
            "buyerName": row.orderName ?? "",
            "remark": generatedRemark(row),
            "platform": remarkPlatformKey,
            "remarkBuyerId": row.remarkBuyerId ?? "",
            "shortId": row.shortId ?? "",
            "orderNameId": row.orderNameId ?? "",
            "cachedUserId": row.cachedUserId ?? "",
            "cachedNicknameMask": row.cachedNicknameMask ?? "",
            "cachedVerifiedAt": row.cachedVerifiedAt ?? "",
            "cacheShopKey": row.cacheShopKey ?? "",
            "cacheVersion": row.cacheVersion ?? ""
        ]
    }

    private func resolveBuyerId(_ row: LiveTagItem) -> String {
        let candidates: [String?] = activePlatform == "2"
            ? [row.remarkBuyerId, row.danmuUserId, row.orderNameId, row.shortId]
            : [row.remarkBuyerId, row.shortId, row.orderNameId]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
    }

    private var remarkPlatformKey: String {
        activePlatform == "2" ? "xiaohongshu" : "douyin"
    }

    private func openShopPage() {
        let raw = activePlatform == "2"
            ? "https://ark.xiaohongshu.com/app-order/order/query"
            : "https://fxg.jinritemai.com/ffa/morder/order/list"
        if let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PrinterTestView: View {
    @EnvironmentObject private var pageActivation: PageActivationState
    @State private var instructionType = "TSPL"
    @State private var width = "60"
    @State private var height = "40"
    @State private var command = "SIZE 60 mm,40 mm\nCLS\nTEXT 40,40,\"TSS24.BF2\",0,1,1,\"迅拣测试\"\nPRINT 1"
    @State private var printers: [String] = []
    @State private var selectedPrinter = ""
    @State private var isRefreshing = false
    @State private var logs: [String] = []
    @State private var hasLoaded = false

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    printerInspector
                    commandEditor
                }
                VStack(spacing: 16) {
                    printerInspector
                    commandEditor
                }
            }
            .padding(.top, 20)
            .macPagePadding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: pageActivation.isActive) {
            guard pageActivation.isActive, !hasLoaded else { return }
            guard await pageActivation.waitForFirstInteractiveFrame() else { return }
            await refreshPrinters()
            hasLoaded = true
        }
    }

    private var printerInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("打印机选择")
                .font(.system(size: 18, weight: .semibold))
            if isRefreshing {
                ProgressView("正在扫描系统打印机")
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else if printers.isEmpty {
                EmptyPanel(text: "未发现系统打印机")
            } else {
                ForEach(printers, id: \.self) { printer in
                    Button {
                        selectedPrinter = printer
                        appendLog("已选择打印机：\(printer)")
                    } label: {
                        HStack {
                            Image(systemName: "printer.fill")
                                .foregroundStyle(FastSortTheme.accent)
                            Text(printer)
                                .lineLimit(1)
                            Spacer()
                            if selectedPrinter == printer {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(FastSortTheme.success)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedPrinter == printer ? FastSortTheme.accentSoft : FastSortTheme.groupedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .buttonStyle(.plain)
                }
            }
            Button("刷新设备") {
                Task { await refreshPrinters() }
            }
            .buttonStyle(AccentOutlineButtonStyle())
            MacSelect("指令语言", selection: $instructionType, options: [
                MacSelectOption(label: "TSPL", value: "TSPL"),
                MacSelectOption(label: "CPCL", value: "CPCL"),
                MacSelectOption(label: "ESC/POS", value: "ESC/POS")
            ], width: 178)
            HStack {
                TextField("宽 mm", text: $width).webTextInput()
                TextField("高 mm", text: $height).webTextInput()
            }
            Button("生成预设指令") { generatePreset() }
                .buttonStyle(AccentOutlineButtonStyle())
        }
        .padding(16)
        .frame(width: 300)
        .webCard()
    }

    private var commandEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("指令内容")
                .font(.system(size: 18, weight: .semibold))
            TextEditor(text: $command)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 260)
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(FastSortTheme.border) }
            HStack {
                Button("发送") { Task { await sendCommand() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedPrinter.isEmpty || command.isEmpty)
                Button("清空日志") { logs.removeAll() }
                    .buttonStyle(AccentOutlineButtonStyle())
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("日志").font(.system(size: 14, weight: .semibold))
                ForEach(logs.suffix(8), id: \.self) { log in
                    Text(log).font(.system(size: 12, design: .monospaced)).foregroundStyle(FastSortTheme.muted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .webCard()
    }

    private func generatePreset() {
        if instructionType == "ESC/POS" {
            command = "1B 40 1B 61 01 E8 BF 85 E6 8B A3 E6 B5 8B E8 AF 95 0A 1D 56 00"
        } else if instructionType == "CPCL" {
            command = "! 0 200 200 320 1\nTEXT 4 0 40 40 迅拣测试\nFORM\nPRINT"
        } else {
            command = "SIZE \(width) mm,\(height) mm\nCLS\nTEXT 40,40,\"TSS24.BF2\",0,1,1,\"迅拣测试\"\nPRINT 1"
        }
        appendLog("已生成 \(instructionType) 预设指令")
    }

    private func appendLog(_ text: String) {
        logs.append("\(Date()) \(text)")
    }

    private func refreshPrinters() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let output = runProcess("/usr/bin/lpstat", arguments: ["-p"])
        let names = output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let parts = line.split(separator: " ")
                guard parts.count >= 2, parts[0] == "printer" else { return nil }
                return String(parts[1])
            }
        printers = names
        if selectedPrinter.isEmpty || !printers.contains(selectedPrinter) {
            selectedPrinter = printers.first ?? ""
        }
        appendLog(printers.isEmpty ? "未发现系统打印机" : "发现 \(printers.count) 台系统打印机")
    }

    private func sendCommand() async {
        guard !selectedPrinter.isEmpty else {
            appendLog("请先选择打印机")
            return
        }
        do {
            let data: Data
            if instructionType == "ESC/POS", command.range(of: #"^[0-9A-Fa-f\s]+$"#, options: .regularExpression) != nil {
                data = Data(hexString: command)
            } else {
                data = Data(command.utf8)
            }
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("xunjian-print-\(UUID().uuidString).bin")
            try data.write(to: fileURL)
            let output = runProcess("/usr/bin/lp", arguments: ["-d", selectedPrinter, "-o", "raw", fileURL.path])
            appendLog("已发送 \(data.count) 字节到 \(selectedPrinter)：\(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        } catch {
            appendLog("发送失败：\(error.localizedDescription)")
        }
    }

    private func runProcess(_ launchPath: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return error.localizedDescription
        }
    }
}

private extension Data {
    init(hexString: String) {
        var bytes = [UInt8]()
        let clean = hexString.replacingOccurrences(of: #"[^0-9A-Fa-f]"#, with: "", options: .regularExpression)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2, limitedBy: clean.endIndex) ?? clean.endIndex
            if next <= clean.endIndex {
                let chunk = String(clean[index..<next])
                if let byte = UInt8(chunk, radix: 16) {
                    bytes.append(byte)
                }
            }
            index = next
        }
        self = Data(bytes)
    }
}
