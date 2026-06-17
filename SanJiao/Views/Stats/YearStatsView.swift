import SwiftUI
import SwiftData

struct YearStatsView: View {
    let transactions: [Transaction]
    @Environment(AppState.self) private var appState

    private var isCurrentYear: Bool {
        appState.statsYear == Calendar.current.component(.year, from: Date())
    }

    /// 所有有记录的年份
    private var yearsWithData: Set<Int> {
        Set(transactions.map { Calendar.current.component(.year, from: $0.date) })
    }

    private var yearTx: [Transaction] {
        transactions.filter {
            Calendar.current.component(.year, from: $0.date) == appState.statsYear &&
            !$0.isRefunded && $0.isExpense
        }
    }

    private var totalExpense: Double { yearTx.reduce(0) { $0 + $1.absoluteAmount } }

    private var yearIncomeTx: [Transaction] {
        transactions.filter {
            Calendar.current.component(.year, from: $0.date) == appState.statsYear &&
            !$0.isRefunded && !$0.isExpense
        }
    }

    private var yearIncome: Double { yearIncomeTx.reduce(0) { $0 + $1.absoluteAmount } }
    private var yearSavings: Double { yearIncome - totalExpense }
    private var savingsRate: Double? {
        guard yearIncome > 0 else { return nil }
        return yearSavings / yearIncome
    }
    /// 结余/超出收入 color：盈余用柔和墨绿（金融惯例 + 莫兰迪色调），赤字用橙色（柔性警示）
    private var savingsColor: Color { yearSavings >= 0 ? Color.appGreen : Color.appOrange }
    private var isOverspending: Bool { yearIncome > 0 && yearSavings < 0 }

    // Monthly totals (12 months)
    private var monthlyTotals: [Double] {
        (1...12).map { mo in
            yearTx.filter { Calendar.current.component(.month, from: $0.date) == mo }
                  .reduce(0) { $0 + $1.absoluteAmount }
        }
    }

    private var monthAvg: Double {
        let active = monthlyTotals.filter { $0 > 0 }
        return active.isEmpty ? 0 : active.reduce(0, +) / Double(active.count)
    }

    private var barsData: [BarItem] {
        let now = Date()
        let nowYear = Calendar.current.component(.year, from: now)
        let nowMonth = Calendar.current.component(.month, from: now)
        return (1...12).map { mo in
            let isFuture = appState.statsYear == nowYear && mo > nowMonth
            let isCurrent = appState.statsYear == nowYear && mo == nowMonth
            return BarItem(label: "\(mo)", amount: monthlyTotals[mo-1],
                           isCurrent: isCurrent, isFuture: isFuture, detailLabel: String(localized: "\(mo)月"))
        }
    }

    // Category breakdown
    private var categoryBreakdown: [(name: String, emoji: String, amount: Double, pct: Double)] {
        let grouped = Dictionary(grouping: yearTx, by: \.categoryName)
        return grouped.map { entry -> (name: String, emoji: String, amount: Double, pct: Double) in
            let name = entry.key
            let txs = entry.value
            let emoji = txs.first?.categoryEmoji ?? ""
            let amt = txs.reduce(0) { $0 + $1.absoluteAmount }
            return (name: name, emoji: emoji, amount: amt, pct: totalExpense > 0 ? amt/totalExpense : 0)
        }.sorted { $0.amount > $1.amount }.prefix(5).map { $0 }
    }

