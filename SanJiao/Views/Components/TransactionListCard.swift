import SwiftUI
import SwiftData

// MARK: - List card

struct TransactionListCard: View {
    let transactions: [Transaction]
    var showsDateInMeta: Bool = false

    var isSelecting: Bool = false
    var selectedIDs: Binding<Set<UUID>> = .constant([])
    var onStartSelecting: ((UUID) -> Void)? = nil

    @Environment(\.modelContext) private var context

    // Single sheet router — avoids stacking two .sheet modifiers
    private enum ActiveSheet: Identifiable {
        case actionMenu(Transaction)
        case categoryPicker(Transaction)
        var id: String {
            switch self {
            case .actionMenu(let tx):    "action-\(tx.id)"
            case .categoryPicker(let tx): "cat-\(tx.id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    // Alert state
    @State private var editNameTx: Transaction?
    @State private var editNameText: String = ""
    @State private var editAmountTx: Transaction?
    @State private var editAmountText: String = ""
    @State private var deleteCandidateTx: Transaction?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(transactions, id: \.id) { tx in
                TransactionRow(
                    tx: tx,
                    showsDateInMeta: showsDateInMeta,
                    isSelecting: isSelecting,
                    isSelected: selectedIDs.wrappedValue.contains(tx.id)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelecting {
                        toggleSelection(tx.id)
                    } else {
                        activeSheet = .actionMenu(tx)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.45) {
                    guard !isSelecting, onStartSelecting != nil else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onStartSelecting?(tx.id)
                }

                if tx.id != transactions.last?.id {
                    Divider().padding(.leading, 68)
                }
            }
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))

        // MARK: Sheet router
        .sheet(item: $activeSheet) { sheet in
            switch sheet {

            case .actionMenu(let tx):
                TransactionActionSheet(
                    tx: tx,
                    onEditName: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            editNameText = tx.name
                            editNameTx   = tx
                        }
                    },
                    onEditAmount: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            editAmountText = String(tx.absoluteAmount)
                            editAmountTx   = tx
                        }
                    },
                    onEditCategory: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            activeSheet = .categoryPicker(tx)
                        }
                    },
                    onToggleRefund: { toggleRefund(tx) },
                    onDelete: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            deleteCandidateTx = tx
                        }
                    }
                )
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)

            case .categoryPicker(let tx):
                CategoryPickerSheet(isExpense: tx.isExpense) { name, emoji in
                    tx.categoryName  = name
                    tx.categoryEmoji = emoji
                    try? context.save()
                }
            }
        }

        // MARK: Name edit alert
        .alert("修改名称", isPresented: Binding(
            get: { editNameTx != nil },
            set: { if !$0 { editNameTx = nil } }
        )) {
            TextField("名称", text: $editNameText)
            Button("保存") {
                if let tx = editNameTx,
                   !editNameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    tx.name = editNameText.trimmingCharacters(in: .whitespaces)
                    try? context.save()
                }
                editNameTx = nil
            }
            Button("取消", role: .cancel) { editNameTx = nil }
        } message: {
            if let tx = editNameTx { Text("当前：\(tx.name)") }
        }

        // MARK: Amount edit alert
        .alert("修改金额", isPresented: Binding(
            get: { editAmountTx != nil },
            set: { if !$0 { editAmountTx = nil } }
        )) {
            TextField("金额", text: $editAmountText)
                .keyboardType(.decimalPad)
            Button("保存") {
                if let tx = editAmountTx,
                   let value = Double(editAmountText), value > 0 {
                    tx.amount = tx.isExpense ? -value : value
                    try? context.save()
                }
                editAmountTx = nil
            }
            Button("取消", role: .cancel) { editAmountTx = nil }
        } message: {
            if let tx = editAmountTx {
                Text("当前：¥\(String(format: "%.2f", tx.absoluteAmount))")
            }
        }

        // MARK: Delete confirmation alert
        .alert("删除这条记录？", isPresented: Binding(
            get: { deleteCandidateTx != nil },
            set: { if !$0 { deleteCandidateTx = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let tx = deleteCandidateTx { deleteTx(tx) }
                deleteCandidateTx = nil
            }
            Button("取消", role: .cancel) { deleteCandidateTx = nil }
        } message: {
            if let tx = deleteCandidateTx {
                Text("「\(tx.name)」删除后无法恢复")
            }
        }
    }

    // MARK: - Helpers

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.wrappedValue.contains(id) {
            selectedIDs.wrappedValue.remove(id)
        } else {
            selectedIDs.wrappedValue.insert(id)
        }
    }

    private func toggleRefund(_ tx: Transaction) {
        tx.isRefunded.toggle()
        try? context.save()
        activeSheet = nil
    }

    private func deleteTx(_ tx: Transaction) {
        context.delete(tx)
        try? context.save()
    }
}

