import Foundation
import SwiftUI
import SwiftData
import Observation

struct SpendingReferenceStats {
    let averageDailySpending: Double
    let activeDays: Int
    let sampleCalendarDays: Int
}

enum StatsScrollTarget: String {
    case bigTransactions = "stats-big-transactions"
    case frequentSpending = "stats-frequent-spending"
}

enum BillManagementEntryTarget {
    case home
    case `import`
    case export
}

@Observable
final class AppState {
    @ObservationIgnored private var successOverlayDismissWorkItem: DispatchWorkItem?

    // MARK: - Navigation
    var selectedTab: Tab = .today
    var showOnboarding: Bool = false
    var pendingOpenBillManagement: Bool = false
    var pendingBillManagementTarget: BillManagementEntryTarget = .home
    var showRecordSheet: Bool = false
    var showSuccessOverlay: Bool = false
    var showPaywall: Bool = false

    // MARK: - Record sheet state
    var recordType: RecordType = .expense
    var recordAmount: String = ""
    var recordCategoryName: String = "餐饮"
    var recordCategoryEmoji: String = "🍜"
    var recordDate: Date = Date()
    var recordNote: String = ""
    var recordStartTime: Date = Date()
    /// 用户在本次记账中手动碰过分类 chip 后，关闭智能预测覆盖
    var recordCategoryUserTouched: Bool = false

    // MARK: - Success overlay
    var successAmount: String = ""
    var successCategoryLine: String = ""
    var successDetail: String = ""
    var successElapsed: String = ""
    var successInsight: String = ""

    // MARK: - Stats navigation
    var statsView: StatsViewType = .month
    var statsMonthYear: Int = Calendar.current.component(.year, from: Date())
    var statsMonthMo: Int = Calendar.current.component(.month, from: Date())
    var statsYear: Int = Calendar.current.component(.year, from: Date())
    var pendingStatsScrollTarget: StatsScrollTarget?

    // MARK: - Daily average (computed from real data, not a manual budget)
    /// Legacy helper kept for compatibility; uses the same stabilized reference logic as the home page.
    func dailyAverage(transactions: [Transaction]) -> Double {
        spendingReferenceStats(transactions: transactions).averageDailySpending
    }

    func spendingReferenceStats(transactions: [Transaction], now: Date = Date(), maxLookbackDays: Int = 180) -> SpendingReferenceStats {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let maxStart = calendar.date(byAdding: .day, value: -maxLookbackDays, to: today) else {
            return SpendingReferenceStats(averageDailySpending: 0, activeDays: 0, sampleCalendarDays: 0)
        }

        let validExpenses = transactions.filter {
            !$0.isRefunded &&
            $0.isExpense &&
            $0.absoluteAmount > 0 &&
            $0.categoryName != "转账" &&
            $0.date < today
        }

        guard let earliestExpenseDay = validExpenses
            .map({ calendar.startOfDay(for: $0.date) })
            .min() else {
            return SpendingReferenceStats(averageDailySpending: 0, activeDays: 0, sampleCalendarDays: 0)
        }

        let effectiveStart = max(maxStart, earliestExpenseDay)
        let sampleCalendarDays = max(1, (calendar.dateComponents([.day], from: effectiveStart, to: today).day ?? 0))

        let windowExpenses = validExpenses.filter { $0.date >= effectiveStart }
        let groupedByDay = Dictionary(grouping: windowExpenses) { calendar.startOfDay(for: $0.date) }
        let dailyTotals = groupedByDay.values
            .map { dayTransactions in
                dayTransactions.reduce(0) { $0 + $1.absoluteAmount }
            }
            .filter { $0 > 0 }
            .sorted()

        guard !dailyTotals.isEmpty else {
            return SpendingReferenceStats(averageDailySpending: 0, activeDays: 0, sampleCalendarDays: sampleCalendarDays)
        }

        let activeDays = dailyTotals.count
        let lowerIndex = Int(Double(activeDays - 1) * 0.05)
        let upperIndex = Int(Double(activeDays - 1) * 0.95)
        let lowerBound = dailyTotals[lowerIndex]
        let upperBound = dailyTotals[upperIndex]
        let winsorizedTotal = dailyTotals.reduce(0) { partial, value in
            partial + min(max(value, lowerBound), upperBound)
        }

        return SpendingReferenceStats(
            averageDailySpending: winsorizedTotal / Double(activeDays),
            activeDays: activeDays,
            sampleCalendarDays: sampleCalendarDays
        )
    }

    /// Today's total spending
    func todaySpending(transactions: [Transaction]) -> Double {
        let today = Calendar.current.startOfDay(for: Date())
        return transactions
            .filter { !$0.isRefunded && $0.isExpense && $0.date >= today }
            .reduce(0) { $0 + $1.absoluteAmount }
    }

    // MARK: - Onboarding
    func checkOnboarding() {
        let key = "onboarding_shown_v1"
        if !UserDefaults.standard.bool(forKey: key) {
            showOnboarding = true
        }
    }

