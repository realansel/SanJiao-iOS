import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Document Picker Wrapper

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            .commaSeparatedText,
            UTType(filenameExtension: "xlsx") ?? .spreadsheet,
            .spreadsheet
        ]
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - Import Result

private struct ImportResult {
    let saved: Int
    let skipped: Int
    let source: String   // "微信" or "支付宝"
}

private struct ImportPreview {
    let source: String
    let newItems: [ImportedTransaction]
    let skipped: Int
}

enum BillManagementMode {
    case `import`
    case export
}

private struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            self.text = text
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: .utf8) ?? Data())
    }
}

// MARK: - Main View

struct BillImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(UnlockManager.self) private var unlockManager
    @Environment(AppState.self) private var appState
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var merchantRules: [MerchantCategoryRule]

    @State private var mode: BillManagementMode?
    @State private var showPicker      = false
    @State private var isLoading       = false
    @State private var result: ImportResult?
    @State private var errorMessage: String?
    @State private var importPreview: ImportPreview?
    @State private var showExporter = false
    @State private var exportDocument = CSVDocument(text: "")
    @State private var exportMessage: String?
    @State private var showClearDataSheet       = false   // 清空数据 step1：警告 sheet
    @State private var showClearDataFinalAlert  = false   // 清空数据 step2：最终确认 alert
    @State private var clearDataMessage: String?

    // 导入页教程相关
    @State private var importGuideSource: ImportGuideSource = .wechat
    @State private var showImportGuideSteps: Bool = false

    /// 上次成功导出 CSV 的时间戳（用于"清空数据"前判断备份新鲜度）
    @AppStorage(AppStorageKeys.lastCSVExportTimestamp) private var lastExportTimestamp: Double = 0

    init(startMode: BillManagementMode? = nil) {
        _mode = State(initialValue: startMode)
    }

    var body: some View {
        ScrollView {
            managementHome
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .background(Color.appBg)
        .navigationTitle("账单管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 试用已结束时，外部入口（如 onboarding）传入的 .import 也要拦下，回到管理首页并弹出 paywall
            if mode == .import, !unlockManager.canRecord {
                mode = nil
                appState.showPaywall = true
            }
        }
        .navigationDestination(item: $mode) { m in
            switch m {
            case .import: importFlow
            case .export: exportFlow
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { url in
                handleFile(url)
            }
        }
        .sheet(item: $importPreview) { preview in
            ImportPreviewSheet(
                preview: preview,
                isSaving: isLoading,
                onConfirm: { items, changedIndices in
                    confirmImport(preview, items: items, changedIndices: changedIndices)
                }
            )
        }
        .sheet(isPresented: $showClearDataSheet) {
            ClearDataWarningSheet(
                lastExportDate: lastExportDate,
                onBackup: {
                    showClearDataSheet = false
                    // 等 sheet dismiss 动画完成再 push，避免冲突
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        mode = .export
                    }
                },
                onContinue: {
                    showClearDataSheet = false
                    // 给 sheet 一点时间 dismiss，再弹最终确认 alert
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showClearDataFinalAlert = true
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                exportMessage = String(localized: "账单已导出，可在文件 App 中查看或分享。")
                // 记录最新备份时间戳
                lastExportTimestamp = Date().timeIntervalSince1970
            case .failure(let error):
                exportMessage = error.localizedDescription
            }
        }
        .alert("确认清空所有数据？", isPresented: $showClearDataFinalAlert) {
            Button("确认清空", role: .destructive) {
                clearAllLocalData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销，请确认你已经导出过备份。")
        }
        .alert("已清空", isPresented: Binding(
            get: { clearDataMessage != nil },
            set: { if !$0 { clearDataMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(clearDataMessage ?? "")
        }
    }

    private var lastExportDate: Date? {
        lastExportTimestamp > 0 ? Date(timeIntervalSince1970: lastExportTimestamp) : nil
    }

    // MARK: - Push 子流程（NavigationStack push，系统 back 接管）

    private var importFlow: some View {
        ScrollView {
            importContent
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .background(Color.appBg)
        .navigationTitle("账单导入")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var exportFlow: some View {
        ScrollView {
            exportContent
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .background(Color.appBg)
        .navigationTitle("账单导出")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Mode Views

    private var managementHome: some View {
        VStack(spacing: 14) {
            modeCard(
                icon: "📥",
                title: String(localized: "导入账单"),
                subtitle: unlockManager.canRecord
                    ? String(localized: "支持悦笺、微信支付、支付宝导出文件")
                    : String(localized: "试用已结束，解锁后即可继续导入"),
                tint: .appAccent
            ) {
                guard unlockManager.canRecord else {
                    appState.showPaywall = true
                    return
                }
                mode = .import
            }

            modeCard(
                icon: "📤",
                title: String(localized: "导出账单"),
                subtitle: transactions.isEmpty
                    ? String(localized: "暂无可导出的本地账单")
                    : String(localized: "导出 \(transactions.count) 笔本地账单为 CSV"),
                tint: .appWarning
            ) {
                mode = .export
            }

            // 清空数据：作为辅助操作放在底部，弱化视觉权重（链接样式）
            Button {
                showClearDataSheet = true
            } label: {
                Text("清空所有本地数据")
                    .font(.system(size: 13))
                    .foregroundStyle(.appRed.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
    }

    private var importContent: some View {
        VStack(spacing: 20) {
            Button(action: { showPicker = true }) {
                Group {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("解析中…").font(.system(size: 17, weight: .semibold))
                        }
                    } else {
                        Text(result == nil ? String(localized: "选择账单文件") : String(localized: "继续导入"))
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isLoading ? Color.appAccent.opacity(0.6) : Color.appAccent)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            Text("数据仅在本设备处理")
                .font(.system(size: 12))
                .foregroundStyle(.appTertiary)

            if let result {
                resultCard(result)
            }

            importGuideCard

            tipsCard(
                icon: "💡",
                title: String(localized: "导入提示"),
                tips: [
                    String(localized: "同一份账单重复导入会自动去重"),
                    String(localized: "退款、理财、充值等记录可能会被自动跳过")
                ]
            )

            Color.clear.frame(height: 12)
        }
        .alert("无法导入", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好的", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var exportContent: some View {
        VStack(spacing: 20) {
            Button(action: prepareExport) {
                Text(transactions.isEmpty
                     ? String(localized: "暂无账单可导出")
                     : String(localized: "导出 \(transactions.count) 笔账单为 CSV"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(transactions.isEmpty ? Color.appTertiary.opacity(0.5) : Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(transactions.isEmpty)

            tipsCard(
                icon: "📄",
                title: String(localized: "导出内容"),
                tips: [
                    String(localized: "包含时间、名称、金额、收支类型、分类、备注"),
                    String(localized: "金额保留正负号：支出为负数，收入为正数"),
                    String(localized: "UTF-8 编码，可用 Numbers、Excel 打开")
                ]
            )

            if let exportMessage {
                resultMessageCard(exportMessage)
            }
        }
    }

    // MARK: - Handle File

    private func handleFile(_ url: URL) {
        isLoading = true
        result = nil
        errorMessage = nil
        importPreview = nil

        DispatchQueue.global(qos: .userInitiated).async {
            // 先检测来源（内容嗅探），再解析
            let src = BillImportManager.detectSource(url: url)

            do {
                let items = try BillImportManager.parse(url: url)

                DispatchQueue.main.async {
                    // 轻账自身导出的文件分类已精确，无需商户规则重映射
                    let categorizedItems: [ImportedTransaction]
                    if src == "轻账" {
                        categorizedItems = items
                    } else {
                        categorizedItems = BillImportManager.applyMerchantRules(
                            to: items, source: src, context: modelContext)
                    }
                    let summary = BillImportManager.summarizeImport(categorizedItems, context: modelContext)
                    importPreview = ImportPreview(source: src, newItems: summary.newItems, skipped: summary.skipped)
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = (error as? BillImportError)?.errorDescription ?? error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func confirmImport(_ preview: ImportPreview, items: [ImportedTransaction], changedIndices: Set<Int>) {
        isLoading = true
        errorMessage = nil

        DispatchQueue.main.async {
            let validChangedIndices = changedIndices.filter {
                preview.newItems.indices.contains($0) && items.indices.contains($0)
            }
            let groupedChangedIndices = Dictionary(grouping: validChangedIndices) { index in
                let item = preview.newItems[index]
                let type = item.isExpense ? "expense" : "income"
                let ruleName = BillImportManager.merchantRuleName(for: item, source: preview.source)
                return "\(preview.source)|\(type)|\(MerchantCategoryRule.makeKey(ruleName))"
            }

            for indices in groupedChangedIndices.values {
                let categoryKeys = Set(indices.map { "\(items[$0].categoryName)|\(items[$0].categoryEmoji)" })
                guard categoryKeys.count == 1, let index = indices.first else { continue }
                BillImportManager.upsertMerchantRule(
                    for: preview.newItems[index],
                    source: preview.source,
                    categoryName: items[index].categoryName,
                    categoryEmoji: items[index].categoryEmoji,
                    context: modelContext
                )
            }
            let (saved, skipped) = BillImportManager.save(items, context: modelContext)
            if saved > 0,
               UserDefaults.standard.object(forKey: AppStorageKeys.billManagementStartDate) == nil {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppStorageKeys.billManagementStartDate)
            }
            result = ImportResult(saved: saved, skipped: skipped + preview.skipped, source: preview.source)
            importPreview = nil
            isLoading = false
        }
    }

    // MARK: - Export

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return String(localized: "悦笺账单-\(formatter.string(from: Date()))")
    }

    private func prepareExport() {
        exportDocument = CSVDocument(text: makeCSV(from: transactions))
        exportMessage = nil
        showExporter = true
    }

    private func clearAllLocalData() {
        transactions.forEach { modelContext.delete($0) }
        merchantRules.forEach { modelContext.delete($0) }

        let defaultExpenseOrder = Dictionary(uniqueKeysWithValues:
            Category.defaultExpenseCategories.enumerated().map { index, item in
                ("expense|\(item.0)", (index, item.1))
            }
        )
        let defaultIncomeOrder = Dictionary(uniqueKeysWithValues:
            Category.defaultIncomeCategories.enumerated().map { index, item in
                ("income|\(item.0)", (index, item.1))
            }
        )

        for category in categories {
            if category.isCustom {
                modelContext.delete(category)
                continue
            }

            let key = "\(category.type)|\(category.name)"
            if let (sortOrder, emoji) = defaultExpenseOrder[key] ?? defaultIncomeOrder[key] {
                category.sortOrder = sortOrder
                category.emoji = emoji
            }
        }

        try? modelContext.save()
        Category.seedDefaultCategories(context: modelContext)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.billManagementStartDate)
        result = nil
        exportMessage = nil
        errorMessage = nil
        clearDataMessage = String(localized: "本地账单数据已清空，默认类别已保留。")
    }

    private func makeCSV(from transactions: [Transaction]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let h = CSVLocalization.current
        let t = CSVLocalization.currentType
        let r = CSVLocalization.currentRefund

        let header = h.array
        let rows = transactions
            .sorted { $0.date > $1.date }
            .map { tx in
                [
                    formatter.string(from: tx.date),
                    tx.name,
                    String(format: "%.2f", tx.amount),
                    tx.isExpense ? t.expense : t.income,
                    CSVLocalization.localizedCategoryName(tx.categoryName),
                    tx.categoryEmoji,
                    tx.note,
                    tx.isRefunded ? r.yes : r.no,
                    formatter.string(from: tx.createdAt)
                ]
            }

        return "\u{FEFF}" + ([header] + rows)
            .map { $0.map(csvEscape).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func modeCard(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(icon)
                    .font(.system(size: 24))
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.appSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.appTertiary)
            }
            .padding(16)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 导入教程：合并 3 张为 1 张带 segmented control 的可折叠卡

    private var importGuideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 头部：标题 + 展开/收起
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    showImportGuideSteps.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text("📖").font(.system(size: 16))
                    Text("如何获取账单文件")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                    Spacer()
                    Image(systemName: showImportGuideSteps ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.appTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showImportGuideSteps {
                // 来源切换
                Picker("来源", selection: $importGuideSource) {
                    ForEach(ImportGuideSource.allCases) { src in
                        Text(src.label).tag(src)
                    }
                }
                .pickerStyle(.segmented)

                // 步骤列表
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(importGuideSource.steps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.appAccent)
                                .frame(width: 16, height: 16)
                                .background(Color.appAccentSoft)
                                .clipShape(Circle())
                            Text(step)
                                .font(.system(size: 12))
                                .foregroundStyle(.appSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appSeparator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - tipsCard（轻量版：透明底 + 细描边 + 小字号）

    @ViewBuilder
    private func tipsCard(icon: String, title: String, tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(icon).font(.system(size: 14))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.appSecondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.appTertiary)
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        Text(tip)
                            .font(.system(size: 12))
                            .foregroundStyle(.appSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appSeparator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func resultCard(_ r: ImportResult) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.appGreen)
                Text("\(r.source)账单导入完成")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                Spacer()
            }

            HStack(spacing: 12) {
                resultStat(value: "\(r.saved)", label: String(localized: "成功导入"), color: .appGreen)
                resultStat(value: "\(r.skipped)", label: String(localized: "已存在跳过"), color: .appTertiary)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appGreen.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func resultStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.appSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.appBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.appRed)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.appPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func resultMessageCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.appGreen)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.appPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension ImportPreview: Identifiable {
    var id: String { "\(source)-\(newItems.count)-\(skipped)" }
}

private struct ImportPreviewSheet: View {
    let preview: ImportPreview
    let isSaving: Bool
    let onConfirm: ([ImportedTransaction], Set<Int>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showAllItems = false
    @State private var editableItems: [ImportedTransaction]
    @State private var categoryEditingTarget: CategoryEditingTarget?
    @State private var showCategoryManager = false
    @State private var categoryManagerType: RecordType = .expense
    @State private var changedIndices = Set<Int>()
    @State private var expandedGroupKeys = Set<String>()
    @State private var showUncategorizedOnly = false
    @State private var uncategorizedFocusIndices = Set<Int>()

    init(
        preview: ImportPreview,
        isSaving: Bool,
        onConfirm: @escaping ([ImportedTransaction], Set<Int>) -> Void
    ) {
        self.preview = preview
        self.isSaving = isSaving
        self.onConfirm = onConfirm
        _editableItems = State(initialValue: preview.newItems)
    }

    private var previewGroups: [ImportPreviewGroup] {
        let sourceItems: [(Int, ImportedTransaction)] = showUncategorizedOnly
            ? editableItems.enumerated().compactMap { index, item in
                uncategorizedFocusIndices.contains(index) ? (index, item) : nil
            }
            : editableItems.enumerated().map { ($0.offset, $0.element) }

        var orderedKeys: [String] = []
        var buckets: [String: [Int]] = [:]

        for (index, item) in sourceItems {
            let key = groupKey(for: item)
            if buckets[key] == nil {
                orderedKeys.append(key)
            }
            buckets[key, default: []].append(index)
        }

        return orderedKeys.compactMap { key in
            guard let indices = buckets[key], let firstIndex = indices.first else { return nil }
            let first = editableItems[firstIndex]
            return ImportPreviewGroup(
                key: key,
                name: groupDisplayName(for: first),
                isExpense: first.isExpense,
                indices: indices
            )
        }
    }

    private var visibleGroups: [ImportPreviewGroup] {
        showAllItems ? previewGroups : Array(previewGroups.prefix(12))
    }

    private var uncategorizedCount: Int {
        editableItems.filter { $0.categoryName == "其他" }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCard
                    previewListCard
                }
                .padding(20)
            }
            .background(Color.appBg)
            .navigationTitle("导入确认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.appTertiary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? String(localized: "导入中…") : String(localized: "确认导入")) {
                        onConfirm(editableItems, changedIndices)
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.appAccent)
                    .disabled(isSaving)
                }
            }
        }
        .sheet(item: $categoryEditingTarget) { target in
            let indices = indices(for: target)
            if let firstIndex = indices.first, editableItems.indices.contains(firstIndex) {
                CategoryPickerSheet(
                    isExpense: editableItems[firstIndex].isExpense,
                    onPick: { name, emoji in
                        updateCategory(at: indices, name: name, emoji: emoji)
                        categoryEditingTarget = nil
                    },
                    onManage: {
                        categoryManagerType = editableItems[firstIndex].isExpense ? .expense : .income
                        categoryEditingTarget = nil
                        showCategoryManager = true
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagementView(initialType: categoryManagerType)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(preview.source)账单已解析完成")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.appPrimary)

            HStack(spacing: 12) {
                previewStat(value: "\(editableItems.count)", label: String(localized: "预计导入"), color: .appGreen)
                previewStat(value: "\(preview.skipped)", label: String(localized: "预计跳过"), color: .appTertiary)
            }

            Text(editableItems.isEmpty
                 ? String(localized: "这些记录已存在于悦笺中，确认后不会重复添加。")
                 : String(localized: "点任意一笔可修改分类；修改后会记住该商户，下次自动识别。"))
                .font(.system(size: 13))
                .foregroundStyle(.appSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if uncategorizedCount > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.appWarning)
                            .padding(.top, 1)

                        Text("有 \(uncategorizedCount) 笔暂时归到“其他”，建议点开看一眼分类。你改过一次后，悦笺会尽量记住。")
                            .font(.system(size: 12))
                            .foregroundStyle(.appSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            if showUncategorizedOnly {
                                showUncategorizedOnly = false
                                uncategorizedFocusIndices.removeAll()
                            } else {
                                uncategorizedFocusIndices = Set(
                                    editableItems.enumerated().compactMap { index, item in
                                        item.categoryName == "其他" ? index : nil
                                    }
                                )
                                showUncategorizedOnly = true
                                showAllItems = true
                            }
                        }
                    } label: {
                        Text(showUncategorizedOnly ? String(localized: "查看全部记录") : String(localized: "只看这 \(uncategorizedCount) 笔"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.appWarning)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.appWarningSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.appWarning.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var previewListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("预览记录")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                Spacer()
                if !editableItems.isEmpty {
                    Text(showAllItems
                         ? String(localized: "\(previewGroups.count) 组 · \(editableItems.count) 笔")
                         : String(localized: "前 \(visibleGroups.count) 组"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.appTertiary)
                }
            }

            if editableItems.isEmpty {
                Text("没有新的可导入记录")
                    .font(.system(size: 13))
                    .foregroundStyle(.appSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleGroups) { group in
                        groupRow(group)
                    }
                }

                if previewGroups.count > visibleGroups.count {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            showAllItems = true
                        }
                    } label: {
                        Text("查看全部 \(previewGroups.count) 组 · \(editableItems.count) 笔")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.appAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.appAccentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func groupRow(_ group: ImportPreviewGroup) -> some View {
        guard let firstIndex = group.indices.first, editableItems.indices.contains(firstIndex) else {
            return AnyView(EmptyView())
        }

        let first = editableItems[firstIndex]
        let isExpanded = expandedGroupKeys.contains(group.key)
        let isSingle = group.indices.count == 1
        let total = group.indices.reduce(0) { partial, index in
            partial + (editableItems.indices.contains(index) ? editableItems[index].amount : 0)
        }
        let hasChanges = group.indices.contains { changedIndices.contains($0) }

        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("MdHHmm")

        return AnyView(
            VStack(spacing: 8) {
                Button {
                    categoryEditingTarget = .group(group.key)
                } label: {
                    HStack(spacing: 12) {
                        Text(first.categoryEmoji)
                            .font(.system(size: 20))
                            .frame(width: 32, height: 32)
                            .background(Color.appBg)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                // 单条：展示完整名称（对手+商品）；多条合并：展示交易对手
                                Text(isSingle ? first.name : group.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.appPrimary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)

                                if !isSingle {
                                    Text("\(group.indices.count)笔")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.appAccent)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.appAccentSoft)
                                        .clipShape(Capsule())
                                }
                            }

                            HStack(spacing: 6) {
                                if isSingle {
                                    Text(dateFormatter.string(from: first.date))
                                }
                                Text(first.categoryName.localizedCategoryName)
                                Text(hasChanges ? String(localized: "已修改") : String(localized: "点击修改"))
                                    .foregroundStyle(.appAccent)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.appSecondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Text("\(first.isExpense ? "-" : "+")¥\(String(format: "%.2f", total))")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(first.isExpense ? .appPrimary : .appGreen)

                            if group.indices.count > 1 {
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                        toggleGroup(group.key)
                                    }
                                } label: {
                                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.appTertiary)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.appTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PreviewTapFeedbackStyle())

                if isExpanded {
                    VStack(spacing: 6) {
                        ForEach(group.indices, id: \.self) { index in
                            if editableItems.indices.contains(index) {
                                previewDetailRow(editableItems[index], index: index)
                            }
                        }
                    }
                    .padding(.leading, 44)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        )
    }

    private func previewDetailRow(_ item: ImportedTransaction, index: Int) -> some View {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MdHHmm")

        return Button {
            categoryEditingTarget = .item(index)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.appPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text(formatter.string(from: item.date))
                        Text(item.categoryName.localizedCategoryName)
                        Text(changedIndices.contains(index) ? String(localized: "已修改") : String(localized: "点击修改"))
                            .foregroundStyle(.appAccent)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.appSecondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("\(item.isExpense ? "-" : "+")¥\(String(format: "%.2f", item.amount))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.isExpense ? .appPrimary : .appGreen)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.appTertiary)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PreviewTapFeedbackStyle())
    }

    private func previewStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.appSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.appBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func updateCategory(at indices: [Int], name: String, emoji: String) {
        for index in indices where editableItems.indices.contains(index) {
            editableItems[index] = editableItems[index].applyingCategory(name: name, emoji: emoji)
            changedIndices.insert(index)
        }
    }

    private func indices(for target: CategoryEditingTarget) -> [Int] {
        switch target {
        case .item(let index):
            return editableItems.indices.contains(index) ? [index] : []
        case .group(let key):
            return previewGroups.first(where: { $0.key == key })?.indices ?? []
        }
    }

    private func toggleGroup(_ key: String) {
        if expandedGroupKeys.contains(key) {
            expandedGroupKeys.remove(key)
        } else {
            expandedGroupKeys.insert(key)
        }
    }

    private func groupKey(for item: ImportedTransaction) -> String {
        let type = item.isExpense ? "expense" : "income"
        let groupName = BillImportManager.merchantRuleName(for: item, source: preview.source)
        return "\(type)|\(MerchantCategoryRule.makeKey(groupName))"
    }

    private func groupDisplayName(for item: ImportedTransaction) -> String {
        BillImportManager.merchantRuleName(for: item, source: preview.source)
    }
}

private struct PreviewTapFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.appAccent.opacity(0.10) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ImportPreviewGroup: Identifiable {
    let key: String
    let name: String
    let isExpense: Bool
    let indices: [Int]

    var id: String { key }
}

// MARK: - 导入教程来源（用于 segmented control）

private enum ImportGuideSource: String, CaseIterable, Identifiable {
    case wechat, alipay, yuejian

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wechat:   return String(localized: "微信")
        case .alipay:   return String(localized: "支付宝")
        case .yuejian: return String(localized: "悦笺备份")
        }
    }

    var steps: [String] {
        switch self {
        case .wechat:
            return [
                String(localized: "打开「微信」→「我」→「服务」→「钱包」"),
                String(localized: "进入右上角「账单」→「常见问题」→「下载账单」"),
                String(localized: "按月或时间范围导出，优先 XLSX，CSV 也可"),
                String(localized: "下载完成后回到悦笺，选择该文件即可")
            ]
        case .alipay:
            return [
                String(localized: "打开「支付宝」→「我的」→「账单」"),
                String(localized: "进入右上角更多，选「开具交易流水证明」"),
                String(localized: "按提示选择时间范围并提交"),
                String(localized: "下载完成后选择 CSV 文件导入")
            ]
        case .yuejian:
            return [
                String(localized: "在「我的」→「账单管理」→「导出账单」中导出 CSV"),
                String(localized: "通过「文件」App、AirDrop 或邮件保存这份备份"),
                String(localized: "回到导入页，选择该 CSV 即可还原数据")
            ]
        }
    }
}

private enum CategoryEditingTarget: Identifiable {
    case item(Int)
    case group(String)

    var id: String {
        switch self {
        case .item(let index): return "item-\(index)"
        case .group(let key): return "group-\(key)"
        }
    }
}

// MARK: - 清空数据警告 Sheet

/// 清空数据前的提示页面：克制版。
/// 不罗列删除清单，也不强制门槛——只提供清晰的提示和便捷的备份入口，
/// 让用户做出知情决定（避免误删，但不干预其选择）。
private struct ClearDataWarningSheet: View {
    let lastExportDate: Date?
    let onBackup: () -> Void
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// 是否有过备份记录（仅作信息展示，不再用于门槛禁用）
    private var hasAnyBackup: Bool { lastExportDate != nil }

    private var lastBackupText: String {
        guard let last = lastExportDate else { return String(localized: "从未导出过备份") }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yyyyMMddHHmm")
        let days = Int(Date().timeIntervalSince(last) / (24 * 3600))
        let timeStr = String(f.string(from: last).split(separator: " ").last ?? "")
        return days == 0
            ? String(localized: "上次备份：今天 \(timeStr)")
            : String(localized: "上次备份：\(f.string(from: last))（\(days) 天前）")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    messageCard
                    backupStatusRow
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Color.appBg)
            .navigationTitle("清空数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.appSecondary)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.appRed.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.appRed)
            }
            .padding(.top, 12)

            Text("即将清空所有本地数据")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.appPrimary)
                .multilineTextAlignment(.center)
        }
    }

    private var messageCard: some View {
        Text("所有数据只存在你的本地设备，清空后无法恢复，卸载 app 也是一样。**请先导出一份 CSV 备份**，需要时可以随时再导入回来。")
            .font(.system(size: 13))
            .foregroundStyle(.appSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var backupStatusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: hasAnyBackup ? "checkmark.circle.fill" : "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hasAnyBackup ? .appGreen : .appTertiary)
            Text(lastBackupText)
                .font(.system(size: 12))
                .foregroundStyle(.appSecondary)
            Spacer()
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // 主推：先导出备份（视觉权重最高，让用户走更稳妥的路径）
            Button(action: onBackup) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.up.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("先导出备份")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.appAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            // 次按钮：始终可用，不再门槛禁用
            Button(action: onContinue) {
                Text("继续清空")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.appRed.opacity(0.7), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
