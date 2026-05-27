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
            }
            .background(Color.appBg)
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
                                .font(.system(size: 26))
                                .frame(width: 56, height: 56)
                                .background(Color.appCard)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            Text(cat.name.localizedCategoryName)
                                .font(.system(size: 12))
                                .foregroundStyle(.appPrimary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
