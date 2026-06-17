import SwiftUI
import SwiftData

private struct DaySection: Identifiable {
    var id: Date
    var transactions: [Transaction]
}

/// 年月对——避开元组类型推断瓶颈（namedtuple 在 SwiftUI 视图里编译极慢）
struct YearMonth: Hashable {
    let year: Int
    let month: Int

    /// 从一组交易中提取出现过的 (年, 月)，总是包含当前年月（即使无数据），按时间倒序。
    static func availableMonths(from transactions: [Transaction]) -> [YearMonth] {
        let cal = Calendar.current
        var seen = Set<String>()
        var result: [YearMonth] = []
        for tx in transactions {
            let comps = cal.dateComponents([.year, .month], from: tx.date)
            guard let y = comps.year, let m = comps.month else { continue }
            let key = "\(y)|\(m)"
            if seen.insert(key).inserted {
                result.append(YearMonth(year: y, month: m))
            }
        }
        let now = cal.dateComponents([.year, .month], from: Date())
        if let y = now.year, let m = now.month, !seen.contains("\(y)|\(m)") {
            result.append(YearMonth(year: y, month: m))
        }
        result.sort { a, b in
            if a.year != b.year { return a.year > b.year }
            return a.month > b.month
        }
        return result
    }
}

// 通过 KVO 监听父级 UIScrollView 的 contentOffset，SwiftUI PreferenceKey 在非 Lazy 滚动时不可靠
// internal 可见性——StatsView 也复用同款滚动探针
struct ScrollOffsetDetector: UIViewRepresentable {
    @Binding var offset: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(offset: $offset) }
    func makeUIView(context: Context) -> UIView { context.coordinator.view }
    func updateUIView(_ uiView: UIView, context: Context) {}

    class Coordinator: NSObject {
        let view = TrackerView()
        init(offset: Binding<CGFloat>) { view.offsetBinding = offset }
    }

    class TrackerView: UIView {
        var offsetBinding: Binding<CGFloat>?
        private var kvoToken: NSKeyValueObservation?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard kvoToken == nil else { return }
            // 向上遍历找到 UIScrollView
            var v: UIView? = superview
            while let current = v {
                if let sv = current as? UIScrollView {
                    kvoToken = sv.observe(\.contentOffset, options: .new) { [weak self] sv, _ in
                        DispatchQueue.main.async {
                            self?.offsetBinding?.wrappedValue = sv.contentOffset.y
                        }
                    }
                    return
                }
                v = current.superview
            }
        }
    }
}

