import Foundation
import SwiftData
import zlib // libz is bundled with Apple platforms; if linker error: add -lz to Other Linker Flags

// MARK: - Parsed row before mapping to Transaction

struct ImportedTransaction {
    let date: Date
    let amount: Double      // always positive
    let isExpense: Bool
    let name: String
    let merchantName: String?
    let categoryName: String
    let categoryEmoji: String
    let note: String

    func applyingCategory(name categoryName: String, emoji categoryEmoji: String) -> ImportedTransaction {
        ImportedTransaction(
            date: date,
            amount: amount,
            isExpense: isExpense,
            name: name,
            merchantName: merchantName,
            categoryName: categoryName,
            categoryEmoji: categoryEmoji,
            note: note
        )
    }
}

// MARK: - Errors

enum BillImportError: Error, LocalizedError {
    case unsupportedFormat
    case encodingError
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return String(localized: "不支持的文件格式。\n悦笺支持微信支付 CSV / XLSX、支付宝 CSV、悦笺备份 CSV，请重新选择对应文件。")
        case .encodingError:
            return String(localized: "文件编码无法识别，请尝试重新导出原始账单后再导入。")
        case .parseError:
            return String(localized: "文件内容无法识别。\n请确认选择的是微信支付、支付宝或悦笺的原始导出文件，且文件未经任何修改。")
        }
    }
}

// MARK: - CSV Localization Helper

/// Provides three-language mappings for CSV headers, type labels, and default category names.
/// Export uses the current UI language; import recognises all three variants.
enum CSVLocalization {

    // ── Headers ────────────────────────────────────────────────────────

    struct Headers {
        let transactionTime: String
        let name: String
        let amount: String
        let type: String
        let category: String
        let categoryIcon: String
        let note: String
        let isRefunded: String
        let createdAt: String

        var array: [String] {
            [transactionTime, name, amount, type, category, categoryIcon, note, isRefunded, createdAt]
        }
    }

    static let zhHans = Headers(
        transactionTime: "交易时间", name: "名称", amount: "金额", type: "类型",
        category: "分类", categoryIcon: "分类图标", note: "备注",
        isRefunded: "是否退款", createdAt: "创建时间")

    static let zhHant = Headers(
        transactionTime: "交易時間", name: "名稱", amount: "金額", type: "類型",
        category: "分類", categoryIcon: "分類圖示", note: "備註",
        isRefunded: "是否退款", createdAt: "建立時間")

    static let en = Headers(
        transactionTime: "Transaction Time", name: "Name", amount: "Amount", type: "Type",
        category: "Category", categoryIcon: "Category Icon", note: "Note",
        isRefunded: "Is Refunded", createdAt: "Created At")

    /// All known "category icon" header variants — used to detect YueJian format on import.
    static let allCategoryIconHeaders = [zhHans.categoryIcon, zhHant.categoryIcon, en.categoryIcon]

    /// Headers for the current UI language.
    static var current: Headers {
        let lang = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        if lang.hasPrefix("en") { return en }
        if lang == "zh-Hant" || lang.hasPrefix("zh-Hant") { return zhHant }
        return zhHans
    }

    // ── Type labels (支出 / 收入) ──────────────────────────────────────

    struct TypeLabels {
        let expense: String
        let income: String
    }

    static let typeZhHans = TypeLabels(expense: "支出", income: "收入")
    static let typeZhHant = TypeLabels(expense: "支出", income: "收入")
    static let typeEn     = TypeLabels(expense: "Expense", income: "Income")

    static var currentType: TypeLabels {
        let lang = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        if lang.hasPrefix("en") { return typeEn }
        if lang == "zh-Hant" || lang.hasPrefix("zh-Hant") { return typeZhHant }
        return typeZhHans
    }

    /// Returns true if the value means "expense" in any supported language.
    static func isExpenseLabel(_ value: String) -> Bool {
        value == "支出" || value == "Expense"
    }

    /// Returns true if the value means "expense" or "income" in any supported language.
    static func isTypeLabel(_ value: String) -> Bool {
        ["支出", "收入", "Expense", "Income"].contains(value)
    }

    // ── Refund labels (是 / 否) ────────────────────────────────────────

    struct RefundLabels {
        let yes: String
        let no: String
    }

    static let refundZhHans = RefundLabels(yes: "是", no: "否")
    static let refundZhHant = RefundLabels(yes: "是", no: "否")
    static let refundEn     = RefundLabels(yes: "Yes", no: "No")

