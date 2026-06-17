import SwiftUI
import SwiftData

struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var transactions: [Transaction]

    @State private var selectedType: RecordType
    @State private var editingCategory: Category?
    @State private var isAddingCategory = false
    @State private var editMode: EditMode = .inactive
    @State private var deleteCandidate: Category?

    init(initialType: RecordType = .expense) {
        _selectedType = State(initialValue: initialType)
    }

    private var currentCategories: [Category] {
        categories
            .filter { $0.type == selectedTypeString }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectedTypeString: String {
        selectedType == .expense ? "expense" : "income"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                List {
                    Section {
                        ForEach(currentCategories) { category in
                            Button {
                                editingCategory = category
                            } label: {
                                categoryRow(category)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if category.isCustom && editMode != .active {
                                    Button(role: .destructive) {
                                        deleteCandidate = category
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .onMove(perform: moveCategory)
                    } header: {
                        Text("长按右侧排序柄拖动顺序")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.appTertiary)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.appBg)
                .environment(\.editMode, $editMode)

                Button {
                    isAddingCategory = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("新增\(selectedType == .expense ? "支出" : "收入")类别")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                }
                .buttonStyle(.plain)
            }
            .background(Color.appBg)
            .navigationTitle("类别管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(.appAccent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editMode == .active ? "完成排序" : "排序") {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .foregroundStyle(.appAccent)
                }
            }
            .sheet(item: $editingCategory) { category in
                CategoryEditorSheet(
                    category: category,
                    onSave: { name, emoji in
                        update(category, name: name, emoji: emoji)
                    },
                    onDelete: category.isCustom ? {
                        delete(category)
                    } : nil
                )
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isAddingCategory) {
                CategoryEditorSheet(type: selectedType) { name, emoji in
                    addCategory(name: name, emoji: emoji)
                }
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
            .alert("删除这个自定义类别？", isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            )) {
                Button("删除", role: .destructive) {
                    if let category = deleteCandidate {
                        delete(category)
                    }
                    deleteCandidate = nil
                }
                Button("取消", role: .cancel) {
                    deleteCandidate = nil
                }
            } message: {
                if let category = deleteCandidate {
                    Text("「\(category.name.localizedCategoryName)」对应的历史账单会自动归到“其他”。")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                typeSegment("支出", type: .expense)
                typeSegment("收入", type: .income)
            }
            .padding(3)
            .background(Color.appSeparator)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Text("调整后会影响记账时的类别展示顺序。修改名称或 emoji 时，已有同类账单也会同步更新。")
                .font(.system(size: 13))
                .foregroundStyle(.appSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func typeSegment(_ title: String, type: RecordType) -> some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                selectedType = type
                editMode = .inactive
            }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedType == type ? .appPrimary : .appSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selectedType == type ? Color.appCard : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private func categoryRow(_ category: Category) -> some View {
        HStack(spacing: 14) {
            Text(category.emoji)
                .font(.system(size: 26))
                .frame(width: 36, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name.localizedCategoryName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.appPrimary)
                Text(category.isCustom ? "自定义类别" : "默认类别")
                    .font(.system(size: 12))
                    .foregroundStyle(.appTertiary)
            }

            Spacer()

            if editMode != .active {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.appTertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func addCategory(name: String, emoji: String) {
        let nextOrder = (currentCategories.map(\.sortOrder).max() ?? -1) + 1
        context.insert(Category(
            name: name,
            emoji: emoji,
            type: selectedTypeString,
            sortOrder: nextOrder,
            isCustom: true
        ))
        try? context.save()
    }

    private func update(_ category: Category, name: String, emoji: String) {
        let oldName = category.name
        let oldEmoji = category.emoji
        let isExpense = category.isExpense

        category.name = name
        category.emoji = emoji
        category.isCustom = true

        for tx in transactions where tx.isExpense == isExpense
            && tx.categoryName == oldName
            && tx.categoryEmoji == oldEmoji {
            tx.categoryName = name
            tx.categoryEmoji = emoji
        }

        try? context.save()
    }

    private func moveCategory(from source: IndexSet, to destination: Int) {
        var reordered = currentCategories
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, category) in reordered.enumerated() {
            category.sortOrder = index
        }
        try? context.save()
    }

    private func delete(_ category: Category) {
        guard category.isCustom else { return }

        let fallbackName = "其他"
        let fallbackEmoji = category.isExpense ? "💡" : "⭐"

        for tx in transactions where tx.isExpense == category.isExpense
            && tx.categoryName == category.name
            && tx.categoryEmoji == category.emoji {
            tx.categoryName = fallbackName
            tx.categoryEmoji = fallbackEmoji
        }

        context.delete(category)

        let remaining = currentCategories
            .filter { $0.id != category.id }
            .sorted { $0.sortOrder < $1.sortOrder }

        for (index, item) in remaining.enumerated() {
            item.sortOrder = index
        }

        try? context.save()
    }
}

private struct CategoryEditorSheet: View {
    let title: String
    let initialName: String
    let initialEmoji: String
    let onSave: (String, String) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var showDeleteAlert = false

    init(category: Category, onSave: @escaping (String, String) -> Void, onDelete: (() -> Void)? = nil) {
        self.title = "编辑类别"
        self.initialName = category.name
        self.initialEmoji = category.emoji
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: category.name)
        _emoji = State(initialValue: category.emoji)
    }

    init(type: RecordType, onSave: @escaping (String, String) -> Void) {
        self.title = "新增\(type == .expense ? "支出" : "收入")类别"
        self.initialName = ""
        self.initialEmoji = "💡"
        self.onSave = onSave
        self.onDelete = nil
        _name = State(initialValue: "")
        _emoji = State(initialValue: "💡")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    TextField("Emoji", text: $emoji)
                        .font(.system(size: 34))
                        .multilineTextAlignment(.center)
                        .frame(width: 78, height: 68)
                        .background(Color.appBg)
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                    TextField("类别名称", text: $name)
                        .font(.system(size: 17, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(Color.appBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 12)

                Text("名称建议保持简短，emoji 会作为记账入口和账单列表里的类别图标。")
                    .font(.system(size: 13))
                    .foregroundStyle(.appSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button {
                    onSave(
                        name.trimmingCharacters(in: .whitespacesAndNewlines),
                        emoji.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    dismiss()
                } label: {
                    Text("保存")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(canSave ? Color.appAccent : Color.appTertiary.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .background(Color.appCard)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.appTertiary)
                }
                if onDelete != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("删除") {
                            showDeleteAlert = true
                        }
                        .foregroundStyle(.appRed)
                    }
                }
            }
            .alert("删除这个自定义类别？", isPresented: $showDeleteAlert) {
                Button("删除", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("对应的历史账单会自动归到“其他”。")
            }
        }
    }
}
