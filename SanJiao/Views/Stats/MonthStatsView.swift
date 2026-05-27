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

            let label: String
            switch i {
            case 5: label = isNow ? String(localized: "本周") : String(localized: "当周")
            case 4: label = isNow ? String(localized: "上周") : String(localized: "前周")
            default: label = f.string(from: periodEnd)
            }

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
            // Month navigator
            HStack(spacing: 12) {
                navBtn(disabled: false) { appState.changeStatsMonth(-1) }
                Text("\(String(appState.statsMonthYear))年\(appState.statsMonthMo)月")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                navBtn(isNext: true, disabled: isNow) { appState.changeStatsMonth(1) }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

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
                // Donut + legend
                HStack(spacing: 24) {
                    DonutChart(
                        segments: categoryBreakdown.enumerated().map { (i, item) in (item.amount, donutColor(idx: i)) },
                        centerText: "¥\(Int(totalExpense).formatted())",
                        centerLabel: isNow ? String(localized: "本月支出") : String(localized: "\(appState.statsMonthMo)月支出")
                    )
                    .frame(width: 110, height: 110)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(categoryBreakdown.enumerated()), id: \.offset) { i, item in
                            HStack(spacing: 8) {
                                Circle().fill(donutColor(idx: i)).frame(width: 10, height: 10)
                                Text(item.name.localizedCategoryName).font(.system(size: 13)).foregroundStyle(.appSecondary).frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(Int(item.pct * 100))%").font(.system(size: 13, weight: .semibold)).foregroundStyle(.appPrimary)
                            }
                        }
                    }
                }
                .padding(24)
                .background(Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
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
                        badgeText: String(localized: "这个月常出现"),
                        distributionTitle: String(localized: "月内分布")
                    )
                    .id(StatsScrollTarget.frequentSpending.rawValue)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
            }

            Spacer(minLength: 20)
        }
    }

    private func donutColor(idx: Int) -> Color {
        let colors: [Color] = [.appAccent, Color(hex: "FF9F0A"), Color(hex: "34C759"), Color(hex: "FF3B30"), Color(hex: "AEAEB2")]
        return colors[idx % colors.count]
    }

    @ViewBuilder
    private func navBtn(isNext: Bool = false, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(isNext ? "›" : "‹")
                .font(.system(size: 14))
                .foregroundStyle(disabled ? .appTertiary : .appSecondary)
                .frame(width: 30, height: 30)
                .background(Color.appSeparator)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
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
            VStack(spacing: 2) {
                Text(centerText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.appPrimary)
                    .tracking(-0.5)
                Text(centerLabel)
                    .font(.system(size: 10))
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

    private var maxAmount: Double { bars.filter { !$0.isFuture }.map(\.amount).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题行：选中时右侧显示该期金额
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                Spacer()
                if let idx = selectedIndex, let bar = bars[safe: idx] {
                    HStack(spacing: 4) {
                        Text(bar.detailLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(.appSecondary)
                        Text("¥\(Int(bar.amount).formatted())")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.appAccent)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: selectedIndex)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(bars.indices, id: \.self) { i in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(barColor(bars[i], selected: selectedIndex == i))
                            .frame(height: barHeight(bars[i]))
                            .scaleEffect(y: selectedIndex == i ? 1.06 : 1, anchor: .bottom)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selectedIndex)
                        Text(bars[i].label)
                            .font(.system(size: 10, weight: selectedIndex == i ? .bold : .medium))
                            .foregroundStyle(selectedIndex == i ? Color.appAccent : Color.appTertiary)
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
            .frame(height: 108, alignment: .bottom)
        }
        .padding(20)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func barColor(_ bar: BarItem, selected: Bool) -> Color {
        if bar.isFuture { return Color.appSeparator.opacity(0.5) }
        if selected     { return Color.appAccent }
        if bar.isCurrent { return Color.appAccent.opacity(0.75) }
        return Color.appAccentSoft
    }

    private func barHeight(_ bar: BarItem) -> CGFloat {
        if bar.isFuture { return 4 }
        return maxAmount > 0 ? max(CGFloat(bar.amount / maxAmount) * 80, 4) : 4
    }
}

struct TopCategoriesCard: View {
    let title: String
    let items: [(name: String, emoji: String, amount: Double, pct: Double)]

    private var maxAmount: Double { items.map { $0.amount }.max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.appPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(items.indices, id: \.self) { i in
                if i > 0 { Divider().padding(.leading, 68) }
                HStack(spacing: 12) {
                    Text("\(i + 1)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.appTertiary)
                        .frame(width: 16, alignment: .center)
                    Text(items[i].emoji)
                        .font(.system(size: 18))
                        .frame(width: 36, height: 36)
                        .background(Color.appBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(items[i].name.localizedCategoryName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.appPrimary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color.appSeparator).frame(height: 3)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(i == 0 ? Color.appAccent : i == 1 ? Color.appTertiary : Color(hex: "C7C7CC"))
                                        .frame(width: geo.size.width * CGFloat(items[i].amount / maxAmount), height: 3)
                                }
                            }.frame(height: 3)
                            Text("\(Int(items[i].pct * 100))%")
                                .font(.system(size: 11))
                                .foregroundStyle(.appSecondary)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                    Text("¥\(Int(items[i].amount).formatted())")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
    @State private var editNameTx: Transaction?
    @State private var editNameText = ""
    @State private var editAmountTx: Transaction?
    @State private var editAmountText = ""
    @State private var deleteCandidateTx: Transaction?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("大额消费")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                    Text("单笔超 ¥\(Int(threshold)) · 占本月 \(formatPercent(thresholdPercent))+")
                        .font(.system(size: 11))
                        .foregroundStyle(.appTertiary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("共 \(allTransactions.count) 笔")
                        .font(.system(size: 12))
                        .foregroundStyle(.appTertiary)
                    Button {
                        activeSheet = .thresholdSettings
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.appTertiary)
                            .frame(width: 28, height: 28)
                            .background(Color.appBg)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("调整大额消费线")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ForEach(transactions, id: \.id) { tx in
                if tx.id != transactions.first?.id { Divider().padding(.leading, 68) }
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
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.visible)
            case .actionMenu(let tx):
                TransactionActionSheet(
                    tx: tx,
                    onEditName: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            editNameText = tx.name
                            editNameTx = tx
                        }
                    },
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
                    onToggleRefund: { toggleRefund(tx) },
                    onDelete: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            deleteCandidateTx = tx
                        }
                    }
                )
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
            case .categoryPicker(let tx):
                CategoryPickerSheet(isExpense: tx.isExpense) { name, emoji in
                    tx.categoryName = name
                    tx.categoryEmoji = emoji
                    try? context.save()
                }
            }
        }
        .alert("修改名称", isPresented: Binding(
            get: { editNameTx != nil },
            set: { if !$0 { editNameTx = nil } }
        )) {
            TextField("名称", text: $editNameText)
            Button("保存") {
                if let tx = editNameTx,
                   !editNameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    tx.name = editNameText.trimmingCharacters(in: .whitespaces)
                    try? context.save()
                }
                editNameTx = nil
            }
            Button("取消", role: .cancel) { editNameTx = nil }
        } message: {
            if let tx = editNameTx { Text("当前：\(tx.name)") }
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
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(Color.appBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.appPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(dayString(tx.date))
                        .font(.system(size: 12))
                        .foregroundStyle(.appSecondary)
                    Text(dayOfWeek(tx.date))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.appWarning)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.appWarningSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    // Percentage of month
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.appPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            activeSheet = .actionMenu(tx)
        }
    }

    private func toggleRefund(_ tx: Transaction) {
        tx.isRefunded.toggle()
        try? context.save()
        activeSheet = nil
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("大额消费线")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.appPrimary)
                Text("我们默认用 5% 作为温和提醒线，你也可以按自己的消费节奏微调。")
                    .font(.system(size: 13))
                    .foregroundStyle(.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 18)

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
                        .background(thresholdPercent == option ? Color.appWarning : Color.appBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.appTertiary)
                .padding(.horizontal, 2)

            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(Color.appBg)
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
    @State private var editNameTx: Transaction?
    @State private var editNameText = ""
    @State private var editAmountTx: Transaction?
    @State private var editAmountText = ""
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
                        onEditName: {
                            activeSheet = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                editNameText = tx.name
                                editNameTx = tx
                            }
                        },
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
                        onToggleRefund: { toggleRefund(tx) },
                        onDelete: {
                            activeSheet = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                deleteCandidateTx = tx
                            }
                        }
                    )
                    .presentationDetents([.height(430)])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(24)
                case .categoryPicker(let tx):
                    CategoryPickerSheet(isExpense: tx.isExpense) { name, emoji in
                        tx.categoryName = name
                        tx.categoryEmoji = emoji
                        try? context.save()
                    }
                }
            }
            .alert("修改名称", isPresented: Binding(
                get: { editNameTx != nil },
                set: { if !$0 { editNameTx = nil } }
            )) {
                TextField("名称", text: $editNameText)
                Button("保存") {
                    if let tx = editNameTx,
                       !editNameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        tx.name = editNameText.trimmingCharacters(in: .whitespaces)
                        try? context.save()
                    }
                    editNameTx = nil
                }
                Button("取消", role: .cancel) { editNameTx = nil }
            } message: {
                if let tx = editNameTx { Text("当前：\(tx.name)") }
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
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(Color.appBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
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

    private func toggleRefund(_ tx: Transaction) {
        tx.isRefunded.toggle()
        try? context.save()
        activeSheet = nil
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
    let distributionTitle: String

    @State private var selectedItem: FrequencyInsightItem?

    private var maxTimes: Int { items.map { $0.times }.max() ?? 1 }

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
                if i > 0 { Divider().padding(.leading, 54) }
                Button {
                    selectedItem = items[i]
                } label: {
                    HStack(spacing: 10) {
                        Text(items[i].emoji)
                            .font(.system(size: 18))
                            .frame(width: 28, alignment: .center)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(items[i].name.localizedCategoryName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.appPrimary)
                                .lineLimit(1)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color.appSeparator).frame(height: 3)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.appAccent.opacity(0.28))
                                        .frame(width: geo.size.width * CGFloat(items[i].times) / CGFloat(maxTimes), height: 3)
                                }
                            }.frame(height: 3)
                            Text("\(items[i].times) 次 · 均 ¥\(String(format: "%.0f", items[i].avg)) / 次")
                                .font(.system(size: 11))
                                .foregroundStyle(.appTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("¥\(Int(items[i].total).formatted())")
                                .font(.system(size: 15, weight: .semibold))
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
                    Text("次数看着轻，合在一起更清楚")
                        .font(.system(size: 11))
                        .foregroundStyle(.appTertiary)
                }
                Spacer()
                Text("¥\(Int(total).formatted())")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.appPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(item: $selectedItem) { item in
            FrequencyInsightDetailSheet(item: item, distributionTitle: distributionTitle)
        }
    }
}