    static var currentRefund: RefundLabels {
        let lang = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        if lang.hasPrefix("en") { return refundEn }
        if lang == "zh-Hant" || lang.hasPrefix("zh-Hant") { return refundZhHant }
        return refundZhHans
    }

    /// Returns true if the value means "refunded" in any supported language.
    static func isRefundedLabel(_ value: String) -> Bool {
        value == "是" || value == "Yes"
    }

    // ── Default category name mapping ──────────────────────────────────
    // Key = zh-Hans canonical name (stored in DB).
    // On export: canonical → localized.  On import: localized → canonical.

    private static let categoryMap: [(zhHans: String, en: String, zhHant: String)] = [
        // expense
        ("餐饮", "Food",          "餐飲"),
        ("交通", "Transport",     "交通"),
        ("咖啡", "Coffee",        "咖啡"),
        ("购物", "Shopping",      "購物"),
        ("旅游", "Travel",        "旅遊"),
        ("娱乐", "Entertainment", "娛樂"),
        ("医疗", "Medical",       "醫療"),
        ("住房", "Housing",       "住房"),
        ("通讯", "Phone",         "通訊"),
        ("教育", "Education",     "教育"),
        ("运动", "Fitness",       "運動"),
        ("美妆", "Beauty",        "美妝"),
        ("宠物", "Pets",          "寵物"),
        ("人情", "Social",        "人情"),
        ("红包", "Red Packet",    "紅包"),
        ("其他", "Other",         "其他"),
        // income
        ("工资", "Salary",        "薪資"),
        ("奖金", "Bonus",         "獎金"),
        ("兼职", "Part-time",     "兼職"),
        ("投资", "Investment",    "投資"),
        ("退款", "Refund",        "退款"),
        ("转账", "Transfer",      "轉帳"),
    ]

    /// Reverse lookup: any language → zh-Hans canonical name.
    /// Custom category names not in the map are returned as-is.
    private static let reverseMap: [String: String] = {
        var m: [String: String] = [:]
        for entry in categoryMap {
            m[entry.zhHans] = entry.zhHans
            m[entry.en]     = entry.zhHans
            m[entry.zhHant] = entry.zhHans
        }
        return m
    }()

    /// Forward lookup: zh-Hans canonical → localized name for current UI language.
    /// Custom category names not in the map are returned as-is.
    private static let forwardMap: [String: [String: String]] = {
        var m: [String: [String: String]] = [:]
        for entry in categoryMap {
            m[entry.zhHans] = ["en": entry.en, "zh-Hant": entry.zhHant, "zh-Hans": entry.zhHans]
        }
        return m
    }()

    /// Convert a canonical (zh-Hans) category name to the current UI language.
    static func localizedCategoryName(_ canonical: String) -> String {
        let lang = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        let langKey: String
        if lang.hasPrefix("en") { langKey = "en" }
        else if lang == "zh-Hant" || lang.hasPrefix("zh-Hant") { langKey = "zh-Hant" }
        else { langKey = "zh-Hans" }
        return forwardMap[canonical]?[langKey] ?? canonical
    }

    /// Convert a possibly-localized category name back to zh-Hans canonical form.
    static func canonicalCategoryName(_ localized: String) -> String {
        reverseMap[localized] ?? localized
    }
}

// MARK: - Manager

final class BillImportManager {

    // MARK: Entry point

    static func parse(url: URL) throws -> [ImportedTransaction] {
        let ext = url.pathExtension.lowercased()
        let data = try Data(contentsOf: url)
        switch ext {
        case "csv":  return try parseCSV(data)
        case "xlsx": return try parseXLSX(data)
        default:     throw BillImportError.unsupportedFormat
        }
    }