    func dismissOnboarding(startWithBillManagement: Bool = false) {
        withAnimation(.easeInOut(duration: 0.5)) {
            showOnboarding = false
        }
        UserDefaults.standard.set(true, forKey: "onboarding_shown_v1")
        if startWithBillManagement {
            selectedTab = .mine
            pendingBillManagementTarget = .import
            pendingOpenBillManagement = true
        }
    }

    // MARK: - Record sheet
    func openRecordSheet() {
        recordType = .expense
        recordAmount = ""
        recordCategoryName = "餐饮"
        recordCategoryEmoji = "🍜"
        recordDate = Date()
        recordNote = ""
        recordStartTime = Date()
        recordCategoryUserTouched = false
        showRecordSheet = true
    }

    // MARK: - Smart category prediction
    /// 根据时段、金额、历史记录预测最可能的分类。
    /// 算法：每条历史交易给候选分类加分（最近一笔权重最高，同时段次之，同金额区间再次，总频次保底），最高分胜出。
    /// 无数据时回退到时段硬编码默认值。
    func predictedCategory(
        for date: Date,
        amount: Double?,
        transactions: [Transaction],
        categories: [Category],
        type: RecordType
    ) -> Category? {
        let isExpense = (type == .expense)
        let candidates = categories.filter { $0.isExpense == isExpense }
        guard !candidates.isEmpty else { return nil }

        let relevant = transactions.filter { $0.isExpense == isExpense && !$0.isRefunded }
        guard !relevant.isEmpty else {
            return coldStartCategory(for: date, candidates: candidates)
        }

        let cal = Calendar.current
        let targetHour = cal.component(.hour, from: date)
        let amountBucket = amount.map { Self.amountBucket($0) }
        let recencyThreshold = Date().addingTimeInterval(-30 * 86400)

        var scores: [String: Double] = [:]

        // 信号 1：最近一笔（强信号）
        if let last = relevant.max(by: { $0.date < $1.date }) {
            scores[last.categoryName, default: 0] += 3.0
        }

        for tx in relevant {
            let txHour = cal.component(.hour, from: tx.date)

            // 信号 2：同时段 ±2 小时
            if abs(txHour - targetHour) <= 2 {
                scores[tx.categoryName, default: 0] += 2.0
            }

            // 信号 3：同金额区间
            if let bucket = amountBucket, Self.amountBucket(tx.absoluteAmount) == bucket {
                scores[tx.categoryName, default: 0] += 1.0
            }

            // 信号 4：总频次背景
            scores[tx.categoryName, default: 0] += 0.5

            // 衰减加成：最近 30 天的数据再加一点
            if tx.date > recencyThreshold {
                scores[tx.categoryName, default: 0] += 0.3
            }
        }

        let best = scores.max { $0.value < $1.value }?.key
        if let best, let match = candidates.first(where: { $0.name == best }) {
            return match
        }
        return coldStartCategory(for: date, candidates: candidates)
    }

    private static func amountBucket(_ amount: Double) -> Int {
        switch amount {
        case ..<20:     return 0
        case 20..<100:  return 1
        case 100..<500: return 2
        default:        return 3
        }
    }

    private func coldStartCategory(for date: Date, candidates: [Category]) -> Category? {
        let hour = Calendar.current.component(.hour, from: date)
        let preferred: String
        switch hour {
        case 6..<10:   preferred = "咖啡"
        case 10..<14:  preferred = "餐饮"
        case 17..<21:  preferred = "餐饮"
        default:       preferred = "餐饮"
        }
        return candidates.first(where: { $0.name == preferred })
            ?? candidates.first(where: { $0.name == "餐饮" })
            ?? candidates.first
    }