// MARK: - Custom action sheet

struct TransactionActionSheet: View {
    let tx: Transaction
    let onEditName: () -> Void
    let onEditAmount: () -> Void
    let onEditCategory: () -> Void
    let onToggleRefund: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            // Drag handle
            Capsule()
                .fill(Color.appSeparator)
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Transaction info header
            HStack(spacing: 14) {
                Text(tx.categoryEmoji)
                    .font(.system(size: 22))
                    .frame(width: 46, height: 46)
                    .background(Color.appBg)
                    .clipShape(RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 4) {
                    Text(tx.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                    Text("\(tx.categoryName.localizedCategoryName) · \(tx.displayAmount)")
                        .font(.system(size: 13))
                        .foregroundStyle(.appSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider()

            // Standard actions
            actionRow(icon: "pencil",          label: "修改名称", action: onEditName)
            rowDivider()
            actionRow(icon: "yensign.circle",  label: "修改金额", action: onEditAmount)
            rowDivider()
            actionRow(icon: "tag",             label: "修改分类", action: onEditCategory)
            if tx.isExpense {
                rowDivider()
                actionRow(
                    icon:  tx.isRefunded ? "arrow.uturn.backward.circle" : "arrow.counterclockwise.circle",
                    label: tx.isRefunded ? "取消退款标记" : "标记退款",
                    action: onToggleRefund
                )
            }

            // Destructive section separator
            Color.appBg
                .frame(height: 8)

            Divider()
            actionRow(icon: "trash", label: "删除记录", isDestructive: true, action: onDelete)

            Spacer(minLength: 0)
        }
        .background(Color.appCard)
    }

    // MARK: - Row builder

    @ViewBuilder
    private func actionRow(
        icon: String,
        label: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(isDestructive ? Color.appRed : Color.appAccent)
                    .frame(width: 28)
                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(isDestructive ? Color.appRed : Color.appPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rowDivider() -> some View {
        Divider().padding(.leading, 62)
    }
}

// MARK: - Row

struct TransactionRow: View {
    let tx: Transaction
    var showsDateInMeta: Bool = false
    var isSelecting: Bool = false
    var isSelected: Bool  = false

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox (visible only in multi-select mode)
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.appAccent : Color.appTertiary)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Category emoji icon
            Text(tx.categoryEmoji)
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(Color.appBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Name + meta
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tx.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tx.isRefunded ? .appTertiary : .appPrimary)
                        .lineLimit(1)
                    if tx.isRefunded {
                        Text("已退款")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.appOrange)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text("\(tx.categoryName.localizedCategoryName) · \(metaTimeString(tx.date))")
                    .font(.system(size: 12))
                    .foregroundStyle(.appSecondary)
            }

            Spacer()

            // Amount
            Text(tx.displayAmount)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(amountColor)
                .strikethrough(tx.isRefunded)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            isSelected
                ? Color.appAccent.opacity(0.08)
                : Color.clear
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelecting)
        .animation(.spring(response: 0.2,  dampingFraction: 0.9), value: isSelected)
    }

    private var amountColor: Color {
        if tx.isRefunded { return .appTertiary }
        return tx.isIncome ? .appGreen : .appPrimary
    }

    private func metaTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        if showsDateInMeta {
            f.setLocalizedDateFormatFromTemplate("MMMdHHmm")
        } else {
            f.dateFormat = "HH:mm"
        }
        return f.string(from: date)
    }
}