    /// 通过文件内容识别来源（"轻账" / "微信" / "支付宝"），在 handleFile 里用于决定是否跳过商户规则
    static func detectSource(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "xlsx" { return "微信" }

        guard let data = try? Data(contentsOf: url) else { return "支付宝" }

        let gbkEnc = String.Encoding(rawValue:
            CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

        // Use the first line only to avoid splitting a multi-byte emoji mid-sequence.
        // The header line is always < 200 bytes, so searching the first 1024 bytes is enough.
        let searchChunk = data.prefix(1024)
        let headerEnd = searchChunk.firstIndex(of: 0x0A) ?? searchChunk.endIndex
        let headerData = data[data.startIndex..<headerEnd]

        let preview = String(data: headerData, encoding: .utf8)
                   ?? String(data: headerData, encoding: gbkEnc)
                   ?? ""

        if CSVLocalization.allCategoryIconHeaders.contains(where: { preview.contains($0) }) { return "轻账" }
        if preview.contains("交易类型") { return "微信" }
        return "支付宝"
    }

    // MARK: Save

    static func summarizeImport(_ items: [ImportedTransaction], context: ModelContext) -> (newItems: [ImportedTransaction], skipped: Int) {
        let existing = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let existingKeys = Set(existing.map { dupKey($0.date, $0.absoluteAmount) })

        var newItems: [ImportedTransaction] = []
        var skipped = 0
        for item in items {
            if existingKeys.contains(dupKey(item.date, item.amount)) {
                skipped += 1
            } else {
                newItems.append(item)
            }
        }
        return (newItems, skipped)
    }

    static func applyMerchantRules(
        to items: [ImportedTransaction],
        source: String,
        context: ModelContext
    ) -> [ImportedTransaction] {
        let rules = (try? context.fetch(FetchDescriptor<MerchantCategoryRule>())) ?? []
        guard !rules.isEmpty else { return items }

        var exactRules: [String: MerchantCategoryRule] = [:]
        var generalRules: [String: MerchantCategoryRule] = [:]
        for rule in rules {
            exactRules[ruleLookupKey(source: rule.source, type: rule.type, merchantKey: rule.merchantKey)] = rule
            if rule.source == "通用" {
                generalRules[ruleLookupKey(source: "通用", type: rule.type, merchantKey: rule.merchantKey)] = rule
            }
        }

        var usedRuleIDs = Set<UUID>()
        let mapped = items.map { item in
            let type = item.isExpense ? "expense" : "income"
            let merchantKey = MerchantCategoryRule.makeKey(merchantRuleName(for: item, source: source))
            let sourceKey = ruleLookupKey(source: source, type: type, merchantKey: merchantKey)
            let generalKey = ruleLookupKey(source: "通用", type: type, merchantKey: merchantKey)
            guard let rule = exactRules[sourceKey] ?? generalRules[generalKey] else {
                return item
            }
            usedRuleIDs.insert(rule.id)
            return item.applyingCategory(name: rule.categoryName, emoji: rule.categoryEmoji)
        }

        if !usedRuleIDs.isEmpty {
            let now = Date()
            for rule in rules where usedRuleIDs.contains(rule.id) {
                rule.useCount += 1
                rule.updatedAt = now
            }
            try? context.save()
        }

        return mapped
    }

    static func upsertMerchantRule(
        for item: ImportedTransaction,
        source: String,
        categoryName: String,
        categoryEmoji: String,
        context: ModelContext
    ) {
        let ruleName = merchantRuleName(for: item, source: source)
        let merchantKey = MerchantCategoryRule.makeKey(ruleName)
        guard !merchantKey.isEmpty else { return }

        let type = item.isExpense ? "expense" : "income"
        let rules = (try? context.fetch(FetchDescriptor<MerchantCategoryRule>())) ?? []
        if let existing = rules.first(where: {
            $0.source == "通用" && $0.type == type && $0.merchantKey == merchantKey
        }) ?? rules.first(where: {
            $0.source == source && $0.type == type && $0.merchantKey == merchantKey
        }) {
            existing.merchantName = ruleName
            existing.source = "通用"
            existing.categoryName = categoryName
            existing.categoryEmoji = categoryEmoji
            existing.updatedAt = Date()
        } else {
            context.insert(MerchantCategoryRule(
                merchantName: ruleName,
                source: "通用",
                type: type,
                categoryName: categoryName,
                categoryEmoji: categoryEmoji
            ))
        }
        try? context.save()
    }

    static func save(_ items: [ImportedTransaction], context: ModelContext) -> (saved: Int, skipped: Int) {
        let summary = summarizeImport(items, context: context)

        var saved = 0
        for item in summary.newItems {
            let tx = Transaction(
                name: item.name,
                categoryName: item.categoryName,
                categoryEmoji: item.categoryEmoji,
                amount: item.isExpense ? -item.amount : item.amount,
                date: item.date,
                note: item.note
            )
            context.insert(tx)
            saved += 1
        }
        try? context.save()
        return (saved, summary.skipped)
    }

    private static func dupKey(_ date: Date, _ amount: Double) -> String {
        let t = Int(date.timeIntervalSince1970 / 60) // minute bucket
        return "\(t)_\(Int(amount * 100))"
    }

    private static func ruleLookupKey(source: String, type: String, merchantKey: String) -> String {
        "\(source)|\(type)|\(merchantKey)"
    }

    static func merchantRuleName(for item: ImportedTransaction, source: String) -> String {
        if source == "微信", let merchantName = item.merchantName?.trimmed, !merchantName.isEmpty, merchantName != "/" {
            return merchantName
        }
        return item.name
    }

    // MARK: - CSV

    private static func parseCSV(_ data: Data) throws -> [ImportedTransaction] {
        let gbkEnc = String.Encoding(rawValue:
            CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

        guard let content = String(data: data, encoding: gbkEnc) ??
                             String(data: data, encoding: .utf8) else {
            throw BillImportError.encodingError
        }

        // 去掉 UTF-8 BOM（轻账导出文件带 BOM）
        let stripped = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content
        let lines = stripped.components(separatedBy: .newlines)

        // 优先检测轻账格式（含 "分类图标" / "分類圖示" / "Category Icon" 列）
        if let headerIdx = lines.firstIndex(where: { line in
            CSVLocalization.allCategoryIconHeaders.contains(where: { line.contains($0) })
        }) {
            let dataLines = Array(lines.dropFirst(headerIdx + 1))
            return parseQingZhangCSVLines(dataLines)
        }

        // 微信 / 支付宝格式
        guard let headerIdx = lines.firstIndex(where: {
            $0.contains("交易时间") && $0.contains("收/支")
        }) else {
            throw BillImportError.parseError(String(localized: "找不到表头行，请确认文件来自微信支付、支付宝或悦笺导出"))
        }

        let isWeChat = lines[headerIdx].contains("交易类型")
        let dataLines = Array(lines.dropFirst(headerIdx + 1))

        return isWeChat
            ? parseWeChatCSVLines(dataLines)
            : parseAlipayCSVLines(dataLines)
    }

    // 轻账导出格式列顺序：交易时间, 名称, 金额, 类型, 分类, 分类图标, 备注, 是否退款, 创建时间
    // 金额：支出为负数，收入为正数（与微信/支付宝不同，直接使用原值绝对值）
    // 日期格式兼容：标准导出 "yyyy-MM-dd HH:mm:ss" 以及斜杠格式 "yyyy/M/d HH:mm"
    private static func parseQingZhangCSVLines(_ lines: [String]) -> [ImportedTransaction] {
        let df1 = makeDateFormatter("yyyy-MM-dd HH:mm:ss")
        let df2 = makeDateFormatter("yyyy/M/d HH:mm:ss")
        let df3 = makeDateFormatter("yyyy/M/d HH:mm")
        func parseDate(_ s: String) -> Date? {
            df1.date(from: s) ?? df2.date(from: s) ?? df3.date(from: s)
        }
        return lines.compactMap { line in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let cols = csvSplit(line)
            guard cols.count >= 8 else { return nil }

            // 跳过退款记录（退款本身是对支出的冲销，导入意义不大）
            // 支持三语：是 / Yes
            let isRefunded = CSVLocalization.isRefundedLabel(cols[7].trimmed)
            guard !isRefunded else { return nil }

            guard let date   = parseDate(cols[0].trimmed),
                  let amount = Double(cols[2].trimmed) else { return nil }

            // 支持三语：支出/收入 / Expense/Income
            let type = cols[3].trimmed
            guard CSVLocalization.isTypeLabel(type) else { return nil }

            // 分类名可能是英文或繁中，反查回简中规范键
            let rawCategory = cols[4].trimmed
            let canonicalCategory = CSVLocalization.canonicalCategoryName(rawCategory)

            return ImportedTransaction(
                date:          date,
                amount:        abs(amount),   // ImportedTransaction 约定存绝对值
                isExpense:     CSVLocalization.isExpenseLabel(type),
                name:          cols[1].trimmed,
                merchantName:  nil,
                categoryName:  canonicalCategory,
                categoryEmoji: cols[5].trimmed,
                note:          cols[6].trimmed
            )
        }
    }

    // Alipay columns: 交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,...,交易状态,...
    private static func parseAlipayCSVLines(_ lines: [String]) -> [ImportedTransaction] {
        let df = makeDateFormatter("yyyy-MM-dd HH:mm:ss")
        return lines.compactMap { line in
            let cols = csvSplit(line)
            guard cols.count >= 9 else { return nil }
            let direction = cols[5].trimmed
            guard direction == "支出" || direction == "收入" else { return nil }
            let status = cols[8].trimmed
            guard status != "交易关闭" && status != "交易失败" else { return nil }
            guard let date = df.date(from: cols[0].trimmed),
                  let amount = Double(cols[6].trimmed) else { return nil }
            let isExpense = direction == "支出"
            let product  = cols[4].trimmed
            let merchant = cols[2].trimmed
            let name = (product.isEmpty || product == "/") ? merchant : product
            let cat = alipayCategory(cols[1].trimmed, isExpense: isExpense)
            return ImportedTransaction(date: date, amount: amount, isExpense: isExpense,
                                       name: name, merchantName: merchant, categoryName: cat.0, categoryEmoji: cat.1,
                                       note: "支付宝导入")
        }
    }

    // WeChat CSV columns: 交易时间,交易类型,交易对方,商品,收/支,金额(元),...,当前状态,...
    private static func parseWeChatCSVLines(_ lines: [String]) -> [ImportedTransaction] {
        let df = makeDateFormatter("yyyy-MM-dd HH:mm:ss")
        let skipTypes: Set<String> = ["购买理财通","零钱通存入","零钱通取出","提现","充值","信用卡还款"]
        return lines.compactMap { line in
            let cols = csvSplit(line)
            guard cols.count >= 8 else { return nil }
            let direction = cols[4].trimmed
            guard direction == "支出" || direction == "收入" else { return nil }
            let txType = cols[1].trimmed
            guard !skipTypes.contains(txType) else { return nil }
            guard cols[7].trimmed != "已全额退款" else { return nil }
            guard let date = df.date(from: cols[0].trimmed),
                  let amount = Double(cols[5].trimmed.replacingOccurrences(of: "¥", with: ""))
            else { return nil }
            let isExpense = direction == "支出"
            let merchant = cols[2].trimmed
            let product  = sanitizedWeChatProductName(cols[3].trimmed)
            let name = wechatDisplayName(merchant: merchant, product: product)
            let cat = wechatCategory(txType, merchant: merchant, product: product, isExpense: isExpense)
            return ImportedTransaction(date: date, amount: amount, isExpense: isExpense,
                                       name: name, merchantName: merchant, categoryName: cat.0, categoryEmoji: cat.1,
                                       note: product)
        }
    }

    // MARK: - XLSX (WeChat)

    private static func parseXLSX(_ data: Data) throws -> [ImportedTransaction] {
        guard let strData   = extractFromZip(data, path: "xl/sharedStrings.xml"),
              let sheetData = extractFromZip(data, path: "xl/worksheets/sheet1.xml") else {
            throw BillImportError.parseError(String(localized: "无法读取 XLSX 内部结构"))
        }
        let sharedStrings = parseSharedStrings(strData)
        let rows = parseSheet(sheetData, sharedStrings: sharedStrings)

        guard let headerIdx = rows.firstIndex(where: {
            $0.contains("交易时间") && $0.contains("收/支")
        }) else {
            throw BillImportError.parseError(String(localized: "找不到表头行"))
        }

        let dataRows = Array(rows.dropFirst(headerIdx + 1))
        return parseWeChatXLSXRows(dataRows)
    }

    // WeChat XLSX rows: 交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,...
    private static func parseWeChatXLSXRows(_ rows: [[String]]) -> [ImportedTransaction] {
        let df = makeDateFormatter("yyyy-MM-dd HH:mm:ss")
        let skipTypes: Set<String> = ["购买理财通","零钱通存入","零钱通取出","提现","充值","信用卡还款"]
        return rows.compactMap { cols in
            guard cols.count >= 8 else { return nil }
            let direction = cols[4].trimmed
            guard direction == "支出" || direction == "收入" else { return nil }
            let txType = cols[1].trimmed
            guard !skipTypes.contains(txType) else { return nil }
            guard cols[7].trimmed != "已全额退款" else { return nil }

            let rawDate = cols[0].trimmed
            guard let date = parseWeChatDate(rawDate, formatter: df) else { return nil }

            let amtStr = cols[5].trimmed.replacingOccurrences(of: "¥", with: "")
            guard let amount = Double(amtStr) else { return nil }

            let isExpense = direction == "支出"
            let merchant = cols[2].trimmed
            let product  = sanitizedWeChatProductName(cols[3].trimmed)
            let name = wechatDisplayName(merchant: merchant, product: product)
            let cat = wechatCategory(txType, merchant: merchant, product: product, isExpense: isExpense)
            return ImportedTransaction(date: date, amount: amount, isExpense: isExpense,
                                       name: name, merchantName: merchant, categoryName: cat.0, categoryEmoji: cat.1,
                                       note: product)
        }
    }

    // MARK: - ZIP reader

    private static func extractFromZip(_ data: Data, path: String) -> Data? {
        var offset = 0
        while offset + 30 <= data.count {
            // Local file header signature: PK\x03\x04
            guard data[offset] == 0x50, data[offset+1] == 0x4B,
                  data[offset+2] == 0x03, data[offset+3] == 0x04 else {
                offset += 1; continue
            }
            let method      = data.u16(at: offset + 8)
            let compressed  = Int(data.u32(at: offset + 18))
            let nameLen     = Int(data.u16(at: offset + 26))
            let extraLen    = Int(data.u16(at: offset + 28))
            let nameStart   = offset + 30
            guard nameStart + nameLen <= data.count else { break }
            let entryName   = String(data: data[nameStart..<nameStart+nameLen], encoding: .utf8) ?? ""
            let dataStart   = nameStart + nameLen + extraLen
            let dataEnd     = dataStart + compressed
            guard dataEnd <= data.count else { break }

            if entryName == path {
                let payload = Data(data[dataStart..<dataEnd])
                if method == 0 { return payload }
                if method == 8 { return deflateInflate(payload) }
            }
            offset = compressed > 0 ? dataEnd : dataStart + 1
        }
        return nil
    }

    /// Raw DEFLATE (ZIP method 8) decompression via zlib with -15 windowBits.
    private static func deflateInflate(_ data: Data) -> Data? {
        var result = Data()
        var stream = z_stream()
        let initStatus = data.withUnsafeBytes { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return Z_DATA_ERROR }
            stream.next_in  = UnsafeMutablePointer(mutating: base.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(data.count)
            return inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var buf = [UInt8](repeating: 0, count: 65536)
        var ret = Z_OK
        repeat {
            buf.withUnsafeMutableBufferPointer { ptr in
                stream.next_out  = ptr.baseAddress!
                stream.avail_out = uInt(ptr.count)
            }
            ret = inflate(&stream, Z_SYNC_FLUSH)
            let produced = buf.count - Int(stream.avail_out)
            result.append(contentsOf: buf.prefix(produced))
        } while ret == Z_OK
        return ret == Z_STREAM_END ? result : nil
    }

    // MARK: - XLSX XML parsers

    private static func parseSharedStrings(_ data: Data) -> [String] {
        let d = SharedStringsDelegate()
        let p = XMLParser(data: data); p.delegate = d; p.parse()
        return d.strings
    }

    private static func parseSheet(_ data: Data, sharedStrings: [String]) -> [[String]] {
        let d = SheetDelegate(sharedStrings: sharedStrings)
        let p = XMLParser(data: data); p.delegate = d; p.parse()
        return d.rows
    }

    // MARK: - Category mapping

    private static func alipayCategory(_ cat: String, isExpense: Bool) -> (String, String) {
        if !isExpense { return ("工资", "💰") }
        switch cat {
        case "餐饮美食":           return ("餐饮", "🍜")
        case "交通出行":           return ("交通", "🚇")
        case "旅行出游":           return ("旅游", "✈️")
        case "咖啡":              return ("咖啡", "☕️")
        case "日用百货","网络购物",
             "数码电器","服饰装扮": return ("购物", "🛒")
        case "文化休闲","亲子娱乐": return ("娱乐", "🎬")
        case "医疗健康":           return ("医疗", "💊")
        case "住房物业","水电煤":   return ("住房", "🏠")
        case "充值缴费":           return ("通讯", "📱")
        case "教育培训":           return ("教育", "🎓")
        case "运动健身":           return ("运动", "🏃")
        default:                  return ("其他", "💡")
        }
    }

    private static func wechatCategory(_ txType: String, merchant: String, product: String, isExpense: Bool) -> (String, String) {
        if txType.contains("微信红包") { return ("红包", "🧧") }
        if !isExpense { return ("工资", "💰") }

        // 微信账单里，真实语义通常藏在“交易对方 + 商品”里；
        // “交易类型”更多用于辅助判断二维码、团购、转账等上下文。
        let primaryText = normalizeText("\(merchant) \(product)")
        let typeText = normalizeText(txType)
        let text = "\(primaryText) \(typeText)"

        if containsAny(text, keywords: [
            "luckin","manner","starbucks","瑞幸","星巴克","库迪","mstand",
            "咖啡","奶茶","喜茶","奈雪","茶百道","沪上阿姨","coco","茶颜","霸王茶姬","饮品"
        ]) {
            return ("咖啡", "☕️")
        }

        if containsAny(text, keywords: [
            "外卖","美食","餐厅","火锅","烧烤","烤肉","麻辣烫","面馆","米线","米粉","盖饭",
            "早餐","宵夜","食堂","小吃","汉堡","披萨","炸鸡","肯德基","麦当劳","必胜客",
            "沙县","兰州拉面","螺蛳粉","餐饮","饭店","料理","烘焙","甜品","煎饼","点餐",
            "堂食","团购","大众点评","秦大碗","餐"
        ]) {
            return ("餐饮", "🍜")
        }

        if containsAny(text, keywords: [
            "滴滴","地铁","公交","打车","出租车","顺风车","12306","高铁","火车票","机票",
            "航班","停车","高速","加油","充电站","充电平台","自助充电","单车","哈啰","青桔",
            "美团单车","蔚来","nio","汽车","交通"
        ]) {
            return ("交通", "🚇")
        }

        if containsAny(text, keywords: [
            "酒店","民宿","度假","景区","门票","旅行","旅游","出游","携程","飞猪","同程",
            "airbnb","booking","环球影城","迪士尼","机酒","邮轮"
        ]) {
            return ("旅游", "✈️")
        }

        if containsAny(text, keywords: [
            "电影","演出","剧场","ktv","酒吧","桌游","密室","游戏","电玩","网吧",
            "爱奇艺","腾讯视频","优酷","bilibili","哔哩哔哩","网易云","qq音乐","会员","娱乐"
        ]) {
            return ("娱乐", "🎬")
        }

        if containsAny(text, keywords: [
            "医院","药店","药房","口腔","诊所","挂号","检查","体检","中医","西医",
            "牙科","医药","药","诊"
        ]) {
            return ("医疗", "💊")
        }

        if containsAny(text, keywords: [
            "房租","租金","物业","水费","电费","燃气","煤气","供暖","宽带","房贷","住房"
        ]) {
            return ("住房", "🏠")
        }

        if containsAny(text, keywords: [
            "话费","流量","套餐","充值缴费","中国移动","中国联通","中国电信","通信","宽带续费"
        ]) {
            return ("通讯", "📱")
        }

        if containsAny(text, keywords: [
            "课程","培训","学费","教材","书店","书籍","考试","报名","驾校","教育"
        ]) {
            return ("教育", "🎓")
        }

        if containsAny(text, keywords: [
            "健身","瑜伽","游泳","羽毛球","篮球","足球","跑步","训练","运动"
        ]) {
            return ("运动", "🏃")
        }

        if containsAny(text, keywords: [
            "口红","粉底","面膜","护肤","彩妆","香水","丝芙兰","sephora","屈臣氏美妆",
            "美妆","美容","美甲","理发","剪发","烫发","染发"
        ]) {
            return ("美妆", "💄")
        }

        if containsAny(text, keywords: [
            "宠物","猫粮","狗粮","宠粮","宠物医院","宠物店","猫砂","宠物美容","宠物用品","猫","狗"
        ]) {
            return ("宠物", "🐾")
        }

        if containsAny(text, keywords: [
            "礼物","鲜花","礼金","份子","红包礼","伴手礼","人情","祝福","满月酒","婚礼","生日礼"
        ]) {
            return ("人情", "🎀")
        }

        if containsAny(text, keywords: [
            "超市","便利店","全家","罗森","7eleven","711","京东","淘宝","天猫","拼多多",
            "盒马","山姆","costco","屈臣氏","名创优品","宜家","商场","闪购","购物","百货",
            "citysuper","奥乐齐","aldi","lawson","zara","得物"
        ]) {
            return ("购物", "🛒")
        }

        return ("其他", "💡")
    }

    // MARK: - Helpers

    private static func csvSplit(_ line: String) -> [String] {
        var fields: [String] = []
        var cur = "", inQ = false
        for ch in line {
            if ch == "\"" { inQ.toggle() }
            else if ch == "," && !inQ { fields.append(cur.trimmed); cur = "" }
            else { cur.append(ch) }
        }
        fields.append(cur.trimmed)
        return fields
    }

    private static func makeDateFormatter(_ fmt: String) -> DateFormatter {
        let df = DateFormatter()
        df.dateFormat = fmt
        df.locale = Locale(identifier: "zh_CN")
        df.timeZone = .current
        return df
    }

    private static func wechatDisplayName(merchant: String, product: String) -> String {
        let merchant = merchant.trimmed
        let product = product.trimmed

        let merchantEmpty = merchant.isEmpty || merchant == "/"
        let productEmpty = product.isEmpty || product == "/"

        if merchantEmpty { return product }
        if productEmpty { return merchant }
        if merchant == product { return merchant }
        if product.contains(merchant) { return product }
        return "\(merchant)-\(product)"
    }

    private static func sanitizedWeChatProductName(_ product: String) -> String {
        guard !product.isEmpty else { return product }

        for separator in ["-", "_"] {
            guard let range = product.range(of: separator) else { continue }
            let suffixStart = range.upperBound
            let suffix = product[suffixStart...]

            let digits = suffix.prefix { $0.isNumber }
            if digits.count > 5 {
                return String(product[..<range.lowerBound]).trimmed
            }
        }

        return product
    }

    private static func parseWeChatDate(_ raw: String, formatter: DateFormatter) -> Date? {
        if let date = formatter.date(from: raw) {
            return date
        }

        guard let serial = Double(raw) else { return nil }
        let wholeDays = Int(serial.rounded(.down))
        let seconds = Int(((serial - Double(wholeDays)) * 86400).rounded())

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        var base = DateComponents()
        base.calendar = calendar
        base.timeZone = .current
        base.year = 1899
        base.month = 12
        base.day = 30
        base.hour = 0
        base.minute = 0
        base.second = 0

        guard let baseDate = calendar.date(from: base),
              let dayDate = calendar.date(byAdding: .day, value: wholeDays, to: baseDate) else {
            return nil
        }
        return calendar.date(byAdding: .second, value: seconds, to: dayDate)
    }

    private static func normalizeText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }

    private static func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

// MARK: - Data helpers

private extension Data {
    func u16(at i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i+1]) << 8 }
    func u32(at i: Int) -> UInt32 {
        UInt32(self[i]) | UInt32(self[i+1]) << 8 | UInt32(self[i+2]) << 16 | UInt32(self[i+3]) << 24
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - SharedStrings XML delegate

private class SharedStringsDelegate: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var cur = "", inT = false

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if el == "si" { cur = "" }
        if el == "t"  { inT = true }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { if inT { cur += s } }
    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        if el == "t"  { inT = false }
        if el == "si" { strings.append(cur) }
    }
}

// MARK: - Sheet XML delegate

private class SheetDelegate: NSObject, XMLParserDelegate {
    let ss: [String]
    var rows: [[String]] = []

