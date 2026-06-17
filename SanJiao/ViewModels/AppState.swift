import Foundation
import SwiftUI
import SwiftData
import Observation
import UIKit

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
    /// 面板出现即自动进入语音聆听（首页「说一笔」入口设置，RecordSheet 消费后清零）
    var recordSheetAutoVoice: Bool = false
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
    /// "你的第 N 笔记账"——累计计数，强调"积累属于自己的账本"
    var successAccumulation: String = ""
    /// 最近 7 天每日末的累计笔数——success overlay 那条荧青线的真实数据，末端 = 第 N 笔
    var successTrendPoints: [Double] = []

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
    /// 打开记账面板。startVoice = true 时，面板出现即直接进入语音聆听
    /// （首页「说一笔」入口用）。RecordSheet.onAppear 消费此标记。
    func openRecordSheet(startVoice: Bool = false) {
        recordType = .expense
        recordAmount = ""
        recordCategoryName = "餐饮"
        recordCategoryEmoji = "🍜"
        recordDate = Date()
        recordNote = ""
        recordStartTime = Date()
        recordCategoryUserTouched = false
        recordSheetAutoVoice = startVoice
        showRecordSheet = true
    }

    // MARK: - Smart category prediction
    /// 返回按预测分数排序后的所有候选分类，第一个为最可能的。
    /// 算法：最近一笔 +3 / 同时段 +2 / 同金额区间 +1 / 总频次 +0.5 / 近 30 天 +0.3。
    /// 无历史数据时按 sortOrder 排序，时段优先分类置顶（冷启动）。
    func predictedCategoriesRanked(
        for date: Date,
        amount: Double?,
        transactions: [Transaction],
        categories: [Category],
        type: RecordType
    ) -> [Category] {
        let isExpense = (type == .expense)
        let candidates = categories.filter { $0.isExpense == isExpense }
        guard !candidates.isEmpty else { return [] }

        let relevant = transactions.filter { $0.isExpense == isExpense && !$0.isRefunded }

        // 冷启动：按 sortOrder 排，但时段优先分类置顶
        guard !relevant.isEmpty else {
            var result = candidates.sorted { $0.sortOrder < $1.sortOrder }
            if let preferred = coldStartCategory(for: date, candidates: candidates),
               let idx = result.firstIndex(where: { $0.id == preferred.id }) {
                let item = result.remove(at: idx)
                result.insert(item, at: 0)
            }
            return result
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

        // 信号 2-5：每笔历史交易加 0.5 保底 + 时段/金额/近期增量；累加到本地变量后一次写回
        for tx in relevant {
            var delta = 0.5
            let txHour = cal.component(.hour, from: tx.date)
            if abs(txHour - targetHour) <= 2 { delta += 2.0 }
            if let bucket = amountBucket, Self.amountBucket(tx.absoluteAmount) == bucket { delta += 1.0 }
            if tx.date > recencyThreshold { delta += 0.3 }
            scores[tx.categoryName, default: 0] += delta
        }

        // 按分数降序，分数相同时按 sortOrder 升序
        return candidates.sorted { a, b in
            let sa = scores[a.name, default: 0]
            let sb = scores[b.name, default: 0]
            if sa != sb { return sa > sb }
            return a.sortOrder < b.sortOrder
        }
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

    func confirmRecord(context: ModelContext, allTransactions: [Transaction] = [], continueRecording: Bool = false) {
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
        // 自学习：用户填过备注 + 选定分类 → 备注成为该分类的「通用」关键词，
        // 下次（含语音记账）出现同样字眼即自动归类。
        if !trimmedNote.isEmpty {
            learnNoteCategory(
                note: trimmedNote,
                type: recordType == .expense ? "expense" : "income",
                categoryName: recordCategoryName,
                categoryEmoji: recordCategoryEmoji,
                context: context
            )
        }
        try? context.save()
        ensureBillManagementStartDate()

        // 「再记」——存完立即清空、继续停留在键盘记下一笔，不弹成功页、不关 sheet。
        // 轻触反馈代替成功页，让用户知道这笔已落库。
        if continueRecording {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            recordAmount = ""
            recordNote = ""
            recordCategoryUserTouched = false   // 解锁排序，让下一笔重新预测分类
            recordStartTime = Date()            // 重新计时，elapsed 才准
            return
        }

        let localizedCategory = recordCategoryName.localizedCategoryName
        successDetail = "\(trimmedNote.isEmpty ? localizedCategory : trimmedNote) · ¥\(String(format: "%.2f", amount))"
        successAmount = "¥\(String(format: "%.2f", amount))"
        successCategoryLine = "\(recordCategoryEmoji) \(localizedCategory)"
        let elapsedText = String(format: "%.1f", elapsed)
        successElapsed = elapsed < 3
            ? String(format: String(localized: "⚡ 闪速 %@ 秒"), elapsedText)
            : String(format: String(localized: "⚡ %@ 秒"), elapsedText)
        successInsight = computeInsight(tx: tx, allTransactions: allTransactions)
        // 累计第几笔（含本次）——排除 tx.id 再 +1，与 computeInsight 同款防御写法
        let totalRecords = allTransactions.filter { $0.id != tx.id }.count + 1
        successAccumulation = String(format: String(localized: "你的第 %d 笔记账"), totalRecords)
        successTrendPoints = computeAccumulationTrend(tx: tx, allTransactions: allTransactions)

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

    /// 备注 → 分类 的自学习：写入/更新一条「通用」MerchantCategoryRule，
    /// 与账单导入纠正共用同一套规则库。匹配在 BillImportManager.inferCategory 里做子串命中。
    private func learnNoteCategory(
        note: String,
        type: String,
        categoryName: String,
        categoryEmoji: String,
        context: ModelContext
    ) {
        let key = MerchantCategoryRule.makeKey(note)
        // 过滤噪音：太短、纯数字、或备注本身就等于分类名（无新信息）
        guard key.count >= 2,
              Double(key) == nil,
              key != MerchantCategoryRule.makeKey(categoryName) else { return }

        let rules = (try? context.fetch(FetchDescriptor<MerchantCategoryRule>())) ?? []
        if let existing = rules.first(where: {
            $0.source == "通用" && $0.type == type && $0.merchantKey == key
        }) {
            existing.categoryName = categoryName
            existing.categoryEmoji = categoryEmoji
            existing.updatedAt = Date()
        } else {
            context.insert(MerchantCategoryRule(
                merchantName: note,
                source: "通用",
                type: type,
                categoryName: categoryName,
                categoryEmoji: categoryEmoji
            ))
        }
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

    /// 最近 7 天「每日末累计笔数」序列——success overlay 荧青线的真实数据。
    /// 含本次（按 tx.recordDate 计入对应日），最后一天的值 = 累计第 N 笔，和 successAccumulation 对齐。
    /// 全部记录都算（含收入），因为"记账"不分收支；退化情况交给绘制端兜底。
    func computeAccumulationTrend(tx: Transaction, allTransactions: [Transaction]) -> [Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // 所有记账日期：排除 tx.id 后再补回本次，避免 allTransactions 是否含 tx 的歧义
        var dates = allTransactions.filter { $0.id != tx.id }.map { $0.date }
        dates.append(tx.date)
        // oldest → today，共 7 天；每天取当日 24:00 之前的累计条数
        return (0..<7).map { offset -> Double in
            let day = cal.date(byAdding: .day, value: -(6 - offset), to: today)!
            let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day))!
            return Double(dates.filter { $0 < dayEnd }.count)
        }
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
