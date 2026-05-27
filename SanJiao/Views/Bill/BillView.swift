import SwiftUI
import SwiftData

private struct DaySection: Identifiable {
    var id: Date
    var transactions: [Transaction]
}

// 通过 KVO 监听父级 UIScrollView 的 contentOffset，SwiftUI PreferenceKey 在非 Lazy 滚动时不可靠
private struct ScrollOffsetDetector: UIViewRepresentable {
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
    @State private var billScrollOffset: CGFloat     = 0     // UIScrollView contentOffset.y，向下滚动时增大
    @State private var footerVisible                 = false

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

    // All IDs visible after filtering (for "全选")
    private var allMonthIDs: Set<UUID> { Set(filteredMonthTransactions.map(\.id)) }
    private var allSelected: Bool { !allMonthIDs.isEmpty && allMonthIDs.isSubset(of: selectedIDs) }

    // MARK: Body

    var body: some View {
        NavigationStack {
            GeometryReader { rootGeo in
                ScrollViewReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                // KVO 探针：零高度，放在内容最顶部，用于监听 UIScrollView 滚动
                                ScrollOffsetDetector(offset: $billScrollOffset)
                                    .frame(height: 0)
                                    .id("bill-top")

                                header
                                summaryCards
                                transactionList
                                footerNote
                            }
                        }

                        if showScrollToTopButton {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo("bill-top", anchor: .top)
                                }
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 44, height: 44)
                                    .background(Color.appAccent.opacity(0.55))
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, isSelecting ? 84 : rootGeo.safeAreaInsets.bottom + 28)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: showScrollToTopButton)
                }
            }
            .background(Color.appBg)
            .navigationBarHidden(true)
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
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                }
            }

            HStack(spacing: 12) {
                navButton(icon: "‹") { changeMonth(-1) }
                Text("\(String(viewYear))年\(viewMonth)月")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                navButton(icon: "›", disabled: isCurrentMonth) { changeMonth(1) }
                Spacer()
                // Filter button — only visible outside select mode and when there's data
                if !isSelecting && !monthTransactions.isEmpty {
                    Button { showFilterSheet = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal.decrease.circle\(isFiltering ? ".fill" : "")")
                                .font(.system(size: 22))
                                .foregroundStyle(isFiltering ? Color.appAccent : Color.appSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var summaryCards: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SumCard(label: "支出", amount: displayExpense, color: .appPrimary)
                SumCard(label: "收入", amount: displayIncome,  color: .appGreen)
                SumCard(label: "结余", amount: displayIncome - displayExpense, color: .appAccent)
            }
            .padding(.horizontal, 16)

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
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFiltering)
        .padding(.bottom, 8)
    }

    // contentOffset.y > 80 表示已向下滚动超过 80pt，顶部内容滚出了可视区
    private var showScrollToTopButton: Bool {
        billScrollOffset > 80
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

    private var footerNote: some View {
        Text("数据仅存储在本设备  ·  私密安全")
            .font(.system(size: 10))
            .foregroundStyle(.appTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .onAppear { footerVisible = true }
            .onDisappear { footerVisible = false }
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
    private func navButton(icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(icon)
                .font(.system(size: 14))
                .foregroundStyle(disabled ? .appTertiary : .appSecondary)
                .frame(width: 30, height: 30)
                .background(Color.appSeparator)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Summary card

struct SumCard: View {
    let label: LocalizedStringKey
    let amount: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.appSecondary)
            Text("¥\(Int(amount).formatted())")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
                .tracking(-0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // --- 按周 ---
                    if !availableWeeks.isEmpty {
                        filterSection(title: "按周") {
                            chipGrid {
                                ForEach(availableWeeks, id: \.self) { week in
                                    chip(title: weekRangeLabel(week),
                                         active: draftWeeks.contains(week)) {
                                        toggleWeek(week)
                                    }
                                }
                            }
                        }
                    }

                    // --- 按分类 ---
                    if !availableCategories.isEmpty {
                        filterSection(title: "按分类") {
                            chipGrid {
                                ForEach(availableCategories, id: \.name) { cat in
                                    chip(title: "\(cat.emoji) \(cat.name.localizedCategoryName)",
                                         active: draftCategories.contains(cat.name)) {
                                        toggleCategory(cat.name)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.appBg)
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") {
                        filterWeeks = []
                        filterCategories = []
                        dismiss()
                    }
                    .foregroundStyle(.appTertiary)
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

    // MARK: - Helpers

    @ViewBuilder
    private func filterSection<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.appSecondary)
                .textCase(.uppercase)
                .tracking(0.4)
            content()
        }
    }

    @ViewBuilder
    private func chipGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        // Wrap chips in a flowing layout via LazyVGrid
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)],
                  alignment: .leading, spacing: 10) {
            content()
        }
    }

    @ViewBuilder
    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .white : Color.appSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(active ? Color.appAccent : Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: active)
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
