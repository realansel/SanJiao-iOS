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
        ("交通", "🚇"),
        ("咖啡", "☕️"),
        ("购物", "🛒"),
        ("旅游", "✈️"),
        ("娱乐", "🎬"),
        ("医疗", "💊"),
        ("住房", "🏠"),
        ("通讯", "📱"),
        ("教育", "🎓"),
        ("运动", "🏃"),
        ("美妆", "💄"),
        ("宠物", "🐾"),
        ("人情", "🎀"),
        ("红包", "🧧"),
        ("其他", "💡"),
    ]

    static let defaultIncomeCategories: [(String, String)] = [
        ("工资", "💰"),
        ("奖金", "🎁"),
        ("红包", "🧧"),
        ("兼职", "💻"),
        ("投资", "📈"),
        ("退款", "↩️"),
        ("转账", "👥"),
        ("其他", "⭐"),
    ]

    static func seedDefaultCategories(context: ModelContext) {
        let descriptor = FetchDescriptor<Category>()
        let existingCategories = (try? context.fetch(descriptor)) ?? []
        var existingKeys = Set(existingCategories.map { "\($0.type)|\($0.name)" })

        for (i, (name, emoji)) in defaultExpenseCategories.enumerated() {
            guard !existingKeys.contains("expense|\(name)") else { continue }
            context.insert(Category(name: name, emoji: emoji, type: "expense", sortOrder: i))
            existingKeys.insert("expense|\(name)")
        }
        for (i, (name, emoji)) in defaultIncomeCategories.enumerated() {
            guard !existingKeys.contains("income|\(name)") else { continue }
            context.insert(Category(name: name, emoji: emoji, type: "income", sortOrder: i))
            existingKeys.insert("income|\(name)")
        }
        try? context.save()
    }
}
