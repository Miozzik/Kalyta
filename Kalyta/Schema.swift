import Foundation
import SwiftData

/// The data model exactly as the first release stored it, before custom categories.
///
/// The store written by that release carries no version, so SwiftData recognises it
/// only by its shape: this schema must not change, or existing stores stop opening.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Expense.self] }

    /// An expense whose category was a fixed enum value.
    @Model
    final class Expense {
        var amount: Double
        var category: Category
        var note: String
        var date: Date

        /// Creates an expense in the first release's shape; used only to test migration.
        init(amount: Double, category: Category, note: String, date: Date) {
            self.amount = amount
            self.category = category
            self.note = note
            self.date = date
        }
    }
}

/// The data model with categories stored as their own records.
///
/// The move from V1 is lightweight: the enum stays as `legacyCategory` (a rename) and
/// the new relationship is optional. ``Store/ensureCategories(in:)`` then links every
/// expense to its category record at launch.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Expense.self, ExpenseCategory.self] }

    /// A single recorded expense.
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

        /// Creates an expense in a category, defaulting to the current moment.
        ///
        /// - Parameters:
        ///   - amount: The amount in hryvnias.
        ///   - category: The category record.
        ///   - note: An optional description.
        ///   - date: When the expense happened.
        init(amount: Double, category: ExpenseCategory, note: String = "", date: Date = .now) {
            self.amount = amount
            self.legacyCategory = Category(rawValue: category.key) ?? .other
            self.assignedCategory = category
            self.note = note
            self.date = date
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
        @Relationship(deleteRule: .nullify, inverse: \Expense.assignedCategory) var expenses: [Expense] = []

        /// Creates a category record.
        ///
        /// - Parameters:
        ///   - key: The stable identifier.
        ///   - customName: The person's name for it, or `nil` for a built-in's own name.
        ///   - symbol: The SF Symbol name.
        ///   - colorName: A ``CategoryColor`` raw value.
        ///   - sortOrder: The position in lists.
        init(key: String, customName: String?, symbol: String, colorName: String, sortOrder: Int) {
            self.key = key
            self.customName = customName
            self.symbol = symbol
            self.colorName = colorName
            self.isHidden = false
            self.sortOrder = sortOrder
        }
    }
}

/// The data model with subscriptions added; expenses and categories are unchanged from V2.
///
/// Adding a model is a lightweight migration. The V2 model types are reused as they are.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [SchemaV2.Expense.self, SchemaV2.ExpenseCategory.self, Subscription.self]
    }

    /// A recurring payment the person wants to keep track of and be reminded about.
    @Model
    final class Subscription {
        /// A stable identifier, also used for the reminder notification.
        @Attribute(.unique) var key: String
        var name: String
        /// The amount of one charge, in hryvnias.
        var amount: Double
        var period: BillingPeriod
        /// The first charge; every later charge is computed from it, never from the previous one.
        var firstChargeDate: Date
        /// The key of the category a recorded charge goes into.
        var categoryKey: String
        /// The ``CategoryColor`` name of the letter avatar, chosen once at creation.
        var colorName: String
        /// The downloaded service icon, stored so it is fetched (and disclosed) only once.
        @Attribute(.externalStorage) var iconData: Data?
        /// The icon slug last looked up, so a missing icon is not requested on every launch.
        var iconSlugTried: String?

        /// Creates a subscription.
        ///
        /// - Parameters:
        ///   - name: The service name, such as "Netflix".
        ///   - amount: The amount of one charge.
        ///   - period: How often it is charged.
        ///   - firstChargeDate: The first charge.
        ///   - categoryKey: The category recorded charges go into.
        init(name: String, amount: Double, period: BillingPeriod, firstChargeDate: Date, categoryKey: String) {
            self.key = UUID().uuidString
            self.name = name
            self.amount = amount
            self.period = period
            self.firstChargeDate = firstChargeDate
            self.categoryKey = categoryKey
            self.colorName = SubscriptionMath.avatarColor(for: name).rawValue
        }
    }
}

/// The data model with income: entries and categories gain an `isIncome` flag.
///
/// Adding a Boolean with a default is lightweight. Subscriptions are unchanged from V3.
enum SchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
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

        /// Creates an expense in a category, defaulting to the current moment.
        ///
        /// - Parameters:
        ///   - amount: The amount in hryvnias.
        ///   - category: The category record.
        ///   - note: An optional description.
        ///   - date: When the expense happened.
        ///   - isIncome: Whether the entry is income.
        init(amount: Double, category: ExpenseCategory, note: String = "", date: Date = .now, isIncome: Bool = false) {
            self.amount = amount
            self.legacyCategory = Category(rawValue: category.key) ?? .other
            self.assignedCategory = category
            self.note = note
            self.date = date
            self.isIncome = isIncome
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

/// The data model with bank sync: entries gain an optional `bankID`.
///
/// Adding an optional attribute is lightweight. Categories and subscriptions are unchanged;
/// the category model is repeated only because its relationship points at this `Expense`.
enum SchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
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

typealias Expense = SchemaV5.Expense
typealias ExpenseCategory = SchemaV5.ExpenseCategory
typealias Subscription = SchemaV3.Subscription

/// How stores move between schema versions.
enum KalytaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            .lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self),
        ]
    }
}
