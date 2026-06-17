import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var name: String
    var emoji: String
    /// "expense" or "income"
    var type: String
    var sortOrder: Int
    var isCustom: Bool

    init(name: String, emoji: String, type: String, sortOrder: Int, isCustom: Bool = false) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.type = type
        self.sortOrder = sortOrder
        self.isCustom = isCustom
    }

    var isExpense: Bool { type == "expense" }
}

// MARK: - 分类名本地化
extension String {
    /// 默认分类名 → 当前语言的显示名。
    /// 中文名作为数据库里的规范键保持不变，只在 UI 显示时查表本地化；
    /// 自定义分类名（不在 catalog 里）会原样返回。
    var localizedCategoryName: String {
        NSLocalizedString(self, comment: "Category name")
    }
}

// MARK: - Default categories
extension Category {
    static let defaultExpenseCategories: [(String, String)] = [
        ("餐饮", "🍜"),
        ("咖啡", "☕️"),
        ("零食", "🍿"),
        ("交通", "🚇"),
        ("购物", "🛒"),
        ("日用", "🧺"),
        ("服饰", "👔"),
        ("娱乐", "🎬"),
        ("订阅", "📺"),
        ("旅游", "✈️"),
        ("住房", "🏠"),
        ("通讯", "📱"),
        ("医疗", "💊"),
        ("美妆", "💄"),
        ("教育", "🎓"),
        ("运动", "🏃"),
        ("宠物", "🐾"),
        ("母婴", "🍼"),
        ("人情", "🧧"),
        ("其他", "💡"),
    ]

    static let defaultIncomeCategories: [(String, String)] = [
        ("工资", "💰"),
        ("报销", "🧾"),
        ("奖金", "🎁"),
        ("兼职", "💻"),
        ("人情", "🧧"),
        ("投资", "📈"),
        ("退款", "↩️"),
        ("其他", "⭐"),
    ]

    static func seedDefaultCategories(context: ModelContext) {
        let descriptor = FetchDescriptor<Category>()
        let existingCategories = (try? context.fetch(descriptor)) ?? []

        // 迁移：红包 → 人情（2026-06 改名，更国际化）。
        // 同时改名同类型分类与历史交易，避免与新种子重复、保持统计口径一致。
        // 仅当同类型尚无「人情」时重命名，防止与已存在的人情撞名产生重复。
        let existingRenqingTypes = Set(existingCategories.filter { $0.name == "人情" }.map(\.type))
        for cat in existingCategories where cat.name == "红包" && !existingRenqingTypes.contains(cat.type) {
            cat.name = "人情"
        }
        let hongbaoTx = (try? context.fetch(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.categoryName == "红包" })
        )) ?? []
        for tx in hongbaoTx { tx.categoryName = "人情" }

        var existingKeys = Set(existingCategories.map { "\($0.type)|\($0.name)" })

        // 新增分类追加到 sortOrder 末尾——首次种子时 max(空) = -1，自然从 0 开始；
        // 已有数据时则从现有最大值之后续编，避免打乱老用户的顺序。
        var nextExpenseOrder = (existingCategories.filter { $0.type == "expense" }.map(\.sortOrder).max() ?? -1) + 1
        var nextIncomeOrder  = (existingCategories.filter { $0.type == "income"  }.map(\.sortOrder).max() ?? -1) + 1

        for (name, emoji) in defaultExpenseCategories where !existingKeys.contains("expense|\(name)") {
            context.insert(Category(name: name, emoji: emoji, type: "expense", sortOrder: nextExpenseOrder))
            existingKeys.insert("expense|\(name)")
            nextExpenseOrder += 1
        }
        for (name, emoji) in defaultIncomeCategories where !existingKeys.contains("income|\(name)") {
            context.insert(Category(name: name, emoji: emoji, type: "income", sortOrder: nextIncomeOrder))
            existingKeys.insert("income|\(name)")
            nextIncomeOrder += 1
        }
        try? context.save()
    }
}
