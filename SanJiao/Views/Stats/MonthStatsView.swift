import SwiftUI
import SwiftData

struct MonthStatsView: View {
    let transactions: [Transaction]
    @Environment(AppState.self) private var appState
    @AppStorage("big_transaction_threshold_percent") private var bigTransactionThresholdPercent = 5.0

    private var selectedMonthDate: Date {
        let components = DateComponents(year: appState.statsMonthYear, month: appState.statsMonthMo, day: 1)
        return Calendar.current.date(from: components) ?? Date()
    }

    private var selectedMonthDayCount: Int {
        Calendar.current.range(of: .day, in: .month, for: selectedMonthDate)?.count ?? 31
    }

    // Transactions for selected month
    private var monthTx: [Transaction] {
        transactions.filter {
            let c = Calendar.current.dateComponents([.year,.month], from: $0.date)
            return c.year == appState.statsMonthYear && c.month == appState.statsMonthMo
        }
    }

    private func weekOfMonth(for date: Date) -> Int {
        let day = Calendar.current.component(.day, from: date)
        return min((day - 1) / 7 + 1, 4)
    }

    private func weekLabel(_ week: Int) -> String {
        let start = (week - 1) * 7 + 1
        let end = week == 4 ? selectedMonthDayCount : min(week * 7, selectedMonthDayCount)
        return String(localized: "\(start)-\(end)日")
    }

    private var totalExpense: Double {
        monthTx.filter { !$0.isRefunded && $0.isExpense }.reduce(0) { $0 + $1.absoluteAmount }
    }

    // Category breakdown for donut
    private var categoryBreakdown: [(name: String, emoji: String, amount: Double, pct: Double)] {
        let expenses = monthTx.filter { !$0.isRefunded && $0.isExpense }
        let grouped = Dictionary(grouping: expenses, by: \.categoryName)
        let items = grouped.map { entry -> (name: String, emoji: String, amount: Double, pct: Double) in
            let name = entry.key
            let txs = entry.value
            let emoji = txs.first?.categoryEmoji ?? ""
            let amt = txs.reduce(0) { $0 + $1.absoluteAmount }
            return (name: name, emoji: emoji, amount: amt, pct: totalExpense > 0 ? amt/totalExpense : 0)
        }.sorted { $0.amount > $1.amount }
        return Array(items.prefix(5))
    }

    // 近6周柱状数据：滚动7天窗口，最右柱终点 = 今天，往左每移一格退7天
    private var sixWeekBars: [BarItem] {
        let cal = Calendar.current
        let anchorDate: Date = {
            if isNow {
                return cal.startOfDay(for: Date())
            }
            let endOfMonth = cal.date(byAdding: DateComponents(month: 1, day: -1), to: selectedMonthDate) ?? selectedMonthDate
            return cal.startOfDay(for: endOfMonth)
        }()
        let f = DateFormatter(); f.dateFormat = "M/d"

        return (0..<6).map { i in
            let offset = 5 - i
            // 该柱的最后一天
            let periodEnd   = cal.date(byAdding: .day, value: -offset * 7, to: anchorDate)!
            // 该柱的第一天（共7天）
            let periodStart = cal.date(byAdding: .day, value: -6, to: periodEnd)!
            // 过滤用的次日（右开区间）
            let periodEndNext = cal.date(byAdding: .day, value: 1, to: periodEnd)!

            let amount = transactions.filter {
                !$0.isRefunded && $0.isExpense &&
                $0.date >= periodStart && $0.date < periodEndNext
            }.reduce(0) { $0 + $1.absoluteAmount }

            // 6 个柱标签全部用日期格式（M/d），避免「日期 + 上周/本周」混搭——
            // 信息精度统一，且月初月末时"上周/本周"会有歧义
            let label = f.string(from: periodEnd)
            let detailLabel = "\(f.string(from: periodStart)) ~ \(f.string(from: periodEnd))"

            return BarItem(label: label, amount: amount,
                           isCurrent: i == 5, detailLabel: detailLabel)
        }
    }

    // Top 3 categories
    private var topCategories: [(name: String, emoji: String, amount: Double, pct: Double)] {
        Array(categoryBreakdown.prefix(3))
    }

    // 大额消费：单笔 >= 用户设置的本月总支出占比
    private var bigTransactionThresholdRatio: Double { bigTransactionThresholdPercent / 100 }
    private var bigTransactionThreshold: Double { totalExpense * bigTransactionThresholdRatio }
    private var allBigTransactions: [Transaction] {
        guard totalExpense > 0 else { return [] }
        return monthTx
            .filter { !$0.isRefunded && $0.isExpense && $0.absoluteAmount >= bigTransactionThreshold }
            .sorted { $0.absoluteAmount > $1.absoluteAmount }
    }
    private var bigTransactions: [Transaction] { Array(allBigTransactions.prefix(5)) }