    private var rowBuf: [Int: String] = [:] // col index → value
    private var cellVal = "", cellType = "", cellRef = ""
    private var inV = false, maxCol = 0

    init(sharedStrings: [String]) { ss = sharedStrings }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if el == "row"  { rowBuf = [:]; maxCol = 0 }
        if el == "c"    { cellType = attributes["t"] ?? ""; cellRef = attributes["r"] ?? ""; cellVal = "" }
        if el == "v"    { inV = true }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { if inV { cellVal += s } }
    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        if el == "v" {
            inV = false
            let resolved = (cellType == "s") ? (Int(cellVal).flatMap { $0 < ss.count ? ss[$0] : nil } ?? cellVal) : cellVal
            let col = colIndex(cellRef)
            rowBuf[col] = resolved
            maxCol = max(maxCol, col)
        }
        if el == "row" {
            guard !rowBuf.isEmpty else { return }
            let arr = (0...maxCol).map { rowBuf[$0] ?? "" }
            rows.append(arr)
        }
    }

    /// "A1" → 0, "B3" → 1, "AA5" → 26
    private func colIndex(_ ref: String) -> Int {
        var col = 0
        for ch in ref.prefix(while: { $0.isLetter }) {
            col = col * 26 + Int(ch.asciiValue! - 64)
        }
        return max(col - 1, 0)
    }
}