struct BillView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var viewYear: Int  = Calendar.current.component(.year,  from: Date())
    @State private var viewMonth: Int = Calendar.current.component(.month, from: Date())

    // MARK: Multi-select state
    @State private var isSelecting             = false
    @State private var selectedIDs: Set<UUID>  = []
    @State private var showBatchCategoryPicker = false
    @State private var showDeleteConfirm       = false

    // MARK: Filter state
    @State private var filterWeeks: Set<Int>         = []
    @State private var filterCategories: Set<String> = []
    @State private var showFilterSheet              = false
    @State private var showMonthPicker               = false
    @State private var billScrollOffset: CGFloat     = 0     // UIScrollView contentOffset.y，向下滚动时增大

    // MARK: Derived

    private var monthTransactions: [Transaction] {
        allTransactions.filter {
            let comps = Calendar.current.dateComponents([.year, .month], from: $0.date)
            return comps.year == viewYear && comps.month == viewMonth
        }
    }

    // Four-week month: 1-7 → 1, 8-14 → 2, 15-21 → 3, 22-end → 4
    private func weekOfMonth(for date: Date) -> Int {
        let day = Calendar.current.component(.day, from: date)
        return min((day - 1) / 7 + 1, 4)
    }

    // Available weeks that actually have transactions this month
    private var availableWeeks: [Int] {
        Array(Set(monthTransactions.map { weekOfMonth(for: $0.date) })).sorted()
    }

    // Available categories that appear this month
    private var availableCategories: [(name: String, emoji: String)] {
        var seen = Set<String>()
        var result: [(String, String)] = []
        for tx in monthTransactions where !seen.contains(tx.categoryName) {
            seen.insert(tx.categoryName)
            result.append((tx.categoryName, tx.categoryEmoji))
        }
        return result.sorted { $0.0 < $1.0 }
    }

    // Range label for a week chip, e.g. "1-7日"
    private func weekRangeLabel(_ week: Int) -> String {
        var comps = DateComponents()
        comps.year = viewYear; comps.month = viewMonth; comps.day = 1
        let daysInMonth = Calendar.current.range(
            of: .day, in: .month,
            for: Calendar.current.date(from: comps) ?? Date()
        )?.count ?? 31
        let start = (week - 1) * 7 + 1
        let end   = week == 4 ? daysInMonth : min(week * 7, daysInMonth)
        return String(localized: "\(start)-\(end)日")
    }

    // Filtered transaction list
    private var filteredMonthTransactions: [Transaction] {
        monthTransactions.filter {
            (filterWeeks.isEmpty || filterWeeks.contains(weekOfMonth(for: $0.date))) &&
            (filterCategories.isEmpty || filterCategories.contains($0.categoryName))
        }
    }

    private var isFiltering: Bool { !filterWeeks.isEmpty || !filterCategories.isEmpty }

    private var displayExpense: Double {
        filteredMonthTransactions.filter { !$0.isRefunded && $0.isExpense }.reduce(0) { $0 + $1.absoluteAmount }
    }
    private var displayIncome: Double {
        filteredMonthTransactions.filter { !$0.isRefunded && $0.isIncome }.reduce(0) { $0 + $1.absoluteAmount }
    }

    private var groupedByDay: [DaySection] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: filteredMonthTransactions) { tx in
            cal.startOfDay(for: tx.date)
        }
        return groups.sorted { $0.key > $1.key }
                     .map { DaySection(id: $0.key, transactions: $0.value) }
    }

    private var isCurrentMonth: Bool {
        let now = Date()
        return viewYear  == Calendar.current.component(.year,  from: now) &&
               viewMonth == Calendar.current.component(.month, from: now)
    }

    /// 头部塌缩阈值——和 StatsView 保持一致
    private var isHeaderCollapsed: Bool { billScrollOffset > 80 }

    // All IDs visible after filtering (for "全选")
    private var allMonthIDs: Set<UUID> { Set(filteredMonthTransactions.map(\.id)) }
    private var allSelected: Bool { !allMonthIDs.isEmpty && allMonthIDs.isSubset(of: selectedIDs) }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // KVO 探针：零高度，放在内容最顶部，监听 UIScrollView 滚动
                    ScrollOffsetDetector(offset: $billScrollOffset)
                        .frame(height: 0)

                    header
                        .opacity(isHeaderCollapsed ? 0 : 1)
                        .frame(maxHeight: isHeaderCollapsed ? 0 : nil, alignment: .top)
                        .clipped()
                        .animation(.easeInOut(duration: 0.18), value: isHeaderCollapsed)
                    summaryCards
                    transactionList
                }
            }
            .background(Color.appBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(isHeaderCollapsed ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if isHeaderCollapsed && !isSelecting {
                    ToolbarItem(placement: .principal) {
                        compactStickyBar
                    }
                }
            }
            // Batch toolbar floats above bottom edge of scroll view
            .safeAreaInset(edge: .bottom) {
                if isSelecting { batchToolbar }
            }
        }
        // Batch category picker
        .sheet(isPresented: $showBatchCategoryPicker) {
            CategoryPickerSheet(isExpense: nil) { name, emoji in
                applyBatchCategory(name: name, emoji: emoji)
            }
        }
        // Batch delete confirmation
        .confirmationDialog("删除选中的记录？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { batchDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销")
        }
        .onChange(of: viewMonth) { _, _ in exitSelectMode(); clearFilters() }
        .onChange(of: viewYear)  { _, _ in exitSelectMode(); clearFilters() }
        .sheet(isPresented: $showFilterSheet) {
            BillFilterSheet(
                filterWeeks:         $filterWeeks,
                filterCategories:    $filterCategories,
                availableWeeks:      availableWeeks,
                availableCategories: availableCategories,
                weekRangeLabel:      weekRangeLabel
            )
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet(
                year: $viewYear,
                month: $viewMonth,
                availableMonths: availableYearMonths
            )
            .presentationDetents([.height(330)])
            .presentationDragIndicator(.visible)
        }
    }

    /// 所有有交易记录的年/月——给月份选择器用，避免用户选到全空的月份
    private var availableYearMonths: [YearMonth] {
        YearMonth.availableMonths(from: allTransactions)
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Row 1：标题 + 右上角操作（筛选 / 完成选择）
            HStack {
                Text("账单")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.appPrimary)
                    .tracking(-0.5)
                Spacer()
                if isSelecting {
                    Button("完成") { withAnimation { exitSelectMode() } }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.appAccent)
                } else if !monthTransactions.isEmpty {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isFiltering ? Color.appAccent : Color.appSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Row 2：月份切换——chevron 内联文字两侧；点中间月份文字弹出年月选择器
            HStack(spacing: 10) {
                monthChevron(systemName: "chevron.left", disabled: false) { changeMonth(-1) }
                Button {
                    showMonthPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text("\(String(viewYear))年\(viewMonth)月")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.appPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.appTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                monthChevron(systemName: "chevron.right", disabled: isCurrentMonth) { changeMonth(1) }
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var summaryCards: some View {
        VStack(spacing: 0) {
            // Inline 3 列数据——不再是 3 张卡片，列间用细分隔线
            HStack(spacing: 0) {
                summaryCell(label: "支出", amount: displayExpense, color: .appPrimary)
                summaryDivider
                summaryCell(label: "收入", amount: displayIncome, color: .appGreen)
                summaryDivider
                summaryCell(label: "结余", amount: displayIncome - displayExpense, color: balanceColor)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)

            // Active filter indicator
            if isFiltering {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11))
                        .foregroundStyle(.appAccent)
                    Text(activeFilterDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.appAccent)
                    Spacer()
                    Button("清除筛选") { clearFilters() }
                        .font(.system(size: 12))
                        .foregroundStyle(.appTertiary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFiltering)
        .padding(.bottom, 12)
    }

    /// 结余颜色：> 0 黑色（中性盈余）；< 0 橙色（柔性赤字警示）；= 0 灰
    private var balanceColor: Color {
        let balance = displayIncome - displayExpense
        if balance < 0 { return .appOrange }
        if balance > 0 { return .appPrimary }
        return .appSecondary
    }

    private func summaryCell(label: LocalizedStringKey, amount: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.appSecondary)
            Text("¥\(Int(amount).formatted())")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.appSeparator.opacity(0.6))
            .frame(width: 0.5, height: 28)
    }

    private var activeFilterDescription: String {
        let sep = String(localized: "、")
        let weekText = filterWeeks.isEmpty
            ? nil
            : String(localized: "周: ") + filterWeeks.sorted().map(weekRangeLabel).joined(separator: sep)
        let categoryText = filterCategories.isEmpty
            ? nil
            : String(localized: "分类: ") + filterCategories.sorted().map { $0.localizedCategoryName }.joined(separator: sep)

        return [weekText, categoryText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var transactionList: some View {
        if filteredMonthTransactions.isEmpty && isFiltering {
            // Empty state when filter yields no results
            VStack(spacing: 8) {
                Text("🔍").font(.system(size: 32)).opacity(0.4)
                Text("没有符合条件的记录")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appSecondary)
                Text("尝试更换筛选条件")
                    .font(.system(size: 13))
                    .foregroundStyle(.appTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else if groupedByDay.isEmpty {
            BillEmptyView()
        } else {
            ForEach(groupedByDay) { section in
                DayGroup(
                    date:             section.id,
                    transactions:     section.transactions,
                    isSelecting:      $isSelecting,
                    selectedIDs:      $selectedIDs,
                    onStartSelecting: { id in
                        withAnimation { isSelecting = true }
                        selectedIDs.insert(id)
                    }
                )
            }
        }
    }

    // MARK: - Batch toolbar

    private var batchToolbar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                // Select all / deselect all
                Button(allSelected ? "取消全选" : "全选") {
                    withAnimation { selectedIDs = allSelected ? [] : allMonthIDs }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.appAccent)
                .frame(maxWidth: .infinity)

                // Count
                Text("已选 \(selectedIDs.count) 项")
                    .font(.system(size: 13))
                    .foregroundStyle(.appSecondary)
                    .frame(maxWidth: .infinity)

                // Modify category
                Button {
                    showBatchCategoryPicker = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "tag")
                            .font(.system(size: 18))
                        Text("改分类")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(selectedIDs.isEmpty ? .appTertiary : .appAccent)
                }
                .disabled(selectedIDs.isEmpty)
                .frame(maxWidth: .infinity)

                // Delete
                Button {
                    showDeleteConfirm = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                        Text("删除")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(selectedIDs.isEmpty ? .appTertiary : .appRed)
                }
                .disabled(selectedIDs.isEmpty)
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Color.appCard)
        }
    }

    // MARK: - Batch operations

    private func batchDelete() {
        let toDelete = allTransactions.filter { selectedIDs.contains($0.id) }
        toDelete.forEach { context.delete($0) }
        try? context.save()
        exitSelectMode()
    }

    private func applyBatchCategory(name: String, emoji: String) {
        let toEdit = allTransactions.filter { selectedIDs.contains($0.id) }
        toEdit.forEach { $0.categoryName = name; $0.categoryEmoji = emoji }
        try? context.save()
        exitSelectMode()
    }

    private func exitSelectMode() {
        isSelecting = false
        selectedIDs = []
    }

    private func clearFilters() {
        filterWeeks = []
        filterCategories = []
    }

    // MARK: - Helpers

    private func changeMonth(_ delta: Int) {
        var mo = viewMonth + delta
        var yr = viewYear
        if mo < 1  { mo = 12; yr -= 1 }
        if mo > 12 { mo = 1;  yr += 1 }
        let now = Date()
        let nowY = Calendar.current.component(.year,  from: now)
        let nowM = Calendar.current.component(.month, from: now)
        if yr > nowY || (yr == nowY && mo > nowM) { return }
        viewYear = yr; viewMonth = mo
    }

    @ViewBuilder
    private func monthChevron(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(disabled ? .appTertiary.opacity(0.5) : .appSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// 滚动后塞进 nav bar 的紧凑头——保留月份切换 + 筛选入口
    private var compactStickyBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                compactChevron(systemName: "chevron.left", disabled: false) { changeMonth(-1) }
                Button {
                    showMonthPicker = true
                } label: {
                    HStack(spacing: 3) {
                        Text("\(String(viewYear))·\(viewMonth)月")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.appPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.appTertiary)
                    }
                }
                .buttonStyle(.plain)
                compactChevron(systemName: "chevron.right", disabled: isCurrentMonth) { changeMonth(1) }
            }
            Spacer(minLength: 4)
            if !monthTransactions.isEmpty {
                Button { showFilterSheet = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isFiltering ? Color.appAccent : Color.appSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func compactChevron(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? .appTertiary.opacity(0.5) : .appSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Day group

struct DayGroup: View {
    let date:  Date
    let transactions: [Transaction]

    // Optional — only BillView provides these
    var isSelecting: Binding<Bool>       = .constant(false)
    var selectedIDs: Binding<Set<UUID>>  = .constant([])
    var onStartSelecting: ((UUID) -> Void)? = nil

    private var dayTotal: Double {
        transactions.filter { !$0.isRefunded }.reduce(0) { $0 + $1.amount }
    }

    private var dayLabel: String {
        let cal = Calendar.current
        let today     = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let dateStr = f.string(from: date)
        if cal.isDate(date, inSameDayAs: today)     { return "\(String(localized: "今天")) · \(dateStr)" }
        if cal.isDate(date, inSameDayAs: yesterday) { return "\(String(localized: "昨天")) · \(dateStr)" }
        return dateStr
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(dayLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.appSecondary)
                Spacer()
                Text(dayTotal >= 0
                     ? "+¥\(String(format: "%.0f", dayTotal))"
                     : "-¥\(String(format: "%.0f", abs(dayTotal)))")
                    .font(.system(size: 13))
                    .foregroundStyle(.appSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 4)

            TransactionListCard(
                transactions:     transactions,
                isSelecting:      isSelecting.wrappedValue,
                selectedIDs:      selectedIDs,
                onStartSelecting: onStartSelecting
            )
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Empty state

struct BillEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("📒")
                .font(.system(size: 40))
                .opacity(0.3)
            Text("本月还没有记录")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.appSecondary)
            Text("记第一笔，开始积累属于你的账单")
                .font(.system(size: 13))
                .foregroundStyle(.appTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 24)
    }
}

// MARK: - Filter sheet

struct BillFilterSheet: View {
    @Binding var filterWeeks:         Set<Int>
    @Binding var filterCategories:    Set<String>
    let availableWeeks:               [Int]
    let availableCategories:          [(name: String, emoji: String)]
    let weekRangeLabel:               (Int) -> String

    // Draft state — only applied when user taps "应用"
    @State private var draftWeeks:      Set<Int>
    @State private var draftCategories: Set<String>

    @Environment(\.dismiss) private var dismiss

    init(filterWeeks: Binding<Set<Int>>, filterCategories: Binding<Set<String>>,
         availableWeeks: [Int], availableCategories: [(name: String, emoji: String)],
         weekRangeLabel: @escaping (Int) -> String) {
        _filterWeeks         = filterWeeks
        _filterCategories    = filterCategories
        self.availableWeeks      = availableWeeks
        self.availableCategories = availableCategories
        self.weekRangeLabel      = weekRangeLabel
        // Initialise draft from current active filters
        _draftWeeks      = State(initialValue: filterWeeks.wrappedValue)
        _draftCategories = State(initialValue: filterCategories.wrappedValue)
    }

    private var hasActiveDraft: Bool { !draftWeeks.isEmpty || !draftCategories.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // --- 按周（单选）---
                    if !availableWeeks.isEmpty {
                        filterSection(title: "按周", caption: "单选") {
                            chipGrid {
                                ForEach(availableWeeks, id: \.self) { week in
                                    weekChip(title: weekRangeLabel(week),
                                             active: draftWeeks.contains(week)) {
                                        selectWeek(week)
                                    }
                                }
                            }
                        }
                    }

                    // --- 按分类（可多选）---
                    if !availableCategories.isEmpty {
                        filterSection(title: "按分类", caption: "可多选") {
                            chipGrid {
                                ForEach(availableCategories, id: \.name) { cat in
                                    categoryChip(emoji: cat.emoji,
                                                 name: cat.name,
                                                 active: draftCategories.contains(cat.name)) {
                                        toggleCategory(cat.name)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.appBg)
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.appSecondary)
                }
                ToolbarItem(placement: .principal) {
                    if hasActiveDraft {
                        Button("清除全部") {
                            draftWeeks = []
                            draftCategories = []
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.appTertiary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        filterWeeks = draftWeeks
                        filterCategories = draftCategories
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.appAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections / chips

    @ViewBuilder
    private func filterSection<Content: View>(title: LocalizedStringKey, caption: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.appSecondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.appTertiary)
            }
            content()
        }
    }

    @ViewBuilder
    private func chipGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)],
                  alignment: .leading, spacing: 10) {
            content()
        }
    }

    /// 按周 chip — 单选语义，圆角矩形（visually 区别于按分类的胶囊）
    @ViewBuilder
    private func weekChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .white : Color.appSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(active ? Color.appAccent : Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: active)
    }

    /// 按分类 chip — 可多选语义，胶囊形 + 选中态紫色描边 + 浅紫底（更明显的"勾选"感）
    @ViewBuilder
    private func categoryChip(emoji: String, name: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji).font(.system(size: 16))
                Text(name.localizedCategoryName)
                    .font(.system(size: 14, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? .appAccent : .appPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(active ? Color.appAccentSoft.opacity(0.55) : Color.appCard)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(active ? Color.appAccent : Color.clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: active)
    }

    /// 周筛选——单选：点已选清空，点新的替换
    private func selectWeek(_ week: Int) {
        if draftWeeks.contains(week) {
            draftWeeks.removeAll()
        } else {
            draftWeeks = [week]
        }
    }

    private func toggleWeek(_ week: Int) {
        if draftWeeks.contains(week) {
            draftWeeks.remove(week)
        } else {
            draftWeeks.insert(week)
        }
    }

    private func toggleCategory(_ category: String) {
        if draftCategories.contains(category) {
            draftCategories.remove(category)
        } else {
            draftCategories.insert(category)
        }
    }
}

// MARK: - Month picker sheet

/// 年 + 月双滚轮选择器——参照 iOS Timer / DatePicker 的 wheel 样式。
/// 两个独立 wheel 平行排列，年范围动态取（数据最早年份 vs current-9）的较小者，
/// 始终至少展示 10 年；用户翻到未来时，"完成"自动 clamp 回当前月。
struct MonthPickerSheet: View {
    @Binding var year: Int
    @Binding var month: Int
    let availableMonths: [YearMonth]

    @Environment(\.dismiss) private var dismiss

    @State private var draftYear: Int
    @State private var draftMonth: Int

    init(year: Binding<Int>, month: Binding<Int>, availableMonths: [YearMonth]) {
        _year = year
        _month = month
        self.availableMonths = availableMonths
        _draftYear  = State(initialValue: year.wrappedValue)
        _draftMonth = State(initialValue: month.wrappedValue)
    }

    private var nowYM: YearMonth {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return YearMonth(year: c.year ?? 2024, month: c.month ?? 1)
    }

    /// 年份滚轮的取值——只展示有数据的年份；总是包含当前年（即使无数据，让用户能回来）。
    private var yearOptions: [Int] {
        var years = Set(availableMonths.map(\.year))
        years.insert(nowYM.year)
        return years.sorted(by: >)
    }

    /// 当前 draftYear 下的月份选项——只显示该年有数据的月份；
    /// 当前年额外保证包含当前月（即使本月无数据，让用户能回到"现在"），且过滤未来月。
    private var monthOptions: [Int] {
        let dataMonths = Set(
            availableMonths
                .filter { $0.year == draftYear }
                .map(\.month)
        )
        if draftYear == nowYM.year {
            var months = dataMonths
            months.insert(nowYM.month)
            return months.filter { $0 <= nowYM.month }.sorted()
        }
        return dataMonths.sorted()
    }

    private var hasFutureDraft: Bool {
        let now = nowYM
        return draftYear > now.year || (draftYear == now.year && draftMonth > now.month)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Picker("Year", selection: $draftYear) {
                        ForEach(yearOptions, id: \.self) { y in
                            Text(verbatim: "\(y) 年")
                                .font(.system(size: 20, weight: .regular))
                                .tag(y)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("Month", selection: $draftMonth) {
                        ForEach(monthOptions, id: \.self) { m in
                            Text("\(m) 月")
                                .font(.system(size: 20, weight: .regular))
                                .tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 200)
                .onChange(of: draftYear) { _, _ in
                    // 切换年后，若当前月不在该年的可选范围，clamp 到时间上最近的一个月（双向对称）。
                    guard !monthOptions.contains(draftMonth), !monthOptions.isEmpty else { return }
                    let target = draftMonth
                    draftMonth = monthOptions.min(by: { abs($0 - target) < abs($1 - target) }) ?? monthOptions[0]
                }

                // 跳到当前月份的快捷链接——iOS DatePicker 也有 "Today"
                Button {
                    let now = nowYM
                    withAnimation { draftYear = now.year; draftMonth = now.month }
                } label: {
                    Text("跳到本月")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.appAccent)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .opacity((draftYear == nowYM.year && draftMonth == nowYM.month) ? 0 : 1)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBg)
            .navigationTitle("选择月份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.appSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        // 选到未来 → clamp 回当前月
                        if hasFutureDraft {
                            let now = nowYM
                            year = now.year
                            month = now.month
                        } else {
                            year = draftYear
                            month = draftMonth
                        }
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.appAccent)
                }
            }
        }
        .presentationBackground(Color.appBg)
    }
}