    // Frequent categories (5+ transactions)
    private var freqCategories: [FrequencyInsightItem] {
        let expenses = monthTx.filter { !$0.isRefunded && $0.isExpense }
        let grouped = Dictionary(grouping: expenses, by: \.categoryName)
        return grouped.compactMap { entry -> FrequencyInsightItem? in
            let name = entry.key
            let txs = entry.value
            guard txs.count >= 5 else { return nil }
            let emoji = txs.first?.categoryEmoji ?? ""
            let total = txs.reduce(0) { $0 + $1.absoluteAmount }
            let buckets = (1...4).map { week -> FrequencyDistributionBucket in
                let weekTransactions = txs.filter { weekOfMonth(for: $0.date) == week }
                let weekTotal = weekTransactions.reduce(0) { $0 + $1.absoluteAmount }
                return FrequencyDistributionBucket(
                    label: String(localized: "第\(week)周"),
                    detailLabel: weekLabel(week),
                    amount: weekTotal,
                    count: weekTransactions.count
                )
            }
            return FrequencyInsightItem(
                name: name,
                emoji: emoji,
                times: txs.count,
                avg: total / Double(txs.count),
                total: total,
                distribution: buckets
            )
        }
        .sorted { lhs, rhs in
            lhs.times == rhs.times ? lhs.total > rhs.total : lhs.times > rhs.times
        }
        .prefix(3)
        .map { $0 }
    }

    private var freqTotal: Double { freqCategories.reduce(0) { $0 + $1.total } }