struct FrequencyInsightDetailSheet: View {
    let item: FrequencyInsightItem
    let distributionTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var metricMode: FrequencyMetricMode = .amount

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(item.emoji)
                                .font(.system(size: 24))
                                .frame(width: 44, height: 44)
                                .background(Color.appAccentSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name.localizedCategoryName)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.appPrimary)
                                Text(distributionTitle)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.appSecondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            insightMetric(label: String(localized: "累计金额"), value: "¥\(Int(item.total).formatted())")
                            insightMetric(label: String(localized: "出现次数"), value: String(localized: "\(item.times) 次"))
                            insightMetric(label: String(localized: "单次均额"), value: "¥\(Int(item.avg.rounded()).formatted())")
                        }
                    }

                    HStack(spacing: 0) {
                        ForEach(FrequencyMetricMode.allCases) { mode in
                            Text(mode.localizedName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(metricMode == mode ? .appPrimary : .appSecondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(metricMode == mode ? Color.appCard : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        metricMode = mode
                                    }
                                }
                        }
                    }
                    .padding(2)
                    .background(Color.appSeparator)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    FrequencyDistributionChart(buckets: item.distribution, mode: metricMode)
                }
                .padding(16)
            }
            .background(Color.appBg)
            .navigationTitle("\(item.name.localizedCategoryName)分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.appAccent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
    let mode: FrequencyMetricMode

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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(mode == .amount ? String(localized: "金额分布") : String(localized: "频次分布"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                Spacer()
                if let bucket = selectedBucket {
                    HStack(spacing: 4) {
                        Text(bucket.detailLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(.appSecondary)
                        Text(formattedValue(for: bucket))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.appAccent)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(buckets) { bucket in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(selectedBucket?.id == bucket.id ? Color.appAccent : Color.appAccentSoft)
                            .frame(height: barHeight(for: bucket))
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedBucket?.id)

                        Text(bucket.label)
                            .font(.system(size: 10, weight: selectedBucket?.id == bucket.id ? .bold : .medium))
                            .foregroundStyle(selectedBucket?.id == bucket.id ? Color.appAccent : Color.appTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
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
            .frame(height: 138, alignment: .bottom)
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            selectedID = selectedBucket?.id
        }
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

    private func barHeight(for bucket: FrequencyDistributionBucket) -> CGFloat {
        let normalized = value(for: bucket) / chartMaxValue
        return max(CGFloat(normalized) * 96, 8)
    }
}

// MARK: - Array safe subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
