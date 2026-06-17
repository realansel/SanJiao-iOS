import SwiftUI
import SwiftData

/// A sheet that lets the user pick a category.
/// - `isExpense: true`  → shows only expense categories
/// - `isExpense: false` → shows only income categories
/// - `isExpense: nil`   → shows both (for batch editing mixed transactions)
struct CategoryPickerSheet: View {
    let isExpense: Bool?
    let onPick: (String, String) -> Void   // (categoryName, categoryEmoji)
    var onManage: (() -> Void)? = nil

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Environment(\.dismiss) private var dismiss
    @State private var measuredHeight: CGFloat = 0

    private var expenseCategories: [Category] { categories.filter { $0.isExpense } }
    private var incomeCategories:  [Category] { categories.filter { !$0.isExpense } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isExpense == nil || isExpense == true {
                        sectionGrid(
                            title: isExpense == nil ? "支出分类" : nil,
                            cats: expenseCategories
                        )
                    }
                    if isExpense == nil || isExpense == false {
                        sectionGrid(
                            title: isExpense == nil ? "收入分类" : nil,
                            cats: incomeCategories
                        )
                    }
                }
                .padding(20)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: PickerContentHeightKey.self, value: geo.size.height)
                    }
                )
            }
            .background(Color.appBg)
            .onPreferenceChange(PickerContentHeightKey.self) { measuredHeight = $0 }
            // 自测内容高度 + 顶部导航栏与底部安全区的固定开销，让 sheet 刚好容纳所有分类、
            // 不截断最后一行。调用点若自带 .presentationDetents（外层），会自然覆盖此默认值。
            .presentationDetents(measuredHeight > 0 ? [.height(measuredHeight + 90)] : [.large])
            .navigationTitle("选择分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.appAccent)
                }
                if onManage != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("管理") {
                            dismiss()
                            DispatchQueue.main.async {
                                onManage?()
                            }
                        }
                        .foregroundStyle(.appAccent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionGrid(title: String?, cats: [Category]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.appSecondary)
                    .padding(.leading, 4)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: 12)],
                spacing: 14
            ) {
                ForEach(cats) { cat in
                    Button {
                        onPick(cat.name, cat.emoji)
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            Text(cat.emoji)
                                .font(.system(size: 38))
                                .frame(width: 56, height: 56)
                            Text(cat.name.localizedCategoryName)
                                .font(.system(size: 12))
                                .foregroundStyle(.appPrimary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 量取分类网格内容的自然高度，用于自适应 sheet detent。
private struct PickerContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
