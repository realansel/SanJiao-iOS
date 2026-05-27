import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID
    var name: String
    var categoryName: String
    var categoryEmoji: String
    /// Negative = expense, positive = income
    var amount: Double
    var date: Date
    var note: String
    var isRefunded: Bool
    var createdAt: Date
    /// Seconds from sheet open to confirm tap. nil = legacy record (duration not measured).
    var recordDuration: Double?

    init(
        name: String,
        categoryName: String,
        categoryEmoji: String,
        amount: Double,
        date: Date = Date(),
        note: String = "",
        isRefunded: Bool = false,
        recordDuration: Double? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.categoryName = categoryName
        self.categoryEmoji = categoryEmoji
        self.amount = amount
        self.date = date
        self.note = note
        self.isRefunded = isRefunded
        self.createdAt = Date()
        self.recordDuration = recordDuration
    }

    var isExpense: Bool { amount < 0 }
    var isIncome: Bool { amount > 0 }
    var absoluteAmount: Double { abs(amount) }

    var displayAmount: String {
        let sign = amount >= 0 ? "+" : "-"
        return "\(sign)¥\(String(format: "%.2f", abs(amount)))"
    }

    /// 用户没填备注时，name 会被设成 categoryName（中文 key）作为占位。
    /// 显示时把这种占位翻译成当前语言；用户自填的备注原样返回。
    var displayName: String {
        name == categoryName ? name.localizedCategoryName : name
    }
}
