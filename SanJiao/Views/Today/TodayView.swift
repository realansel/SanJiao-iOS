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
                        .padding(.bottom, 8)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                // 主入口：手记一笔
                Button {
                    if unlockManager.canRecord {
                        appState.openRecordSheet()
                    } else {
                        appState.showPaywall = true
                    }
                } label: {
                    HStack(spacing: 7) {
                        if unlockManager.canRecord {
                            Image("FeatherGlyph")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(unlockManager.canRecord ? String(localized: "记一笔") : String(localized: "试用已结束，点击解锁"))
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .background(
                        unlockManager.canRecord
                            ? AnyShapeStyle(LinearGradient.accentGradient)
                            : AnyShapeStyle(Color.appSecondary.opacity(0.5))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                // 平行入口：说一笔（语音）——记=写、说=说，成对
                if unlockManager.canRecord {
                    Button {
                        appState.openRecordSheet(startVoice: true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("说一笔")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.appAccent)
                        .frame(height: 52)
                        .padding(.horizontal, 18)
                        .background(Color.appAccentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(
            // 不透明底色 + 顶部细分割线——iOS 原生 bottom bar 写法，
            // 列表底部不再被透明渐变"啃掉"，视觉边界清晰。
            Color.appBg
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.appSeparator.opacity(0.6))
                        .frame(height: 0.5)
                }
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

    /// 1.0× 视为节省态——「刚好达到日均」不该报警；> 1.0× 才进入超出态。
    var isSaving: Bool { amount <= baselineValue }
}

// MARK: - Home header
struct HomeHeaderView: View {
    @Binding var mode: TodayMetricMode
    let display: TodayMetricDisplay
    @State private var showReferenceHelp = false

    private var greetingShort: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? String(localized: "早上好") : h < 18 ? String(localized: "下午好") : String(localized: "晚上好")
    }

    private var dateSubtitle: String {
        let dow = [
            String(localized: "周日"), String(localized: "周一"), String(localized: "周二"),
            String(localized: "周三"), String(localized: "周四"), String(localized: "周五"),
            String(localized: "周六")
        ][Calendar.current.component(.weekday, from: Date()) - 1]
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return "\(f.string(from: Date())) · \(dow)"
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
                String(localized: "新的一天，慢慢来"),
                String(localized: "今天还没有支出"),
                String(localized: "钱包还很安静"),
            ]
            return pool[i]
        } else if ratio < 0.2 {
            let pool = [
                String(localized: "一个好的开端"),
                String(localized: "起步轻，接着来"),
                String(localized: "记下了第一笔，节奏不重"),
            ]
            return pool[i]
        } else if ratio < 0.5 {
            let pool = [
                String(localized: "今天的步子稳"),
                String(localized: "继续顺其自然"),
                String(localized: "还有不少空间"),
            ]
            return pool[i]
        } else if ratio < 0.8 {
            let pool = [
                String(localized: "慢慢往前走"),
                String(localized: "今天和往常差不多"),
                String(localized: "节奏自然，继续记"),
            ]
            return pool[i]
        } else if ratio < 1.0 {
            let pool = [
                String(localized: "快接近日均了"),
                String(localized: "差不多到熟悉的位置"),
                String(localized: "再花一点就到日均"),
            ]
            return pool[i]
        } else if ratio < 1.1 {
            let pool = [
                String(localized: "刚好到日均"),
                String(localized: "贴着日均走"),
                String(localized: "和平时差不多"),
            ]
            return pool[i]
        } else if ratio < 1.5 {
            let pool = [
                String(localized: "比日均多了一点 (+\(over)%)"),
                String(localized: "今天稍微超出一点"),
                String(localized: "多花了一些，记清楚就好"),
            ]
            return pool[i]
        } else if ratio < 10.0 {
            let pool = [
                String(localized: "今天比平时多一些"),
                String(localized: "节奏快了一点"),
                String(localized: "比往常高一些"),
            ]
            return pool[i]
        } else if ratio < 50.0 {
            let pool = [
                String(localized: "今天有一笔特别的支出"),
                String(localized: "数字比平时大不少"),
                String(localized: "今天和平时不太一样"),
            ]
            return pool[i]
        } else {
            let pool = [
                String(localized: "今天有一笔很大的支出"),
                String(localized: "记下就行了"),
                String(localized: "数字大，账记清楚就好 (\(times)× 日均)"),
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
                String(localized: "新的月份，慢慢来"),
                String(localized: "本月还没有支出"),
                String(localized: "这个月才刚开始"),
            ]
            return pool[i]
        } else if ratio < 0.6 {
            let pool = [
                String(localized: "本月起步轻"),
                String(localized: "节奏还很松"),
                String(localized: "还有不少空间"),
            ]
            return pool[i]
        } else if ratio < 0.95 {
            let pool = [
                String(localized: "本月慢慢往前走"),
                String(localized: "比参考线略低 (-\(under)%)"),
                String(localized: "节奏稳，还有余地"),
            ]
            return pool[i]
        } else if ratio < 1.08 {
            let pool = [
                String(localized: "本月贴着参考线走"),
                String(localized: "本月节奏自然"),
                String(localized: "和往常的月份差不多"),
            ]
            return pool[i]
        } else if ratio < 1.5 {
            let pool = [
                String(localized: "本月比参考多一点 (+\(over)%)"),
                String(localized: "节奏快了一些"),
                String(localized: "本月花得比往常多些"),
            ]
            return pool[i]
        } else {
            let pool = [
                String(localized: "本月数字比往常大不少"),
                String(localized: "可能有几笔比较集中的支出"),
                String(localized: "账记清楚了，慢慢看就好"),
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
            // ── Compact header row: 问候 + 段控同高度
            HStack(alignment: .center) {
                Text(greetingShort)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.appSecondary)
                Spacer()
                metricSegmentedControl
            }
            .padding(.bottom, 4)

            // ── 日期副标
            Text(dateSubtitle)
                .font(.system(size: 12))
                .foregroundStyle(.appTertiary)
                .padding(.bottom, 24)

            // ── Hero amount（带左右滑动手势切换模式）
            swipeableMetricHero

            // ── 对比条——三阶段统一容器，stage 1 时显示灰槽
            SpendingBar(
                hasBaseline: display.baselineValue > 0,
                ratio: display.ratio,
                isSaving: display.isSaving,
                baselineLabel: display.baselineLabel,
                showsReferenceHelp: display.showsReferenceHelp,
                referenceHelpTitle: display.referenceHelpTitle,
                referenceHelpMessage: display.referenceHelpMessage,
                showReferenceHelp: $showReferenceHelp
            )
            .padding(.bottom, 8)

            // ── Inline 洞察文案
            Text(display.baselineValue > 0 ? spendingComment : display.emptyHint)
                .font(.system(size: 12))
                .foregroundStyle(.appTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var swipeableMetricHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(display.amountTitle)
                .font(.system(size: 13))
                .foregroundStyle(.appTertiary)

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
            .padding(.bottom, 16)
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
    /// 是否已有日均参考（stage 1 时为 false，仅显示灰槽）
    let hasBaseline: Bool
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

    /// 节省态填充颜色——ratio < 0.8 浅紫（轻松），≥ 0.8 标准紫（临近）
    private var savingFillColor: Color {
        ratio < 0.8 ? Color.appAccent.opacity(0.7) : Color.appAccent
    }

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
            // Label 行——节省 / 超支模式都右对齐显示「日均 ¥X」
            // Stage 1 无参考时为空（占位保持高度一致）
            GeometryReader { geo in
                if hasBaseline {
                    baselineMarkerLabel
                        .frame(width: geo.size.width, height: 12, alignment: .trailing)
                }
            }
            .frame(height: 12)

            // Bar 行——上限锁定 100%
            // - Stage 1：纯灰槽
            // - 节省态 (ratio < 1)：灰槽 + 紫色填充（按 ratio 强度，浅 / 标准）
            // - 超支态 (ratio ≥ 1)：满格橙色，倍数靠下方文字传达
            GeometryReader { geo in
                let trackW = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(Color.appSeparator)
                        .frame(height: 7)

                    if hasBaseline {
                        let fillRatio = isSaving ? CGFloat(min(ratio, 1.0)) : 1.0
                        let fillColor = isSaving ? savingFillColor : Color.appOrange
                        shimmerFill(
                            width: max(trackW * fillRatio, 6),
                            color: fillColor,
                            animated: true
                        )
                    }
                }
            }
            .frame(height: 7)
        }
        .onAppear { startShimmer() }
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
                .foregroundStyle(isSaving ? Color.appAccent.opacity(0.85) : Color.appOrange)
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
        VStack(spacing: 10) {
            EmptyStateIcon(systemName: hasAnyTransactions ? "sun.max" : "square.and.pencil")
                .padding(.bottom, 4)

            Text(emptyTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.appSecondary)

            // 无任何数据时不显示副文案——该提示由上方日均进度条负责，避免重复
            if let emptyMessage {
                Text(emptyMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.appTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, hasAnyTransactions ? 72 : 52)
        .padding(.bottom, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var emptyTitle: String {
        if !hasAnyTransactions {
            return String(localized: "开始第一笔记账吧")
        }
        switch mode {
        case .today:
            return String(localized: "今天还没记账")
        case .month:
            return String(localized: "这个月还没记账")
        }
    }

    private var emptyMessage: String? {
        // 无任何数据：交给上方日均进度条提示，这里不重复
        if !hasAnyTransactions { return nil }
        switch mode {
        case .today:
            return String(localized: "随手记一笔，今天就有迹可循")
        case .month:
            return String(localized: "记一笔，慢慢看清这个月的消费")
        }
    }
}

// MARK: - Shared empty state (kept for backward-compat in BillView)
typealias EmptyStateView = TodayEmptyView