    private var freqCategories: [FrequencyInsightItem] {
        let grouped = Dictionary(grouping: yearTx, by: \.categoryName)
        return grouped.compactMap { entry -> FrequencyInsightItem? in
            let name = entry.key
            let txs = entry.value
            guard txs.count >= 8 else { return nil }
            let emoji = txs.first?.categoryEmoji ?? ""
            let total = txs.reduce(0) { $0 + $1.absoluteAmount }
            let buckets = (1...12).map { month -> FrequencyDistributionBucket in
                let monthTransactions = txs.filter { Calendar.current.component(.month, from: $0.date) == month }
                return FrequencyDistributionBucket(
                    label: String(localized: "\(month)月"),
                    detailLabel: String(localized: "\(month)月"),
                    amount: monthTransactions.reduce(0) { $0 + $1.absoluteAmount },
                    count: monthTransactions.count
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

    private var freqTotal: Double {
        freqCategories.reduce(0) { $0 + $1.total }
    }

    // MARK: - 季度收支比（收入/支出）
    // 锚点：今年取本季度，往年取该年第四季度；向前回溯共 6 个季度
    fileprivate struct QuarterPoint: Identifiable {
        let id: String          // "25Q3"
        let label: String       // "Q3" 显示文字
        let yearShort: String   // "25"
        let ratio: Double?      // nil 表示无收入
        let income: Double
        let expense: Double
    }

    private var quarterlyRatioPoints: [QuarterPoint] {
        let cal = Calendar.current
        let now = Date()
        let currentYear = cal.component(.year, from: now)
        let currentMonth = cal.component(.month, from: now)
        let isCurYear = appState.statsYear == currentYear
        let anchorYear = appState.statsYear
        let anchorQuarter = isCurYear ? ((currentMonth - 1) / 3 + 1) : 4

        return (0..<6).reversed().map { offset in
            var year = anchorYear
            var quarter = anchorQuarter - offset
            while quarter < 1 { year -= 1; quarter += 4 }
            let startMonth = (quarter - 1) * 3 + 1
            let endMonth = startMonth + 2

            var inc = 0.0, exp = 0.0
            for tx in transactions where !tx.isRefunded {
                let c = cal.dateComponents([.year, .month], from: tx.date)
                guard let yy = c.year, let mm = c.month,
                      yy == year, mm >= startMonth, mm <= endMonth else { continue }
                if tx.isExpense { exp += tx.absoluteAmount } else { inc += tx.absoluteAmount }
            }
            let ratio: Double? = (inc > 0 && exp > 0) ? inc / exp : nil
            let yearShort = String(year % 100)
            return QuarterPoint(id: "\(year)Q\(quarter)", label: "Q\(quarter)",
                                yearShort: yearShort, ratio: ratio,
                                income: inc, expense: exp)
        }
    }

    /// 至少要有 2 个有效点才有"趋势"
    private var hasRatioTrend: Bool {
        quarterlyRatioPoints.compactMap { $0.ratio }.count >= 2
    }

    // Highlights
    private var highlights: (highest: (Double, Int), lowest: (Double, Int)) {
        let nonZero = monthlyTotals.enumerated().filter { $0.element > 0 }
        let highest = nonZero.max(by: { $0.element < $1.element })
        let lowest  = nonZero.min(by: { $0.element < $1.element })
        return ((highest?.element ?? 0, (highest?.offset ?? 0) + 1),
                (lowest?.element ?? 0, (lowest?.offset ?? 0) + 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Year nav 已上移到 StatsView 统一管理（支持滚动后塌缩进 nav bar）

            // Donut + legend
            HStack(spacing: 24) {
                DonutChart(
                    segments: categoryBreakdown.indices.map { i in
                        (categoryBreakdown[i].amount, donutColor(idx: i))
                    },
                    centerText: totalExpense < 1000
                        ? "¥\(Int(totalExpense))"
                        : "¥\(Int(totalExpense / 1000))k",
                    centerLabel: isCurrentYear ? String(localized: "今年支出") : String(localized: "全年支出")
                )
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(categoryBreakdown.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(donutColor(idx: i))
                                .frame(width: 9, height: 9)
                            Text(categoryBreakdown[i].name.localizedCategoryName)
                                .font(.system(size: 13))
                                .foregroundStyle(.appSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                            Text("\(Int(categoryBreakdown[i].pct * 100))%")
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
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // 12-month bar chart
            BarChartCard(title: String(localized: "全年支出趋势"), bars: barsData)
                .padding(.horizontal, 16).padding(.bottom, 12)

            // Savings
            savingsCard
                .padding(.horizontal, 16).padding(.bottom, 12)

            // 季度收支比趋势（至少 2 个有效季度才显示）
            if hasRatioTrend {
                IncomeExpenseRatioCard(points: quarterlyRatioPoints)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }

            // Year highlights——inline 3 列，去卡中卡
            if !yearTx.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("年度亮点")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                    HStack(spacing: 0) {
                        hlItem(
                            label: String(localized: "支出最高"),
                            value: highlights.highest.0 > 0 ? "¥\(Int(highlights.highest.0).formatted())" : "—",
                            sub: highlights.highest.0 > 0 ? String(localized: "\(highlights.highest.1)月") : ""
                        )
                        savingsDivider
                        hlItem(
                            label: String(localized: "月均支出"),
                            value: "¥\(Int(monthAvg).formatted())",
                            sub: String(localized: "平均")
                        )
                        savingsDivider
                        hlItem(
                            label: String(localized: "支出最低"),
                            value: highlights.lowest.0 > 0 ? "¥\(Int(highlights.lowest.0).formatted())" : "—",
                            sub: highlights.lowest.0 > 0 ? String(localized: "\(highlights.lowest.1)月") : ""
                        )
                    }
                }
                .padding(16)
                .background(Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            // Top categories
            if !categoryBreakdown.isEmpty {
                TopCategoriesCard(title: String(localized: "支出最多"), items: Array(categoryBreakdown.prefix(3)))
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }

            if !freqCategories.isEmpty {
                FreqSpendingCard(
                    items: freqCategories,
                    total: freqTotal,
                    badgeText: String(localized: "这一年常出现")
                )
                .padding(.horizontal, 16).padding(.bottom, 12)
            }

            Spacer(minLength: 20)
        }
    }

    private func hlItem(label: String, value: String, sub: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.appSecondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.appPrimary)
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundStyle(.appTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 圆环段颜色——和 MonthStatsView 同款 rank 梯度，保持品牌紫一致
    private func donutColor(idx: Int) -> Color {
        switch idx {
        case 0:  return .appAccent
        case 1:  return .appAccent.opacity(0.65)
        case 2:  return .appAccent.opacity(0.45)
        case 3:  return .appAccent.opacity(0.3)
        default: return Color.appSeparator
        }
    }

    // MARK: - Savings card

    private var savingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isOverspending ? String(localized: "年度收支") : String(localized: "年度结余"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.appPrimary)

            // Inline 3 列——和 BillView 顶部 summary 同款语言（去卡中卡）
            HStack(spacing: 0) {
                savingsCell(label: String(localized: "总收入"), value: yearIncome, color: .appGreen)
                savingsDivider
                savingsCell(label: String(localized: "总支出"), value: totalExpense, color: .appPrimary)
                savingsDivider
                savingsCell(
                    label: isOverspending ? String(localized: "超出收入") : String(localized: "结余"),
                    value: abs(yearSavings),
                    color: savingsColor
                )
            }

            if isOverspending {
                let spendRatio = min(totalExpense / yearIncome, 2.0)
                ratioProgressBlock(
                    leadLabel: String(localized: "支出占收入"),
                    pctText: "\(Int((totalExpense / yearIncome * 100).rounded()))%",
                    pctColor: .appOrange,
                    leftFillRatio: min(1.0 / spendRatio, 1),
                    leftColor: Color.appGreen.opacity(0.5),     // 左段=收入覆盖部分，柔和墨绿
                    rightFillRatio: 1.0,
                    rightColor: .appOrange,
                    leftCaption: String(localized: "收入"),
                    leftCaptionColor: .appGreen,
                    rightCaption: String(localized: "支出"),
                    rightCaptionColor: .appOrange
                )
            } else if let rate = savingsRate {
                // 盈余态：bar 始终满格，左段（储蓄）+ 右段（支出）共同分割收入 100%。
                // 同色系深浅区分——都属于"你的收入"。
                ratioProgressBlock(
                    leadLabel: String(localized: "储蓄率"),
                    pctText: "\(Int((rate * 100).rounded()))%",
                    pctColor: .appGreen,
                    leftFillRatio: max(0, min(1, rate)),
                    leftColor: .appGreen,
                    rightFillRatio: 1.0,
                    rightColor: Color.appGreen.opacity(0.2),    // 浅墨绿——同色系，表"也是收入的一部分"
                    leftCaption: String(localized: "储蓄"),
                    leftCaptionColor: .appGreen,
                    rightCaption: String(localized: "支出"),
                    rightCaptionColor: .appSecondary
                )
            } else {
                Text("在记录页添加收入后，这里会显示今年攒下多少钱 💰")
                    .font(.system(size: 12))
                    .foregroundStyle(.appTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 通用 progress + 双标签 block——两种 case 共用，确保视觉权重对等
    @ViewBuilder
    private func ratioProgressBlock(
        leadLabel: String,
        pctText: String,
        pctColor: Color,
        leftFillRatio: Double,    // 左半段填充比 (0~1)
        leftColor: Color,
        rightFillRatio: Double,   // 右半段填充比 (赤字态 = 1.0 满；盈余态 = 0)
        rightColor: Color,
        leftCaption: String,
        leftCaptionColor: Color,
        rightCaption: String,
        rightCaptionColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(leadLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.appSecondary)
                Spacer()
                Text(pctText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(pctColor)
            }
            // 进度条——Capsule 5pt + 0.7 track，统一其他卡的 bar 样式
            GeometryReader { geo in
                let leftEnd = geo.size.width * CGFloat(leftFillRatio)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.appSeparator.opacity(0.7))
                        .frame(height: 5)
                    Capsule()
                        .fill(leftColor)
                        .frame(width: max(leftEnd, 4), height: 5)
                    if rightFillRatio > 0 {
                        Capsule()
                            .fill(rightColor)
                            .frame(width: geo.size.width - leftEnd, height: 5)
                            .offset(x: leftEnd)
                    }
                }
            }
            .frame(height: 5)
            // 双标签：左半段终点位置标 leftCaption，右端标 rightCaption
            GeometryReader { geo in
                let leftEnd = geo.size.width * CGFloat(leftFillRatio)
                ZStack(alignment: .leading) {
                    Text(leftCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(leftCaptionColor)
                        .frame(width: leftEnd, alignment: .trailing)
                    Text(rightCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(rightCaptionColor)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: 16)
        }
    }

    private func savingsCell(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.appSecondary)
            Text("¥\(Int(value).formatted())")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var savingsDivider: some View {
        Rectangle()
            .fill(Color.appSeparator.opacity(0.6))
            .frame(width: 0.5, height: 28)
    }

}

// MARK: - 收支比趋势卡片

private struct IncomeExpenseRatioCard: View {
    let points: [YearStatsView.QuarterPoint]

    /// 左侧 y 轴标签区宽度（与下方 X 标签的 leading inset 必须一致）
    private let leftPad: CGFloat = 28
    private let rightPad: CGFloat = 4

    @State private var selectedIndex: Int? = nil

    /// Y 轴最大值（自适应，至少到 1.5，保证 1.0 基线居中可见）
    private var yMax: Double {
        let validRatios = points.compactMap { $0.ratio }
        let maxV = validRatios.max() ?? 1.0
        return max(1.5, maxV * 1.15)
    }

    /// 最后一个有效季度的索引（默认选中）
    private var defaultIndex: Int? {
        for i in (0..<points.count).reversed() where points[i].ratio != nil { return i }
        return nil
    }

    private var activeIndex: Int? { selectedIndex ?? defaultIndex }
    private var activePoint: YearStatsView.QuarterPoint? {
        guard let i = activeIndex, i < points.count else { return nil }
        return points[i]
    }

    /// 收支比 → 颜色（用于 0.32 数字本身）
    /// > 1：盈余 紫色（品牌色，正向但不喜悦）
    /// = 1：打平 灰色
    /// < 1：赤字 橙色（柔性警示，与 BillView 结余色一致）
    private func ratioColor(for ratio: Double) -> Color {
        if ratio > 1.0 { return .appAccent }
        if ratio < 1.0 { return .appOrange }
        return .appSecondary
    }

    /// 根据收支比给出鼓励/提示文案
    /// 视角：收入对生活的承载力。越高代表赚钱能力越强；越低则给予鼓励而非批评。
    private func encouragement(for ratio: Double?) -> (text: String, color: Color) {
        guard let r = ratio else {
            return (String(localized: "这一季还没有收入记录"), .appTertiary)
        }
        switch r {
        case ..<0.5:
            return (String(localized: "这一季还在蓄力，更大的收入正在路上"), .appAccent)
        case 0.5..<1.0:
            return (String(localized: "已经很接近收支打平，再加一点点就好"), .appAccent)
        case 1.0..<1.01:
            return (String(localized: "刚好收支打平，下一季就能开始攒钱"), .appSecondary)
        case 1.01..<2.0:
            return (String(localized: "收入稳稳覆盖开销，节奏很健康"), .appGreen)
        case 2.0..<5.0:
            return (String(localized: "收入跑赢支出不少，结余很从容"), .appGreen)
        case 5.0..<10.0:
            return (String(localized: "赚钱能力很强，收入远超日常开销"), .appGreen)
        default:
            return (String(localized: "收入远远跑赢支出，财务自由度很高"), .appGreen)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 标题 + 鼓励小字作为一个紧凑单元（彼此间距小，与图表保持 14pt）
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("季度收支比")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                    Spacer()
                    if let p = activePoint, let r = p.ratio {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%.2f", r))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(ratioColor(for: r))
                            Text("\(p.label) '\(p.yearShort)")
                                .font(.system(size: 10))
                                .foregroundStyle(.appTertiary)
                        }
                    }
                }

                // 根据当前选中季度的比值，给出对应的鼓励文案
                let tip = encouragement(for: activePoint?.ratio)
                Text(tip.text)
                    .font(.system(size: 11))
                    .foregroundStyle(tip.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            chartCanvas
                .frame(height: 140)

            // X 轴标签：与图表的"格中心"逻辑严格对齐
            HStack(spacing: 0) {
                Color.clear.frame(width: leftPad)
                ForEach(Array(points.enumerated()), id: \.element.id) { i, p in
                    VStack(spacing: 1) {
                        Text(p.label)
                            .font(.system(size: 11, weight: i == activeIndex ? .semibold : .medium))
                            .foregroundStyle(i == activeIndex ? .appPrimary : .appSecondary)
                        Text("'\(p.yearShort)")
                            .font(.system(size: 9))
                            .foregroundStyle(.appTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                Color.clear.frame(width: rightPad)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var chartCanvas: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let n = points.count
            let topPad: CGFloat = 14
            let bottomPad: CGFloat = 8
            let plotW = w - leftPad - rightPad
            let plotH = h - topPad - bottomPad
            // 每格宽度，点落在"格中心"
            let slotW = plotW / CGFloat(max(n, 1))

            let xFor: (Int) -> CGFloat = { idx in
                leftPad + (CGFloat(idx) + 0.5) * slotW
            }
            let point: (Int, Double) -> CGPoint = { index, ratio in
                let x = xFor(index)
                let normalized = min(max(ratio / yMax, 0), 1)
                let y = topPad + plotH * (1 - CGFloat(normalized))
                return CGPoint(x: x, y: y)
            }

            let breakEvenY = topPad + plotH * (1 - CGFloat(1.0 / yMax))

            let validIndexed: [(Int, Double)] = points.enumerated().compactMap { (i, p) in
                guard let r = p.ratio else { return nil }
                return (i, r)
            }

            ZStack {
                Rectangle()
                    .fill(Color.appBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // y=1 基线
                Path { p in
                    p.move(to: CGPoint(x: leftPad, y: breakEvenY))
                    p.addLine(to: CGPoint(x: w - rightPad, y: breakEvenY))
                }
                .stroke(Color.appSeparator, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // y 轴标签
                VStack {
                    Text(String(format: "%.1f", yMax))
                        .font(.system(size: 9)).foregroundStyle(.appTertiary)
                    Spacer()
                    Text("1.0")
                        .font(.system(size: 9)).foregroundStyle(.appSecondary)
                    Spacer()
                    Text("0")
                        .font(.system(size: 9)).foregroundStyle(.appTertiary)
                }
                .frame(width: leftPad - 4, height: plotH, alignment: .trailing)
                .position(x: (leftPad - 4) / 2, y: topPad + plotH / 2)

                // 选中竖线
                if let i = activeIndex, points[i].ratio != nil {
                    Path { p in
                        let x = xFor(i)
                        p.move(to: CGPoint(x: x, y: topPad))
                        p.addLine(to: CGPoint(x: x, y: h - bottomPad))
                    }
                    .stroke(Color.appAccent.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }

                // 折线
                if validIndexed.count >= 2 {
                    Path { p in
                        let pts = validIndexed.map { point($0.0, $0.1) }
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                // 数据点（可点击）——折线保持品牌紫，活动点用荧青（与 App 图标的数据点同源）
                ForEach(Array(validIndexed.enumerated()), id: \.offset) { _, item in
                    let pt = point(item.0, item.1)
                    let isActive = activeIndex == item.0
                    ZStack {
                        if isActive {
                            // 选中态光晕：荧青
                            Circle().fill(Color.appTeal.opacity(0.2)).frame(width: 22, height: 22)
                        }
                        Circle()
                            .fill(isActive ? Color.appTeal : Color.appCard)
                            .frame(width: isActive ? 11 : 9, height: isActive ? 11 : 9)
                            .overlay(Circle().stroke(isActive ? Color.appTeal : Color.appAccent, lineWidth: 2))
                            .shadow(color: isActive ? Color.appTeal.opacity(0.4) : .clear,
                                    radius: isActive ? 4 : 0, y: isActive ? 2 : 0)
                    }
                    .position(pt)
                }

                // 透明可点击列（命中区比小圆点大很多）
                HStack(spacing: 0) {
                    Color.clear.frame(width: leftPad)
                    ForEach(Array(points.enumerated()), id: \.element.id) { i, p in
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard p.ratio != nil else { return }
                                selectedIndex = i
                            }
                    }
                    Color.clear.frame(width: rightPad)
                }
            }
        }
    }
}
