import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(UnlockManager.self) private var unlockManager
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @AppStorage("big_transaction_threshold_percent") private var bigTransactionThresholdPercent = 5.0
    @State private var metricMode: TodayMetricMode = .today

    private enum ReferenceQuality {
        case insufficient
        case preliminary
        case stable
    }

    private var referenceStats: SpendingReferenceStats {
        appState.spendingReferenceStats(transactions: transactions)
    }

    private var todayTransactions: [Transaction] {
        let start = Calendar.current.startOfDay(for: Date())
        return transactions.filter { $0.date >= start }
    }

    private var monthTransactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return []
        }
        return transactions.filter { $0.date >= monthStart && $0.date <= now }
    }

    private var monthExpenseTransactions: [Transaction] {
        monthTransactions.filter { !$0.isRefunded && $0.isExpense }
    }

    private var displayedTransactions: [Transaction] {
        switch metricMode {
        case .today: todayTransactions
        case .month: monthTransactions
        }
    }

    private var monthReference: Double {
        referenceDailyAverage * Double(monthElapsedDays)
    }

    private var shouldShowMonthInsightCards: Bool {
        metricMode == .month && metricDisplay.baselineValue > 0 && monthSpending > monthReference
    }

    private var monthBigTransactionThreshold: Double {
        monthSpending * (bigTransactionThresholdPercent / 100)
    }

    private var monthBigTransactions: [Transaction] {
        guard monthSpending > 0 else { return [] }
        return monthExpenseTransactions
            .filter { $0.absoluteAmount >= monthBigTransactionThreshold }
            .sorted { $0.absoluteAmount > $1.absoluteAmount }
    }

    private var topFrequentCategory: FrequencyInsightItem? {
        let grouped = Dictionary(grouping: monthExpenseTransactions, by: \.categoryName)
        return grouped.compactMap { entry -> FrequencyInsightItem? in
            let txs = entry.value
            guard txs.count >= 5 else { return nil }
            let total = txs.reduce(0) { $0 + $1.absoluteAmount }
            return FrequencyInsightItem(
                name: entry.key,
                emoji: txs.first?.categoryEmoji ?? "",
                times: txs.count,
                avg: total / Double(txs.count),
                total: total,
                distribution: []
            )
        }
        .sorted { lhs, rhs in
            lhs.times == rhs.times ? lhs.total > rhs.total : lhs.times > rhs.times
        }
        .first
    }

    private var todaySpending: Double {
        todayTransactions
            .filter { !$0.isRefunded && $0.isExpense }
            .reduce(0) { $0 + $1.absoluteAmount }
    }

    // 过去 180 天（不含今天）的活跃日均支出，作为更稳定的参考线
    private var referenceDailyAverage: Double {
        referenceStats.averageDailySpending
    }

    private var referenceActiveDays: Int {
        referenceStats.activeDays
    }

    private var referenceSampleDays: Int {
        referenceStats.sampleCalendarDays
    }

    private var referenceQuality: ReferenceQuality {
        if referenceActiveDays < 5 { return .insufficient }
        if referenceActiveDays < 15 { return .preliminary }
        return .stable
    }

    private var monthSpending: Double {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return 0
        }
        return transactions
            .filter { !$0.isRefunded && $0.isExpense && $0.date >= monthStart && $0.date <= now }
            .reduce(0) { $0 + $1.absoluteAmount }
    }

    private var monthElapsedDays: Int {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return 1
        }
        return (calendar.dateComponents([.day], from: monthStart, to: calendar.startOfDay(for: now)).day ?? 0) + 1
    }

    private var metricDisplay: TodayMetricDisplay {
        switch metricMode {
        case .today:
            let todayBaselineLabel: String = switch referenceQuality {
            case .insufficient: ""
            case .preliminary: String(localized: "初步日均 ¥\(Int(referenceDailyAverage))")
            case .stable: String(localized: "日均 ¥\(Int(referenceDailyAverage))")
            }
            return TodayMetricDisplay(
                mode: .today,
                amountTitle: String(localized: "今日支出"),
                amount: todaySpending,
                comparisonLabel: String(localized: "今日"),
                baselineLabel: todayBaselineLabel,
                baselineValue: referenceQuality == .insufficient ? 0 : referenceDailyAverage,
                emptyHint: String(localized: "先记录 5 天消费，这里会出现你的日均参考"),
                showsReferenceHelp: false,
                referenceHelpTitle: "",
                referenceHelpMessage: ""
            )
        case .month:
            let monthReference = referenceDailyAverage * Double(monthElapsedDays)
            let monthBaselineLabel: String = switch referenceQuality {
            case .insufficient: ""
            case .preliminary: String(localized: "初步参考 ¥\(Int(monthReference))")
            case .stable: String(localized: "本月参考 ¥\(Int(monthReference))")
            }
            return TodayMetricDisplay(
                mode: .month,
                amountTitle: String(localized: "本月支出"),
                amount: monthSpending,
                comparisonLabel: String(localized: "本月"),
                baselineLabel: monthBaselineLabel,
                baselineValue: referenceQuality == .insufficient ? 0 : monthReference,
                emptyHint: String(localized: "先记录 5 天消费，这里会出现你的本月参考线"),
                showsReferenceHelp: true,
                referenceHelpTitle: String(localized: "什么是本月参考？"),
                referenceHelpMessage: referenceHelpMessage
            )
        }
    }

    private var referenceHelpMessage: String {
        let periodText: String
        if referenceSampleDays <= 0 {
            periodText = String(localized: "近一段时间")
        } else if referenceSampleDays < 180 {
            periodText = String(localized: "过去 \(referenceSampleDays) 天")
        } else {
            periodText = String(localized: "过去半年")
        }

        if referenceQuality == .insufficient {
            return String(localized: "这条线会根据你\(periodText)里有消费记录的日子，慢慢长成更贴近你的参考。现在样本还少，先多记几天看看。")
        }

        return String(localized: "这是根据你\(periodText)里有消费记录的日常支出，做过温和平滑后得到的参考线。它不是预算，也不是限制，只是帮你看看这个月大概花得快还是慢。")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HomeHeaderView(
                        mode: $metricMode,
                        display: metricDisplay
                    )

                    if shouldShowMonthInsightCards {
                        monthInsightCards
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    if displayedTransactions.isEmpty {
                        TodayEmptyView(
                            hasAnyTransactions: !transactions.isEmpty,
                            mode: metricMode
                        )
                    } else {
                        TransactionListCard(
                            transactions: displayedTransactions,
                            showsDateInMeta: metricMode == .month
                        )
                            .padding(.horizontal, 16)
                    }

                    if transactions.count > displayedTransactions.count {
                        Button(action: { appState.selectedTab = .bill }) {
                            Text(displayedTransactions.isEmpty ? String(localized: "查看历史账单 →") : String(localized: "查看全部账单 →"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.appAccent)
                                .padding(.vertical, 16)
                                .padding(.horizontal, 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text("数据仅存储在本设备  ·  私密安全")
                        .font(.system(size: 10))
                        .foregroundStyle(.appTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                        .padding(.bottom, 114)
                }
            }
            .background(Color.appBg)
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom) {
                recordButton
            }
        }
    }

    private var recordButton: some View {
        VStack(spacing: 0) {
            // 试用期剩余提示（最后1天才显示，不打扰日常使用）
            if let badge = unlockManager.trialBadgeText,
               unlockManager.state.daysRemaining == 0 {
                Button { appState.showPaywall = true } label: {
                    Text(badge)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.appSecondary)
                        .padding(.bottom, 4)
                }
                .buttonStyle(.plain)
            }

            Button {
                if unlockManager.canRecord {
                    appState.openRecordSheet()
                } else {
                    appState.showPaywall = true
                }
            } label: {
                HStack(spacing: 6) {
                    if !unlockManager.canRecord {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(unlockManager.canRecord ? String(localized: "记一笔") : String(localized: "试用已结束，点击解锁"))
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(height: 60)
                .frame(maxWidth: 288)
                .frame(maxWidth: .infinity)
                .background(
                    unlockManager.canRecord
                        ? AnyShapeStyle(LinearGradient.accentGradient)
                        : AnyShapeStyle(Color.appSecondary.opacity(0.5))
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color.appAccent.opacity(unlockManager.canRecord ? 0.14 : 0), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .background(
            LinearGradient(
                colors: [Color.appBg.opacity(0), Color.appBg.opacity(0.92), Color.appBg],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var monthInsightCards: some View {
        HStack(spacing: 12) {
            monthInsightCard(
                title: String(localized: "大额消费"),
                accent: Color(hex: "FFB457"),
                valueText: monthBigTransactions.isEmpty ? String(localized: "本月暂无明显大额") : String(localized: "\(monthBigTransactions.count) 笔"),
                detailText: monthBigTransactions.first.map {
                    "\($0.categoryEmoji) \(Int($0.absoluteAmount).formatted())"
                } ?? String(localized: "去统计页看完整明细"),
                footerText: monthBigTransactions.isEmpty ? String(localized: "看看这个月最突出的支出") : String(localized: "去统计页看完整大额明细"),
                target: .bigTransactions
            )

            monthInsightCard(
                title: String(localized: "高频消费"),
                accent: Color.appAccent,
                valueText: topFrequentCategory == nil ? String(localized: "本月暂无高频项") : String(localized: "\(topFrequentCategory?.times ?? 0) 次"),
                detailText: topFrequentCategory.map {
                    "\($0.emoji) \($0.name.localizedCategoryName)"
                } ?? String(localized: "去统计页看完整分布"),
                footerText: topFrequentCategory == nil ? String(localized: "看看这个月最常出现的消费") : String(localized: "去统计页看频次与金额分布"),
                target: .frequentSpending
            )
        }
    }

    @ViewBuilder
    private func monthInsightCard(title: String, accent: Color, valueText: String, detailText: String, footerText: String, target: StatsScrollTarget) -> some View {
        Button {
            appState.statsView = .month
            let now = Date()
            appState.statsMonthYear = Calendar.current.component(.year, from: now)
            appState.statsMonthMo = Calendar.current.component(.month, from: now)
            appState.pendingStatsScrollTarget = target
            appState.selectedTab = .stats
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.appTertiary)
                }
                .padding(.bottom, 10)

                Text(valueText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.bottom, 6)

                Text(detailText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.appSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Divider()
                    .padding(.vertical, 12)

                Text(footerText)
                    .font(.system(size: 11))
                    .foregroundStyle(.appTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Today metric mode

enum TodayMetricMode: String, CaseIterable {
    case today = "今日"
    case month = "本月"

    var localizedName: String {
        switch self {
        case .today: String(localized: "今日")
        case .month: String(localized: "本月")
        }
    }
}

struct TodayMetricDisplay {
    let mode: TodayMetricMode
    let amountTitle: String
    let amount: Double
    let comparisonLabel: String
    let baselineLabel: String
    let baselineValue: Double
    let emptyHint: String
    let showsReferenceHelp: Bool
    let referenceHelpTitle: String
    let referenceHelpMessage: String

    var ratio: Double {
        guard baselineValue > 0 else { return 0 }
        return amount / baselineValue
    }

    var isSaving: Bool { amount < baselineValue }
}

// MARK: - Home header
struct HomeHeaderView: View {
    @Binding var mode: TodayMetricMode
    let display: TodayMetricDisplay
    @State private var showReferenceHelp = false

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let dow = [String(localized: "周日"), String(localized: "周一"), String(localized: "周二"), String(localized: "周三"), String(localized: "周四"), String(localized: "周五"), String(localized: "周六")][Calendar.current.component(.weekday, from: Date()) - 1]
        let greet = h < 12 ? String(localized: "早上好") : h < 18 ? String(localized: "下午好") : String(localized: "晚上好")
        return String(localized: "\(greet) · \(dow)")
    }

    // MARK: - Tiered spending comment

    /// 每天轮换一次模板，同一天内保持一致
    private var dailyIndex: Int {
        (Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0) % 3
    }

    private var spendingComment: String {
        switch display.mode {
        case .today:
            return todaySpendingComment
        case .month:
            return monthSpendingComment
        }
    }

    private var todaySpendingComment: String {
        let ratio = display.ratio
        let pct   = Int(ratio * 100)
        let over  = pct - 100
        let times = Int(ratio)
        let i     = dailyIndex

        if ratio == 0 {
            let pool = [
                String(localized: "今天还没花钱，钱包在放空"),
                String(localized: "今天还没有支出，节奏很轻"),
                String(localized: "今日账单还是空白，先慢慢开始"),
            ]
            return pool[i]
        } else if ratio < 0.2 {
            let pool = [
                String(localized: "日均的 \(pct)%，少即是多，今天你做到了"),
                String(localized: "日均的 \(pct)%，今天支出不多，挺轻松"),
                String(localized: "日均的 \(pct)%，今天整体很克制"),
            ]
            return pool[i]
        } else if ratio < 0.5 {
            let pool = [
                String(localized: "日均的 \(pct)%，把钱留给更值得的地方"),
                String(localized: "日均的 \(pct)%，今天的支出比较温和"),
                String(localized: "日均的 \(pct)%，今天还留了不少余地"),
            ]
            return pool[i]
        } else if ratio < 0.8 {
            let pool = [
                String(localized: "日均的 \(pct)%，今天整体偏稳"),
                String(localized: "日均的 \(pct)%，今天花得有分寸"),
                String(localized: "日均的 \(pct)%，今天的节制，是明天的余地"),
            ]
            return pool[i]
        } else if ratio < 1.0 {
            let pool = [
                String(localized: "日均的 \(pct)%，今天很稳，存的是将来某天的任性"),
                String(localized: "日均的 \(pct)%，今天快到日均了"),
                String(localized: "日均的 \(pct)%，今天整体还算平稳"),
            ]
            return pool[i]
        } else if ratio < 1.1 {
            let pool = [
                String(localized: "贴着日均走，不多不少，这就叫生活节奏"),
                String(localized: "今天和日均差不多，节奏挺自然"),
                String(localized: "今天基本贴着日均走，比较稳"),
            ]
            return pool[i]
        } else if ratio < 1.5 {
            let pool = [
                String(localized: "超日均 \(over)%，今天比平时快一点"),
                String(localized: "超日均 \(over)%，偶尔多花一点，也很正常"),
                String(localized: "超日均 \(over)%，账记清楚了，心里会更稳"),
            ]
            return pool[i]
        } else if ratio < 10.0 {
            let pool = [
                String(localized: "日均的 \(pct)%，今天开销比较集中"),
                String(localized: "日均的 \(pct)%，今天明显高于平时"),
                String(localized: "日均的 \(pct)%，大手笔的日子，总会有几天"),
            ]
            return pool[i]
        } else if ratio < 50.0 {
            let pool = [
                String(localized: "日均的 \(times) 倍，今天应该有一笔比较特别的支出"),
                String(localized: "日均的 \(times) 倍，这类开销不常见，记下来更有参考价值"),
                String(localized: "日均的 \(times) 倍，今天的支出和平时差得比较多"),
            ]
            return pool[i]
        } else {
            let pool = [
                String(localized: "日均的 \(times) 倍，今天有一笔非常大的支出"),
                String(localized: "日均的 \(times) 倍，这样的消费会明显拉高今天的总额"),
                String(localized: "日均的 \(times) 倍，回头看看这笔记录，会更容易理解今天"),
            ]
            return pool[i]
        }
    }

    private var monthSpendingComment: String {
        let ratio = display.ratio
        let pct = Int(ratio * 100)
        let over = pct - 100
        let under = 100 - pct
        let i = dailyIndex

        if ratio == 0 {
            let pool = [
                String(localized: "本月还没有明显支出，和参考比会慢很多"),
                String(localized: "本月暂时还很轻，节奏明显慢于参考"),
                String(localized: "这个月刚开始，当前支出还远低于参考"),
            ]
            return pool[i]
        } else if ratio < 0.6 {
            let pool = [
                String(localized: "本月比参考慢了 \(under)%，整体还很轻"),
                String(localized: "本月支出明显慢于参考，留白还很多"),
                String(localized: "本月目前比参考慢不少，节奏比较松"),
            ]
            return pool[i]
        } else if ratio < 0.95 {
            let pool = [
                String(localized: "本月比参考慢了 \(under)%，整体还挺从容"),
                String(localized: "本月支出比参考慢一些，还有余地"),
                String(localized: "本月目前低于参考，节奏比较稳"),
            ]
            return pool[i]
        } else if ratio < 1.08 {
            let pool = [
                String(localized: "本月和参考差不多，整体挺稳"),
                String(localized: "本月基本贴着参考线走，不紧不慢"),
                String(localized: "本月目前和参考接近，节奏自然"),
            ]
            return pool[i]
        } else if ratio < 1.5 {
            let pool = [
                String(localized: "本月比参考线快 \(over)%，知道钱去哪儿就不焦虑"),
                String(localized: "本月支出比参考快了 \(over)%，先看清楚主要花在了哪里"),
                String(localized: "本月比参考多了一点，但账清楚了，心会更稳"),
            ]
            return pool[i]
        } else {
            let pool = [
                String(localized: "本月比参考快了 \(over)%，可能有几笔比较集中的支出"),
                String(localized: "本月支出明显高于参考，先看看主要花在了哪里"),
                String(localized: "本月开销跑得比较快，账在这里，慢慢看就好"),
            ]
            return pool[i]
        }
    }
	
    private var amountParts: (String, String) {
        let cents = Int((display.amount * 100).rounded())
        return (String(cents / 100), String(format: ".%02d", cents % 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            swipeableMetricHeader

            // ── Zone 3: Daily-avg comparison ────────────────────────────────
            if display.baselineValue > 0 {
                HStack(spacing: 8) {
                    Text(display.comparisonLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.appSecondary)

                    SpendingBar(
                        ratio: display.ratio,
                        isSaving: display.isSaving,
                        baselineLabel: display.baselineLabel,
                        showsReferenceHelp: display.showsReferenceHelp,
                        referenceHelpTitle: display.referenceHelpTitle,
                        referenceHelpMessage: display.referenceHelpMessage,
                        showReferenceHelp: $showReferenceHelp
                    )
                }
                .padding(.bottom, 10)

                Text(spendingComment)
                    .font(.system(size: 12))
                    .foregroundStyle(.appTertiary)
            } else {
                Text(display.emptyHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.appTertiary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var swipeableMetricHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(greeting)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.appSecondary)
                .padding(.bottom, 18)

            metricSegmentedControl
                .padding(.bottom, 18)

            Text(display.amountTitle)
                .font(.system(size: 13))
                .foregroundStyle(.appTertiary)
                .padding(.bottom, 6)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("¥")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.appSecondary)
                Text(amountParts.0)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.appPrimary)
                    .tracking(-2)
                    .contentTransition(.numericText(value: display.amount))
                Text(amountParts.1)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.appTertiary)
                    .padding(.leading, 2)
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    if value.translation.width < -44 {
                        switchMode(.month)
                    } else if value.translation.width > 44 {
                        switchMode(.today)
                    }
                }
        )
    }

    private var metricSegmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(TodayMetricMode.allCases, id: \.self) { item in
                Button {
                    switchMode(item)
                } label: {
                    Text(item.localizedName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(mode == item ? .appPrimary : .appTertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 54, minHeight: 30)
                        .background {
                            if mode == item {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.appCard)
                                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.appSeparator.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private func switchMode(_ newMode: TodayMetricMode) {
        guard mode != newMode else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            mode = newMode
        }
    }

}

// MARK: - Spending comparison bar

struct SpendingBar: View {
    /// amount / baseline — unbounded. 1.0 = exactly baseline, 1.4 = 40 % over.
    let ratio: Double
    let isSaving: Bool
    /// Label shown above the marker when the amount exceeds baseline.
    let baselineLabel: String
    let showsReferenceHelp: Bool
    let referenceHelpTitle: String
    let referenceHelpMessage: String
    @Binding var showReferenceHelp: Bool

    @State private var shimmerPhase: CGFloat = -0.4

    // ─── Semantics ───────────────────────────────────────────────────────────
    // Saving  (ratio < 1): bar total = dailyAvg.
    //   Green fill  = ratio * trackW  (today's spend as % of avg)
    //   Gray track  = remaining room to avg
    //   Marker      = right end  (shown as external label in HomeHeaderView)
    //
    // Spending (ratio ≥ 1): bar total = today's spending.
    //   Soft accent = (1/ratio) * trackW  (daily-avg portion)
    //   Purple flow = remaining trackW    (the overage)
    //   Marker line = at (1/ratio) * trackW with label above
    // ─────────────────────────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 3) {
            // Label row — 两种模式都在进度条上方显示参考标签：
            // 超支模式定位在基准线 marker 上方；节省模式右对齐。
            GeometryReader { geo in
                if isSaving {
                    baselineMarkerLabel
                        .frame(width: geo.size.width, height: 12, alignment: .trailing)
                } else {
                    let rawMarkerX = geo.size.width / CGFloat(ratio)
                    let labelWidth = estimatedLabelWidth
                    let clampedMarkerX = min(
                        max(rawMarkerX, labelWidth / 2),
                        max(geo.size.width - (labelWidth / 2), labelWidth / 2)
                    )
                    baselineMarkerLabel
                        .fixedSize()
                        .position(x: clampedMarkerX, y: 6)
                }
            }
            .frame(height: 12)

            // Bar row
            GeometryReader { geo in
                let trackW   = geo.size.width
                // In saving mode: markerX is the right end (trackW).
                // In spending mode: markerX = proportion where daily avg sits.
                let markerX  = isSaving ? trackW : trackW / CGFloat(ratio)
                let baseFillW = isSaving
                    ? trackW * CGFloat(min(ratio, 1.0))   // today's portion of avg
                    : markerX                              // daily-avg portion of today
                let overflowW = isSaving ? CGFloat(0) : trackW - markerX

                ZStack(alignment: .leading) {
                    // Gray track — only in saving mode (shows room left to avg)
                    if isSaving {
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(Color.appSeparator)
                            .frame(height: 7)
                    }

                    // Green fill (saving) or soft base (spending)
                    shimmerFill(
                        width: max(baseFillW, 6),
                        color: isSaving ? Color.appGreen : Color.appAccent.opacity(0.35),
                        animated: isSaving
                    )

                    // Purple flowing overflow (spending only)
                    if !isSaving && overflowW > 0 {
                        shimmerFill(
                            width: overflowW,
                            color: Color.appAccent,
                            animated: true
                        )
                        .offset(x: markerX)
                    }

                    // Marker line (right end in saving, proportional in spending)
                    if !isSaving {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.appAccent.opacity(0.55))
                            .frame(width: 2, height: 14)
                            .offset(x: markerX - 1, y: -3.5)
                    }
                }
            }
            .frame(height: 7)
        }
        .onAppear  { startShimmer() }
        .onChange(of: isSaving) { _, _ in startShimmer() }
    }

    // MARK: - Baseline marker label（超支/节省两种模式共用）

    @ViewBuilder
    private var baselineMarkerLabel: some View {
        HStack(spacing: 2) {
            if showsReferenceHelp {
                Button {
                    showReferenceHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.appTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showReferenceHelp, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(referenceHelpTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.appPrimary)
                        Text(referenceHelpMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.appSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(width: 220, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
                }
            }

            Text(baselineLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSaving ? Color.appGreen : Color.appAccent.opacity(0.7))
                .fixedSize()
        }
    }

    // MARK: - Shared shimmer fill

    @ViewBuilder
    private func shimmerFill(width: CGFloat, color: Color, animated: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3.5)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.65), color],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(width: width, height: 7)
            .overlay {
                if animated {
                    LinearGradient(
                        stops: [
                            .init(color: .clear,               location: 0),
                            .init(color: .white.opacity(0.55), location: 0.5),
                            .init(color: .clear,               location: 1),
                        ],
                        startPoint: UnitPoint(x: shimmerPhase - 0.25, y: 0.5),
                        endPoint:   UnitPoint(x: shimmerPhase + 0.25, y: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3.5))
                }
            }
    }

    // MARK: - Animation

    private func startShimmer() {
        shimmerPhase = -0.4
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            shimmerPhase = 1.4
        }
    }

    private var estimatedLabelWidth: CGFloat {
        CGFloat(baselineLabel.count) * 5.8 + (showsReferenceHelp ? 24 : 0)
    }
}

// MARK: - Today empty state
struct TodayEmptyView: View {
    let hasAnyTransactions: Bool
    let mode: TodayMetricMode

    var body: some View {
        VStack(spacing: 0) {
            Text(hasAnyTransactions ? "🌤️" : "🪙")
                .font(.system(size: 40))
                .opacity(0.55)
                .padding(.bottom, 14)

            Text(emptyTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.appSecondary)
                .padding(.bottom, 8)

            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundStyle(.appTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 20)
        }
        .padding(.top, hasAnyTransactions ? 72 : 52)
        .padding(.bottom, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var emptyTitle: String {
        if !hasAnyTransactions {
            return String(localized: "还没有账单记录")
        }
        switch mode {
        case .today:
            return String(localized: "今天还没开始记录")
        case .month:
            return String(localized: "这个月还没有账单")
        }
    }

    private var emptyMessage: String {
        if !hasAnyTransactions {
            return String(localized: "记下几笔后，这里会慢慢出现你的今日与本月参考。")
        }
        switch mode {
        case .today:
            return String(localized: "今天的消费会出现在这里。")
        case .month:
            return String(localized: "切到本月时，这里会展示你这个月的账单。")
        }
    }
}

// MARK: - Shared empty state (kept for backward-compat in BillView)
typealias EmptyStateView = TodayEmptyView