    private var isNow: Bool {
        let now = Date()
        return appState.statsMonthYear == Calendar.current.component(.year, from: now) &&
               appState.statsMonthMo == Calendar.current.component(.month, from: now)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Month nav 已上移到 StatsView 统一管理（支持滚动后塌缩进 nav bar）

            if monthTx.isEmpty {
                // 本月无数据：展示空状态（与账单/统计页保持一致）
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.appTertiary)
                        .opacity(0.7)
                    Text("本月还没有记录")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.appSecondary)
                    Text("等这个月开始记账，这里就会有数据啦")
                        .font(.system(size: 13))
                        .foregroundStyle(.appTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .padding(.horizontal, 24)
            } else {
                summaryCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // 6-week bar chart
                BarChartCard(title: String(localized: "近 6 周支出趋势"), bars: sixWeekBars)
                    .padding(.horizontal, 16).padding(.bottom, 12)

                // Top categories
                if !topCategories.isEmpty {
                    TopCategoriesCard(title: String(localized: "支出最多"), items: topCategories)
                        .padding(.horizontal, 16).padding(.bottom, 12)
                }

                // Big transactions
                if !bigTransactions.isEmpty {
                    BigTransactionsCard(
                        transactions: bigTransactions,
                        allTransactions: allBigTransactions,
                        threshold: bigTransactionThreshold,
                        thresholdPercent: $bigTransactionThresholdPercent,
                        monthTotal: totalExpense
                    )
                    .id(StatsScrollTarget.bigTransactions.rawValue)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }

                // Frequent spending
                if !freqCategories.isEmpty {
                    FreqSpendingCard(
                        items: freqCategories,
                        total: freqTotal,
                        badgeText: String(localized: "这个月常出现")
                    )
                    .id(StatsScrollTarget.frequentSpending.rawValue)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
            }

            Spacer(minLength: 20)
        }
    }

    /// 圆环段颜色——和「支出最多」「高频消费」bar 同款 rank 梯度：
    /// 排名靠前饱和，后续递减。强化品牌紫，避免 Excel 默认配色感。
    private func donutColor(idx: Int) -> Color {
        switch idx {
        case 0:  return .appAccent
        case 1:  return .appAccent.opacity(0.70)
        case 2:  return .appAccent.opacity(0.50)
        case 3:  return .appAccent.opacity(0.38)
        default: return .appAccent.opacity(0.26)
        }
    }

    private var amountLabel: String {
        isNow ? String(localized: "本月支出") : String(localized: "\(appState.statsMonthMo)月支出")
    }

    /// 月汇总卡：donut + legend，保持统一布局
    private var summaryCard: some View {
        HStack(spacing: 24) {
            DonutChart(
                segments: categoryBreakdown.enumerated().map { (i, item) in (item.amount, donutColor(idx: i)) },
                centerText: "¥\(Int(totalExpense).formatted())",
                centerLabel: amountLabel
            )
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(categoryBreakdown.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(donutColor(idx: i))
                            .frame(width: 9, height: 9)
                        Text(item.name.localizedCategoryName)
                            .font(.system(size: 13))
                            .foregroundStyle(.appSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text("\(Int(item.pct * 100))%")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.appSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

}

// MARK: - Shared chart components

struct DonutChart: View {
    let segments: [(Double, Color)]
    let centerText: String
    let centerLabel: String

    var body: some View {
        Canvas { ctx, size in
            let total = segments.reduce(0.0) { $0 + $1.0 }
            guard total > 0 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 7
            var start = -Double.pi / 2
            for seg in segments {
                let fraction = seg.0 / total
                let end = start + fraction * 2 * Double.pi
                var p = Path()
                p.addArc(center: center, radius: radius,
                         startAngle: .radians(start), endAngle: .radians(end),
                         clockwise: false)
                ctx.stroke(p, with: .color(seg.1),
                           style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                start = end
            }
        }
        .overlay {
            VStack(spacing: 3) {
                Text(centerText)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.appPrimary)
                    .tracking(-0.5)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(centerLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.appSecondary)
            }
        }
    }
}

struct BarItem {
    let label: String       // 柱子底部短标签
    let detailLabel: String // 选中后 legend 展示的详细文字
    let amount: Double
    let isCurrent: Bool
    let isFuture: Bool
    init(label: String, amount: Double, isCurrent: Bool, isFuture: Bool = false, detailLabel: String? = nil) {
        self.label = label
        self.detailLabel = detailLabel ?? label
        self.amount = amount
        self.isCurrent = isCurrent
        self.isFuture = isFuture
    }
}

struct BarChartCard: View {
    let title: String
    let bars: [BarItem]

    @State private var selectedIndex: Int? = nil

    private var chartBarMaxHeight: CGFloat { 130 }
    private var maxAmount: Double { bars.filter { !$0.isFuture }.map(\.amount).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 标题行：选中时右侧显示该期金额——和频次分析 chart 同款 baseline 对齐
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                Spacer()
                if let idx = selectedIndex, let bar = bars[safe: idx] {
                    HStack(spacing: 4) {
                        Text(bar.detailLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(.appPrimary)
                        Text("¥\(Int(bar.amount).formatted())")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.appTeal)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: selectedIndex)

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(bars.indices, id: \.self) { i in
                    VStack(spacing: 8) {
                        // 柱子区——只在 0 值时显示 baseline，避免 6 个柱底连成视觉分割线
                        ZStack(alignment: .bottom) {
                            if bars[i].amount > 0 && !bars[i].isFuture {
                                Capsule()
                                    .fill(barColor(bars[i], selected: selectedIndex == i))
                                    .frame(height: barHeight(bars[i]))
                                    .scaleEffect(y: selectedIndex == i ? 1.04 : 1, anchor: .bottom)
                                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selectedIndex)
                            } else {
                                // 仅 0 值时显示 baseline，传达"这周存在但无支出"
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.appSeparator.opacity(0.6))
                                    .frame(height: 3)
                            }
                        }
                        // 限制柱子最大宽度——保持纤细比例
                        .frame(maxWidth: 32)
                        .frame(height: chartBarMaxHeight, alignment: .bottom)

                        Text(bars[i].label)
                            .font(.system(size: 12, weight: selectedIndex == i ? .semibold : .medium))
                            .foregroundStyle(selectedIndex == i ? Color.appAccent : Color.appSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedIndex = (selectedIndex == i) ? nil : i
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func barColor(_ bar: BarItem, selected: Bool) -> Color {
        if bar.isFuture  { return Color.appSeparator.opacity(0.5) }
        if selected      { return Color.appAccent }
        if bar.isCurrent { return Color.appAccent.opacity(0.75) }
        return Color.appAccent.opacity(0.32)
    }

    /// 柱高——sqrt 缩放放大小值，让"很少花"的周也能看出趋势；
    /// 和频次分析 chart 同款算法（差异：max 130pt 而非 170pt，因为这里是 at-a-glance）。
    private func barHeight(_ bar: BarItem) -> CGFloat {
        guard !bar.isFuture, bar.amount > 0, maxAmount > 0 else { return 0 }
        let normalized = sqrt(bar.amount / maxAmount)
        return max(CGFloat(normalized) * chartBarMaxHeight, 6)
    }
}

struct TopCategoriesCard: View {
    let title: String
    let items: [(name: String, emoji: String, amount: Double, pct: Double)]

    private var maxAmount: Double { items.map { $0.amount }.max() ?? 1 }

    /// 排名→bar 颜色：第 1 主色饱和，后续递减。视觉上即时传达"哪个最重"。
    private func barColor(rank: Int) -> Color {
        switch rank {
        case 0:  return .appAccent
        case 1:  return .appAccent.opacity(0.65)
        case 2:  return .appAccent.opacity(0.4)
        default: return .appSeparator
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.appPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ForEach(items.indices, id: \.self) { i in
                if i > 0 {
                    Rectangle()
                        .fill(Color.appSeparator.opacity(0.6))
                        .frame(height: 0.5)
                        .padding(.leading, 60)
                }
                VStack(alignment: .leading, spacing: 7) {
                    // Row 1: emoji + name + amount
                    HStack(spacing: 12) {
                        Text(items[i].emoji)
                            .font(.system(size: 24))
                            .frame(width: 32, alignment: .center)
                        Text(items[i].name.localizedCategoryName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.appPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("¥\(Int(items[i].amount).formatted())")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.appPrimary)
                    }

                    // Row 2: bar + 百分比，缩进对齐名字
                    HStack(spacing: 10) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.appSeparator.opacity(0.7))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(barColor(rank: i))
                                    .frame(width: max(geo.size.width * CGFloat(items[i].amount / maxAmount), 4),
                                           height: 5)
                            }
                        }
                        .frame(height: 5)
                        Text("\(Int(items[i].pct * 100))%")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.appSecondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .padding(.leading, 44)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct BigTransactionsCard: View {
    let transactions:    [Transaction]   // top 5 for preview
    let allTransactions: [Transaction]   // all big ones for the detail sheet
    let threshold:       Double
    @Binding var thresholdPercent: Double
    let monthTotal:      Double

    @Environment(\.modelContext) private var context

    private enum ActiveSheet: Identifiable {
        case detail
        case thresholdSettings
        case actionMenu(Transaction)
        case categoryPicker(Transaction)

        var id: String {
            switch self {
            case .detail: "detail"
            case .thresholdSettings: "threshold-settings"
            case .actionMenu(let tx): "action-\(tx.id)"
            case .categoryPicker(let tx): "category-\(tx.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var editAmountTx: Transaction?
    @State private var editAmountText = ""
    @State private var editDateTx: Transaction?
    @State private var deleteCandidateTx: Transaction?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header——和「支出最多 / 高频消费」对齐：单行标题 + 可选右元素
            HStack {
                Text("大额消费")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                Spacer()
                Text("单笔超 ¥\(Int(threshold))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.appTertiary)
                Button {
                    activeSheet = .thresholdSettings
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.appTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("调整大额消费线")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ForEach(transactions, id: \.id) { tx in
                if tx.id != transactions.first?.id {
                    Rectangle()
                        .fill(Color.appSeparator.opacity(0.6))
                        .frame(height: 0.5)
                        .padding(.leading, 60)
                }
                bigTxRow(tx)
            }

            // "查看全部" footer — only when more than 5
            if allTransactions.count > 5 {
                Divider()
                Button { activeSheet = .detail } label: {
                    HStack {
                        Text("查看全部 \(allTransactions.count) 笔大额消费")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.appAccent)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.appTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .detail:
                BigTransactionDetailSheet(
                    transactions: allTransactions,
                    threshold: threshold,
                    thresholdPercent: thresholdPercent,
                    monthTotal: monthTotal
                )
            case .thresholdSettings:
                BigTransactionThresholdSheet(thresholdPercent: $thresholdPercent)
                    .presentationDetents([.height(260)])
                    .presentationDragIndicator(.visible)
            case .actionMenu(let tx):
                TransactionActionSheet(
                    tx: tx,
                    isRefunded: Binding(
                        get: { tx.isRefunded },
                        set: { newValue in
                            tx.isRefunded = newValue
                            try? context.save()
                        }
                    ),
                    onEditAmount: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            editAmountText = String(tx.absoluteAmount)
                            editAmountTx = tx
                        }
                    },
                    onEditCategory: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            activeSheet = .categoryPicker(tx)
                        }
                    },
                    onEditDate: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            editDateTx = tx
                        }
                    },
                    onDelete: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            deleteCandidateTx = tx
                        }
                    }
                )
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
                .presentationBackground(Color.appCard)
            case .categoryPicker(let tx):
                CategoryPickerSheet(isExpense: tx.isExpense) { name, emoji in
                    tx.categoryName = name
                    tx.categoryEmoji = emoji
                    try? context.save()
                }
            }
        }
        .sheet(item: $editDateTx) { tx in
            TransactionDateEditSheet(
                date: Binding(
                    get: { tx.date },
                    set: { newDate in
                        tx.date = newDate
                        try? context.save()
                    }
                ),
                onClose: { editDateTx = nil }
            )
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
        .alert("修改金额", isPresented: Binding(
            get: { editAmountTx != nil },
            set: { if !$0 { editAmountTx = nil } }
        )) {
            TextField("金额", text: $editAmountText)
                .keyboardType(.decimalPad)
            Button("保存") {
                if let tx = editAmountTx,
                   let value = Double(editAmountText), value > 0 {
                    tx.amount = tx.isExpense ? -value : value
                    try? context.save()
                }
                editAmountTx = nil
            }
            Button("取消", role: .cancel) { editAmountTx = nil }
        } message: {
            if let tx = editAmountTx {
                Text("当前：¥\(String(format: "%.2f", tx.absoluteAmount))")
            }
        }
        .alert("删除这条记录？", isPresented: Binding(
            get: { deleteCandidateTx != nil },
            set: { if !$0 { deleteCandidateTx = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let tx = deleteCandidateTx { deleteTx(tx) }
                deleteCandidateTx = nil
            }
            Button("取消", role: .cancel) { deleteCandidateTx = nil }
        } message: {
            if let tx = deleteCandidateTx {
                Text("「\(tx.name)」删除后无法恢复")
            }
        }
    }

    @ViewBuilder
    private func bigTxRow(_ tx: Transaction) -> some View {
        HStack(spacing: 12) {
            Text(tx.categoryEmoji)
                .font(.system(size: 24))
                .frame(width: 32, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.appPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(dayString(tx.date)) · \(dayOfWeek(tx.date))")
                        .font(.system(size: 12))
                        .foregroundStyle(.appSecondary)
                    if monthTotal > 0 {
                        Text("\(Int(tx.absoluteAmount / monthTotal * 100))%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.appWarning)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.appWarningSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            Spacer()
            Text("¥\(Int(tx.absoluteAmount).formatted())")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.appPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            activeSheet = .actionMenu(tx)
        }
    }

    private func deleteTx(_ tx: Transaction) {
        context.delete(tx)
        try? context.save()
    }

    private func dayString(_ date: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMd"); return f.string(from: date)
    }
    private func dayOfWeek(_ date: Date) -> String {
        [String(localized: "周日"), String(localized: "周一"), String(localized: "周二"), String(localized: "周三"), String(localized: "周四"), String(localized: "周五"), String(localized: "周六")][Calendar.current.component(.weekday, from: date) - 1]
    }

    private func formatPercent(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value))%"
            : "\(String(format: "%.1f", value))%"
    }
}

private struct BigTransactionThresholdSheet: View {
    @Binding var thresholdPercent: Double
    @Environment(\.dismiss) private var dismiss

    private let options: [Double] = [3, 5, 8, 10, 15]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("我们默认用 5% 作为温和提醒线，你也可以按自己的消费节奏微调。")
                    .font(.system(size: 13))
                    .foregroundStyle(.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                thresholdPercent = option
                            }
                        } label: {
                            VStack(spacing: 5) {
                                Text(formatPercent(option))
                                    .font(.system(size: 15, weight: .semibold))
                                if option == 5 {
                                    Text("推荐")
                                        .font(.system(size: 10, weight: .medium))
                                }
                            }
                            .foregroundStyle(thresholdPercent == option ? .white : .appSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(thresholdPercent == option ? Color.appWarning : Color.appCard)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.appTertiary)
                    .padding(.horizontal, 2)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBg)
            .navigationTitle("大额消费线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.appAccent)
                }
            }
        }
        .presentationBackground(Color.appBg)
    }

    private var description: String {
        switch thresholdPercent {
        case 3: return String(localized: "更敏感：会看到更多可能值得留意的支出。")
        case 5: return String(localized: "默认推荐：既能看见明显大额，又不会提醒过多。")
        case 8: return String(localized: "更克制：只保留相对明显的大笔支出。")
        case 10: return String(localized: "偏宽松：适合本月消费波动比较大的情况。")
        case 15: return String(localized: "非常克制：只显示特别明显的大额消费。")
        default: return String(localized: "当前：单笔达到本月总支出的 \(formatPercent(thresholdPercent)) 会出现在这里。")
        }
    }

    private func formatPercent(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value))%"
            : "\(String(format: "%.1f", value))%"
    }
}

// MARK: - Big Transaction Detail Sheet

struct BigTransactionDetailSheet: View {
    let transactions: [Transaction]
    let threshold:    Double
    let thresholdPercent: Double
    let monthTotal:   Double

    @State private var filterCategory: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private enum ActiveSheet: Identifiable {
        case actionMenu(Transaction)
        case categoryPicker(Transaction)

        var id: String {
            switch self {
            case .actionMenu(let tx): "action-\(tx.id)"
            case .categoryPicker(let tx): "category-\(tx.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var editAmountTx: Transaction?
    @State private var editAmountText = ""
    @State private var editDateTx: Transaction?
    @State private var deleteCandidateTx: Transaction?

    private var categories: [(name: String, emoji: String)] {
        var seen = Set<String>()
        return transactions.compactMap { tx -> (String, String)? in
            guard !seen.contains(tx.categoryName) else { return nil }
            seen.insert(tx.categoryName)
            return (tx.categoryName, tx.categoryEmoji)
        }
    }

    private var filtered: [Transaction] {
        filterCategory == nil
            ? transactions
            : transactions.filter { $0.categoryName == filterCategory }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Info banner
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.appAccent)
                        Text("单笔 ≥ ¥\(Int(threshold))（本月总支出 \(formatPercent(thresholdPercent))）")
                            .font(.system(size: 13))
                            .foregroundStyle(.appSecondary)
                        Spacer()
                        Text("共 \(transactions.count) 笔")
                            .font(.system(size: 12))
                            .foregroundStyle(.appTertiary)
                    }
                    .padding(.horizontal, 20)

                    // Category filter chips
                    if categories.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                bigDetailChip(title: String(localized: "全部"), active: filterCategory == nil) {
                                    filterCategory = nil
                                }
                                ForEach(categories, id: \.name) { cat in
                                    bigDetailChip(
                                        title: "\(cat.emoji) \(cat.name.localizedCategoryName)",
                                        active: filterCategory == cat.name
                                    ) {
                                        filterCategory = (filterCategory == cat.name) ? nil : cat.name
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Transaction rows
                    VStack(spacing: 0) {
                        ForEach(filtered, id: \.id) { tx in
                            if tx.id != filtered.first?.id { Divider().padding(.leading, 68) }
                            detailRow(tx)
                        }
                    }
                    .background(Color.appCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
            }
            .background(Color.appBg)
            .navigationTitle("大额消费")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(.appAccent)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .actionMenu(let tx):
                    TransactionActionSheet(
                        tx: tx,
                        isRefunded: Binding(
                            get: { tx.isRefunded },
                            set: { newValue in
                                tx.isRefunded = newValue
                                try? context.save()
                            }
                        ),
                        onEditAmount: {
                            activeSheet = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                editAmountText = String(tx.absoluteAmount)
                                editAmountTx = tx
                            }
                        },
                        onEditCategory: {
                            activeSheet = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                activeSheet = .categoryPicker(tx)
                            }
                        },
                        onEditDate: {
                            activeSheet = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                editDateTx = tx
                            }
                        },
                        onDelete: {
                            activeSheet = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                deleteCandidateTx = tx
                            }
                        }
                    )
                    .presentationDetents([.height(380)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
                    .presentationBackground(Color.appCard)
                case .categoryPicker(let tx):
                    CategoryPickerSheet(isExpense: tx.isExpense) { name, emoji in
                        tx.categoryName = name
                        tx.categoryEmoji = emoji
                        try? context.save()
                    }
                }
            }
            .sheet(item: $editDateTx) { tx in
                TransactionDateEditSheet(
                    date: Binding(
                        get: { tx.date },
                        set: { newDate in
                            tx.date = newDate
                            try? context.save()
                        }
                    ),
                    onClose: { editDateTx = nil }
                )
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
            }
            .alert("修改金额", isPresented: Binding(
                get: { editAmountTx != nil },
                set: { if !$0 { editAmountTx = nil } }
            )) {
                TextField("金额", text: $editAmountText)
                    .keyboardType(.decimalPad)
                Button("保存") {
                    if let tx = editAmountTx,
                       let value = Double(editAmountText), value > 0 {
                        tx.amount = tx.isExpense ? -value : value
                        try? context.save()
                    }
                    editAmountTx = nil
                }
                Button("取消", role: .cancel) { editAmountTx = nil }
            } message: {
                if let tx = editAmountTx {
                    Text("当前：¥\(String(format: "%.2f", tx.absoluteAmount))")
                }
            }
            .alert("删除这条记录？", isPresented: Binding(
                get: { deleteCandidateTx != nil },
                set: { if !$0 { deleteCandidateTx = nil } }
            )) {
                Button("删除", role: .destructive) {
                    if let tx = deleteCandidateTx { deleteTx(tx) }
                    deleteCandidateTx = nil
                }
                Button("取消", role: .cancel) { deleteCandidateTx = nil }
            } message: {
                if let tx = deleteCandidateTx {
                    Text("「\(tx.name)」删除后无法恢复")
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ tx: Transaction) -> some View {
        HStack(spacing: 12) {
            Text(tx.categoryEmoji)
                .font(.system(size: 22))
                .frame(width: 32, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.appPrimary)
                    .lineLimit(1)
                Text(dateString(tx.date))
                    .font(.system(size: 12))
                    .foregroundStyle(.appSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("¥\(Int(tx.absoluteAmount).formatted())")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                if monthTotal > 0 {
                    Text("\(Int(tx.absoluteAmount / monthTotal * 100))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.appWarning)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            activeSheet = .actionMenu(tx)
        }
    }

    @ViewBuilder
    private func bigDetailChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .white : .appSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Color.appAccent : Color.appCard)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMdHHmm"); return f.string(from: date)
    }

    private func deleteTx(_ tx: Transaction) {
        context.delete(tx)
        try? context.save()
    }

    private func formatPercent(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value))%"
            : "\(String(format: "%.1f", value))%"
    }
}

struct FrequencyDistributionBucket: Identifiable, Hashable {
    let label: String
    let detailLabel: String
    let amount: Double
    let count: Int

    var id: String { label + detailLabel }
}

struct FrequencyInsightItem: Identifiable, Hashable {
    let name: String
    let emoji: String
    let times: Int
    let avg: Double
    let total: Double
    let distribution: [FrequencyDistributionBucket]

    var id: String { "\(emoji)-\(name)" }
}

enum FrequencyMetricMode: String, CaseIterable, Identifiable {
    case amount = "按金额"
    case frequency = "按频次"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .amount: String(localized: "按金额")
        case .frequency: String(localized: "按频次")
        }
    }
}

struct FreqSpendingCard: View {
    let items: [FrequencyInsightItem]
    let total: Double
    let badgeText: String

    @State private var selectedItem: FrequencyInsightItem?

    private var maxTimes: Int { items.map { $0.times }.max() ?? 1 }

    /// 排名→bar 颜色——和「支出最多」同款梯度，确保 3 张卡视觉统一
    private func barColor(rank: Int) -> Color {
        switch rank {
        case 0:  return .appAccent
        case 1:  return .appAccent.opacity(0.65)
        case 2:  return .appAccent.opacity(0.4)
        default: return .appSeparator
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("高频消费")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                Spacer()
                Text(badgeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.appTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ForEach(items.indices, id: \.self) { i in
                if i > 0 {
                    Rectangle()
                        .fill(Color.appSeparator.opacity(0.6))
                        .frame(height: 0.5)
                        .padding(.leading, 60)
                }
                Button {
                    selectedItem = items[i]
                } label: {
                    HStack(spacing: 12) {
                        Text(items[i].emoji)
                            .font(.system(size: 24))
                            .frame(width: 32, alignment: .center)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(items[i].name.localizedCategoryName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.appPrimary)
                                .lineLimit(1)
                            // bar——和「支出最多」完全相同的样式（Capsule 5pt + 同款 track + rank 渐变）
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.appSeparator.opacity(0.7))
                                        .frame(height: 5)
                                    Capsule()
                                        .fill(barColor(rank: i))
                                        .frame(width: max(geo.size.width * CGFloat(items[i].times) / CGFloat(maxTimes), 4),
                                               height: 5)
                                }
                            }
                            .frame(height: 5)
                            Text("\(items[i].times) 次 · 均 ¥\(String(format: "%.0f", items[i].avg)) / 次")
                                .font(.system(size: 11))
                                .foregroundStyle(.appTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("¥\(Int(items[i].total).formatted())")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.appPrimary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.appTertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("高频消费合计")
                        .font(.system(size: 12))
                        .foregroundStyle(.appSecondary)
                    Text("单笔小，合起来不少")
                        .font(.system(size: 11))
                        .foregroundStyle(.appTertiary)
                }
                Spacer()
                Text("¥\(Int(total).formatted())")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.appTeal)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(item: $selectedItem) { item in
            FrequencyInsightDetailSheet(item: item)
        }
    }
}

struct FrequencyInsightDetailSheet: View {
    let item: FrequencyInsightItem

    @Environment(\.dismiss) private var dismiss
    @State private var metricMode: FrequencyMetricMode = .amount

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 3 列统计——直接作为视觉 hero（emoji + 名字已经在 nav title 里）
                    HStack(spacing: 8) {
                        insightMetric(label: String(localized: "累计金额"), value: "¥\(Int(item.total).formatted())")
                        insightMetric(label: String(localized: "出现次数"), value: String(localized: "\(item.times) 次"))
                        insightMetric(label: String(localized: "单次均额"), value: "¥\(Int(item.avg.rounded()).formatted())")
                    }

                    FrequencyDistributionChart(buckets: item.distribution, mode: $metricMode)
                }
                .padding(16)
            }
            .background(Color.appBg)
            // Nav title 一次性承担分类标识：emoji + 名字 + "分析"
            .navigationTitle("\(item.emoji) \(item.name.localizedCategoryName)分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                // 只读视图——用「关闭」/ X icon 语义，避免「完成」暗示用户做了某事
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.appSecondary)
                            .frame(width: 28, height: 28)
                            .background(Color.appBg.opacity(0.001))   // 扩大点击区
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
            }
        }
        // 按内容真实高度给 detent，避免大片空白；同时提供 .large 让用户想拉就拉到顶
        .presentationDetents([.height(450), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBg)
    }

    @ViewBuilder
    private func insightMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.appSecondary)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.appPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct FrequencyDistributionChart: View {
    let buckets: [FrequencyDistributionBucket]
    @Binding var mode: FrequencyMetricMode

    @State private var selectedID: FrequencyDistributionBucket.ID?

    private var chartMaxValue: Double {
        let values = buckets.map { value(for: $0) }
        return max(values.max() ?? 0, 1)
    }

    private var selectedBucket: FrequencyDistributionBucket? {
        if let selectedID { return buckets.first(where: { $0.id == selectedID }) }
        return buckets.first(where: { value(for: $0) > 0 }) ?? buckets.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            // Header：模式段控（紧凑居左）+ 当前选中柱的详情（居右）
            // 用 firstTextBaseline 让段控文字基线与右侧数字基线对齐
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                modeToggle
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 10 }
                Spacer(minLength: 8)
                if let bucket = selectedBucket {
                    HStack(spacing: 4) {
                        Text(bucket.detailLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(.appPrimary)
                        Text(formattedValue(for: bucket))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.appTeal)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 20) {
                ForEach(buckets) { bucket in
                    VStack(spacing: 8) {
                        // 柱子区——只在 0 值时显示 baseline，避免多柱底连成视觉分割线
                        ZStack(alignment: .bottom) {
                            if value(for: bucket) > 0 {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedBucket?.id == bucket.id ? Color.appAccent : Color.appAccent.opacity(0.16))
                                    .frame(height: barHeight(for: bucket))
                                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedBucket?.id)
                            } else {
                                // 仅 0 值时显示 baseline，传达"这周存在但无支出"
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.appSeparator.opacity(0.6))
                                    .frame(height: 3)
                            }
                        }
                        // 限制柱子最大宽度——避免少 bucket 时柱子变成砖块
                        .frame(maxWidth: 40)
                        .frame(height: chartBarMaxHeight, alignment: .bottom)

                        Text(bucket.label)
                            .font(.system(size: 12, weight: selectedBucket?.id == bucket.id ? .semibold : .medium))
                            .foregroundStyle(selectedBucket?.id == bucket.id ? Color.appAccent : Color.appSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedID = bucket.id
                        }
                    }
                }
            }
            .frame(height: chartBarMaxHeight + 8, alignment: .bottom)
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            selectedID = selectedBucket?.id
        }
    }

    /// 紧凑模式段控——只显示选项文字，无外框；选中态白底+阴影；容器底色加深确保对比。
    /// 居左放在 chart card 标题位置，宽度只覆盖必要文字 + padding。
    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(FrequencyMetricMode.allCases) { m in
                Text(m.localizedName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(mode == m ? .appPrimary : .appSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if mode == m {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.appCard)
                                .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            mode = m
                        }
                    }
            }
        }
        .padding(2)
        .background(Color.appSeparator)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func value(for bucket: FrequencyDistributionBucket) -> Double {
        switch mode {
        case .amount: return bucket.amount
        case .frequency: return Double(bucket.count)
        }
    }

    private func formattedValue(for bucket: FrequencyDistributionBucket) -> String {
        switch mode {
        case .amount:
            return "¥\(Int(bucket.amount).formatted())"
        case .frequency:
            return String(localized: "\(bucket.count) 次")
        }
    }

    /// 柱区最大高度——足够大才能展示大额 outlier 与小值的真实差异。
    private var chartBarMaxHeight: CGFloat { 170 }

    /// 柱高计算——平方根缩放：保留排名，但显著放大小值的可视性。
    /// 0 严格为 0（baseline 显示在 ZStack 里）；非 0 至少 8pt 保证可见。
    private func barHeight(for bucket: FrequencyDistributionBucket) -> CGFloat {
        let raw = value(for: bucket)
        guard raw > 0, chartMaxValue > 0 else { return 0 }
        let normalized = sqrt(raw / chartMaxValue)
        return max(CGFloat(normalized) * chartBarMaxHeight, 8)
    }
}

// MARK: - Array safe subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
