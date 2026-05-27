import Foundation
import SwiftData

@Model
final class MerchantCategoryRule {
    var id: UUID
    var merchantKey: String
    var merchantName: String
    /// "微信", "支付宝", or "通用".
    var source: String
    /// "expense" or "income".
    var type: String
    var categoryName: String
    var categoryEmoji: String
    var useCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        merchantName: String,
        source: String,
        type: String,
        categoryName: String,
        categoryEmoji: String
    ) {
        self.id = UUID()
        self.merchantKey = MerchantCategoryRule.makeKey(merchantName)
        self.merchantName = merchantName
        self.source = source
        self.type = type
        self.categoryName = categoryName
        self.categoryEmoji = categoryEmoji
        self.useCount = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static func makeKey(_ merchantName: String) -> String {
        merchantName
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }
}
