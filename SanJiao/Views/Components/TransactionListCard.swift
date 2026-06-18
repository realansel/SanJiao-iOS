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
    @State private var editAmountTx: Transaction?
    @State private var editAmountText: String = ""
    @State private var editDateTx: Transaction?
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
                    // 分隔线：跟 emoji 列宽对齐 (16 + 32 + 12 spacing = 60)，颜色更克制
                    Rectangle()
                        .fill(Color.appSeparator.opacity(0.6))
                        .frame(height: 0.5)
                        .padding(.leading, 60)
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
                    isRefunded: Binding(
                        get: { tx.isRefunded },
                        set: { newValue in
                            tx.isRefunded = newValue
                            try? context.save()
                        }
                    ),
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
                    onEditDate: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            editDateTx = tx
                        }
                    },
                    onDelete: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            deleteCandidateTx = tx
                        }
                    }
                )
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
                .presentationBackground(Color.appCard)

            case .categoryPicker(let tx):
                CategoryPickerSheet(isExpense: tx.isExpense) { name, emoji in
                    tx.categoryName  = name
                    tx.categoryEmoji = emoji
                    try? context.save()
                }
            }
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

        // MARK: Date edit sheet
        .sheet(item: $editDateTx) { tx in
            TransactionDateEditSheet(
                date: Binding(
                    get: { tx.date },
                    set: { newDate in
                        tx.date = newDate
                        try? context.save()
                    }
                ),
                onClose: { editDateTx = nil }
            )
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
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

    private func deleteTx(_ tx: Transaction) {
        context.delete(tx)
        try? context.save()
    }
}

// MARK: - Custom action sheet

/// 单条交易的 settings 风格编辑 sheet。
/// 每行左字段、右当前值 + chevron 进入编辑；退款是即时 toggle，名称是 header 主标题（点击原地编辑）。
struct TransactionActionSheet: View {
    let tx: Transaction
    @Binding var isRefunded: Bool   // 即时 toggle，父级写入 SwiftData
    let onEditAmount: () -> Void
    let onEditCategory: () -> Void
    let onEditDate: () -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var isEditingName = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    private var metaLine: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMdHHmm")
        return "\(tx.categoryName.localizedCategoryName) · \(f.string(from: tx.date))"
    }

    private var amountText: String {
        let abs = tx.absoluteAmount
        let prefix = tx.isExpense ? "-" : "+"
        return "\(prefix)¥\(String(format: "%.2f", abs))"
    }

    private var dateText: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMdHHmm")
        return f.string(from: tx.date)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header：emoji + 可点击名称（原地编辑） + meta（分类 · 日期时间）
            VStack(spacing: 10) {
                Text(tx.categoryEmoji)
                    .font(.system(size: 44))
                    .frame(height: 52)

                if isEditingName {
                    nameEditingField
                } else {
                    Button(action: startEditName) {
                        HStack(spacing: 4) {
                            Text(tx.displayName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.appPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.appTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text(metaLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.appSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider()

            // 编辑字段列表（settings 风格）
            fieldRow(label: "金额", value: amountText, action: onEditAmount)
            rowDivider()
            fieldRow(label: "分类", value: "\(tx.categoryEmoji) \(tx.categoryName.localizedCategoryName)", action: onEditCategory)
            rowDivider()
            fieldRow(label: "日期", value: dateText, action: onEditDate)

            if tx.isExpense {
                rowDivider()
                refundRow
            }

            // 红色分区隔离 destructive 操作
            Color.appBg
                .frame(height: 10)

            Divider()
            Button(action: onDelete) {
                HStack {
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                    Text("删除记录")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Color.appRed)
                .padding(.horizontal, 20)
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .background(Color.appCard)
    }

    // MARK: - Field row

    @ViewBuilder
    private func fieldRow(label: LocalizedStringKey, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(.appSecondary)
                    .frame(width: 56, alignment: .leading)
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.appPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.appTertiary)
            }
            .padding(.horizontal, 20)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 原地编辑名称的 TextField + 取消/保存小按钮
    private var nameEditingField: some View {
        HStack(spacing: 8) {
            TextField("名称", text: $nameDraft)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.appPrimary)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { saveName() }

            Button(action: cancelEditName) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.appTertiary)
            }
            .buttonStyle(.plain)

            Button(action: saveName) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.appAccent)
            }
            .buttonStyle(.plain)
            .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.appBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func startEditName() {
        nameDraft = tx.name
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditingName = true
        }
        // 等过渡动画半帧后再 focus，避免动画期间键盘抖动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            nameFocused = true
        }
    }

    private func saveName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            tx.name = trimmed
            try? context.save()
        }
        endEditing()
    }

    private func cancelEditName() {
        endEditing()
    }

    private func endEditing() {
        nameFocused = false
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditingName = false
        }
    }

    private var refundRow: some View {
        HStack(spacing: 12) {
            Text("退款")
                .font(.system(size: 15))
                .foregroundStyle(.appSecondary)
                .frame(width: 56, alignment: .leading)
            Text(isRefunded ? "已退款" : "无退款")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isRefunded ? .appOrange : .appPrimary)
            Spacer()
            Toggle("", isOn: $isRefunded)
                .labelsHidden()
                .tint(Color.appAccent)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
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

            // Category emoji icon — 裸 emoji，作为视觉锚点
            Text(tx.categoryEmoji)
                .font(.system(size: 22))
                .frame(width: 32, alignment: .center)

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
                Text(metaText)
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

    /// 没填备注（name 是分类名占位）时不再重复显示分类，避免「住房 / 住房 · 10:19」这种"看似 bug"的视觉。
    private var metaText: String {
        let time = metaTimeString(tx.date)
        if tx.name == tx.categoryName {
            return time
        }
        return "\(tx.categoryName.localizedCategoryName) · \(time)"
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

// MARK: - Date edit sheet

/// 单条交易的日期 + 时间编辑器——graphical date + wheel time，限制不能选未来。
struct TransactionDateEditSheet: View {
    @Binding var date: Date
    let onClose: () -> Void

    @State private var draftDate: Date

    init(date: Binding<Date>, onClose: @escaping () -> Void) {
        _date = date
        self.onClose = onClose
        _draftDate = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "",
                    selection: $draftDate,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .tint(Color.appAccent)
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBg)
            .navigationTitle("修改日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onClose() }
                        .foregroundStyle(.appSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        date = draftDate
                        onClose()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.appAccent)
                }
            }
        }
        .presentationBackground(Color.appBg)
    }
}

// MARK: - 空状态图标徽章（记录/账单/统计 共用，亮暗都通透有层次）
/// 极淡光晕 + 渐变柔色圆底 + 柔投影 + 品牌渐变填充的符号——比纯色平铺更有质感。
struct EmptyStateIcon: View {
    let systemName: String

    var body: some View {
        ZStack {
            // 外圈极淡光晕，增加纵深
            Circle()
                .fill(Color.appAccent.opacity(0.06))
                .frame(width: 100, height: 100)
            // 渐变柔色圆底 + 顶部玻璃高光描边 + 柔投影
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.appAccentSoft, Color.appAccentSoft.opacity(0.5)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 74, height: 74)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.65), Color.white.opacity(0.05)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.appAccent.opacity(0.18), radius: 12, y: 5)
            // 品牌渐变填充的符号
            Image(systemName: systemName)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(LinearGradient.accentGradient)
        }
    }
}
