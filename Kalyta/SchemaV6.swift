import Foundation
import SwiftData

/// The data model with currencies: an entry may record a foreign amount and the rate it was converted at.
///
/// Adding optional or defaulted attributes is lightweight. ``Expense/amount`` stays in hryvnias, so totals
/// read it unchanged. Categories and subscriptions are unchanged; the category model is repeated only
/// because its relationship points at this `Expense`.
enum SchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }
    static var models: [any PersistentModel.Type] { [Expense.self, ExpenseCategory.self, SchemaV3.Subscription.self] }

    /// A single entry: an expense, or income when ``isIncome`` is set.
    ///
    /// Kept under the name `Expense`: SwiftData has no documented way to rename an entity,
    /// and the name only matters to the code.
    @Model
    final class Expense {
        /// The amount spent, in hryvnias.
        var amount: Double
        /// The category from before custom categories existed; kept until every store
        /// has been relinked, then dropped in a later schema version.
        @Attribute(originalName: "category") var legacyCategory: Category
        /// The category the expense belongs to; `nil` only until the launch relink runs.
        ///
        /// Not named `category`: SQLite would give it the same `ZCATEGORY` column that
        /// `legacyCategory` already occupies, and the migration fails with "duplicate
        /// column name". Once `legacyCategory` is dropped, a later version can rename
        /// this with `originalName`.
        var assignedCategory: ExpenseCategory?
        /// An optional free-form description, such as the shop name.
        var note: String
        /// The moment the expense happened.
        var date: Date
        /// Whether this entry is money received rather than spent. Totals of spending skip it.
        var isIncome: Bool = false
        /// The bank's transaction id when a bank sync recorded or matched this entry, else `nil`.
        ///
        /// Lets a later sync update a pending payment instead of adding it twice. Not exported to CSV.
        var bankID: String?
        /// The amount in ``currencyCode`` as the person entered it, or `nil` for a hryvnia entry.
        var originalAmount: Double?
        /// The ISO 4217 code of ``originalAmount``; `nil` means hryvnias.
        var currencyCode: String?
        /// The hryvnias per one unit of ``currencyCode`` that ``amount`` was converted at.
        ///
        /// Stored because the rounded hryvnias do not give it back: 3 × 44.9729 is 134.92, which reads as 44.9733.
        var rate: Double?
        /// Whether ``rate`` was a stand-in (offline) and the NBU rate for ``date`` should replace it.
        var isRateEstimated: Bool = false

        /// Creates an expense in a category, defaulting to the current moment.
        ///
        /// - Parameters:
        ///   - amount: The amount in hryvnias.
        ///   - category: The category record.
        ///   - note: An optional description.
        ///   - date: When the expense happened.
        ///   - isIncome: Whether the entry is income.
        ///   - bankID: The bank's transaction id, for entries a bank sync records.
        init(
            amount: Double, category: ExpenseCategory, note: String = "", date: Date = .now, isIncome: Bool = false,
            bankID: String? = nil
        ) {
            self.amount = amount
            self.legacyCategory = Category(rawValue: category.key) ?? .other
            self.assignedCategory = category
            self.note = note
            self.date = date
            self.isIncome = isIncome
            self.bankID = bankID
        }
    }

    /// A category of expenses: one of the built-ins or one the person created.
    @Model
    final class ExpenseCategory {
        /// The stable identifier: "food" and so on for built-ins, a UUID for custom ones.
        /// It never changes after creation, so the CSV `category` column stays stable.
        @Attribute(.unique) var key: String
        /// The name the person gave, or `nil` to use the built-in's localized name.
        var customName: String?
        /// The SF Symbol name of the icon.
        var symbol: String
        /// The palette entry of the colour; see ``CategoryColor``.
        var colorName: String
        /// Whether the category is hidden from the entry sheet; its history stays.
        var isHidden: Bool
        /// The position in lists; built-ins come first in their original order.
        var sortOrder: Int
        /// Whether the category is for income; income categories never appear among spending.
        var isIncome: Bool = false
        @Relationship(deleteRule: .nullify, inverse: \Expense.assignedCategory) var expenses: [Expense] = []

        /// Creates a category record.
        ///
        /// - Parameters:
        ///   - key: The stable identifier.
        ///   - customName: The person's name for it, or `nil` for a built-in's own name.
        ///   - symbol: The SF Symbol name.
        ///   - colorName: A ``CategoryColor`` raw value.
        ///   - sortOrder: The position in lists.
        ///   - isIncome: Whether the category is for income.
        init(
            key: String, customName: String?, symbol: String, colorName: String, sortOrder: Int, isIncome: Bool = false
        ) {
            self.key = key
            self.customName = customName
            self.symbol = symbol
            self.colorName = colorName
            self.isHidden = false
            self.sortOrder = sortOrder
            self.isIncome = isIncome
        }
    }
}