    func confirmRecord(context: ModelContext, allTransactions: [Transaction] = []) {
        guard let amount = Double(recordAmount), amount > 0 else { return }
        let finalAmount = recordType == .expense ? -amount : amount
        let elapsed = Date().timeIntervalSince(recordStartTime)
        let trimmedNote = recordNote.trimmingCharacters(in: .whitespaces)
        let tx = Transaction(
            name: trimmedNote.isEmpty ? recordCategoryName : trimmedNote,
            categoryName: recordCategoryName,
            categoryEmoji: recordCategoryEmoji,
            amount: finalAmount,
            date: recordDate,
            note: recordNote,
            recordDuration: elapsed
        )
        context.insert(tx)
        try? context.save()
        ensureBillManagementStartDate()

        let localizedCategory = recordCategoryName.localizedCategoryName
        successDetail = "\(trimmedNote.isEmpty ? localizedCategory : trimmedNote) · ¥\(String(format: "%.2f", amount))"
        successAmount = "¥\(String(format: "%.2f", amount))"
        successCategoryLine = "\(recordCategoryEmoji) \(localizedCategory)"
        let elapsedText = String(format: "%.1f", elapsed)
        successElapsed = elapsed < 3
            ? String(format: String(localized: "⚡ 闪速 %@ 秒"), elapsedText)
            : String(format: String(localized: "⚡ %@ 秒"), elapsedText)
        successInsight = computeInsight(tx: tx, allTransactions: allTransactions)

        showRecordSheet = false
        successOverlayDismissWorkItem?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { showSuccessOverlay = true }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.showSuccessOverlay = false }
            self.successOverlayDismissWorkItem = nil
        }
        successOverlayDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
        recordAmount = ""
    }

    func dismissSuccessOverlay(openRecordSheet: Bool = false) {
        successOverlayDismissWorkItem?.cancel()
        successOverlayDismissWorkItem = nil
        withAnimation(.easeOut(duration: 0.25)) {
            showSuccessOverlay = false
        }
        if openRecordSheet {
            self.openRecordSheet()
        }
    }

    // MARK: - Stats navigation
    func changeStatsMonth(_ delta: Int) {
        var mo = statsMonthMo + delta
        var yr = statsMonthYear
        if mo < 1  { mo = 12; yr -= 1 }
        if mo > 12 { mo = 1;  yr += 1 }
        let now = Date()
        let nowY = Calendar.current.component(.year, from: now)
        let nowM = Calendar.current.component(.month, from: now)
        if yr > nowY || (yr == nowY && mo > nowM) { yr = nowY; mo = nowM }
        statsMonthYear = yr
        statsMonthMo   = mo
    }

    // MARK: - Post-record insight
    func computeInsight(tx: Transaction, allTransactions: [Transaction]) -> String {
        guard tx.isExpense else { return "" }
        let cal = Calendar.current
        let now = Date()

        // 本月同类别（不含刚存这笔，按 id 排除）
        let monthSame = allTransactions.filter {
            $0.isExpense &&
            $0.categoryName == tx.categoryName &&
            cal.isDate($0.date, equalTo: now, toGranularity: .month) &&
            $0.id != tx.id
        }
        let countThisMonth = monthSame.count + 1
        let totalThisMonth = monthSame.reduce(0) { $0 + $1.absoluteAmount } + tx.absoluteAmount

        let localizedCategory = tx.categoryName.localizedCategoryName

        // 优先级1：里程碑
        let milestones = [1, 5, 10, 20, 30, 50]
        if milestones.contains(countThisMonth) {
            if countThisMonth == 1 {
                return String(format: String(localized: "这是你本月第一笔%@ %@"), localizedCategory, tx.categoryEmoji)
            } else {
                return String(format: String(localized: "本月第 %d 次%@ %@ · 共花 ¥%d"), countThisMonth, localizedCategory, tx.categoryEmoji, Int(totalThisMonth))
            }
        }

        // 优先级2：今日 vs 日均
        let todayStart = cal.startOfDay(for: now)
        let todayTotal = allTransactions.filter {
            $0.isExpense && !$0.isRefunded && $0.date >= todayStart
        }.reduce(0) { $0 + $1.absoluteAmount }

        let referenceStats = spendingReferenceStats(transactions: allTransactions, now: now)
        let dailyAvg = referenceStats.averageDailySpending
        if referenceStats.activeDays > 1, dailyAvg > 0 {
            if todayTotal > dailyAvg * 1.2 {
                return String(format: String(localized: "今天已超过你的日均 ¥%d，注意一下 👀"), Int(dailyAvg))
            } else if todayTotal < dailyAvg * 0.5 {
                return String(format: String(localized: "今天花得很克制，低于日均 ¥%d 👍"), Int(dailyAvg))
            }
        }

        // 优先级3：本月该类别累计
        return String(format: String(localized: "本月%@已花 ¥%d · 共 %d 笔"), localizedCategory, Int(totalThisMonth), countThisMonth)
    }

    func changeStatsYear(_ delta: Int) {
        let newYear = statsYear + delta
        let nowYear = Calendar.current.component(.year, from: Date())
        statsYear = min(max(newYear, 2020), nowYear)
    }

    func ensureBillManagementStartDate(now: Date = Date()) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AppStorageKeys.billManagementStartDate) == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: AppStorageKeys.billManagementStartDate)
    }
}

// MARK: - Enums
enum Tab: String, CaseIterable {
    case today  = "记录"
    case bill   = "账单"
    case stats  = "统计"
    case mine   = "我的"

    var icon: String {
        switch self {
        case .today:  return "pencil"
        case .bill:   return "doc.text"
        case .stats:  return "chart.bar"
        case .mine:   return "person"
        }
    }
}

enum RecordType {
    case expense, income
}

enum StatsViewType {
    case month, year
}

enum AppStorageKeys {
    static let billManagementStartDate = "bill_management_start_date"
    /// 最近一次 CSV 备份导出成功的时间戳；用于"清空数据"前的备份新鲜度判断
    static let lastCSVExportTimestamp  = "last_csv_export_timestamp"
}
