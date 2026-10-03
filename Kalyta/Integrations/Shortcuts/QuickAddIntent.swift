import AppIntents
import SwiftData

/// The Shortcuts action that records an expense without opening the app.
///
/// Both quick-entry features are built on this single action:
/// - Back Tap: Settings → Accessibility → Touch → Back Tap → run a shortcut
///   that calls this action.
/// - Automatic logging of card payments: Shortcuts → Automation → Transaction
///   → the same shortcut.
struct QuickAddExpense: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var description = IntentDescription("Records an expense in Kalyta without opening the app.")
    static var openAppWhenRun = false

    @Parameter(title: "Amount", requestValueDialog: "How much?")
    var amount: Double

    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            throw $amount.needsValueError("The amount must be greater than zero.")
        }
        guard isValidAmount(amount) else {
            throw $amount.needsValueError("The amount is too large.")
        }
        let note = String((note ?? "").prefix(maximumNoteLength))
        let context = Store.container.mainContext
        try Store.ensureCategories(in: context)
        // Back Tap passes neither a category nor a merchant, so ask; the Transaction
        // automation always passes the merchant and stays silent.
        var category = category
        if category == nil && note.isEmpty {
            let choices = try await CategoryQuery().suggestedEntities()
            category = try await $category.requestDisambiguation(among: choices, dialog: "Which category?")
        }
        // A category set in the action wins; without one, the merchant decides.
        let record =
            category.map { Store.category(forKey: $0.id, in: context) }
            ?? Store.category(forMerchant: note, in: context)
        context.insert(Expense(amount: amount, category: record, note: note))
        try context.save()
        return .result(dialog: "Recorded \(formattedHryvnias(amount))")
    }
}

/// A category as Shortcuts sees it.
///
/// Its identifier is the category's stable key, which for built-ins equals the value
/// the earlier enum parameter used ("food" and so on).
struct CategoryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Category" }
    static var defaultQuery = CategoryQuery()

    /// The category's stable key.
    let id: String
    /// The category's name at the time it was read.
    let title: String
    /// The SF Symbol name of the icon.
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        // The title is already localized (or typed by the person); the catalog key "%@" is not translated.
        DisplayRepresentation(title: "\(title)", image: .init(systemName: symbol))
    }

    /// Copies what Shortcuts needs from a category record.
    ///
    /// - Parameter category: The record to describe.
    init(_ category: ExpenseCategory) {
        self.id = category.key
        self.title = category.title
        self.symbol = category.icon
    }
}

/// Finds categories for Shortcuts in the app's shared store.
struct CategoryQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [CategoryEntity.ID]) async throws -> [CategoryEntity] {
        try Self.spendingCategories(withKeys: identifiers, in: Store.container.mainContext).map(CategoryEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        // The action records spending only, so income categories are not offered.
        try Self.allCategories(in: Store.container.mainContext).filter { !$0.isHidden && !$0.isIncome }
            .map(CategoryEntity.init)
    }

    /// Returns the spending categories with the given keys.
    ///
    /// Income categories are left out because the action records spending only;
    /// Shortcuts skips an identifier without a match.
    ///
    /// - Parameters:
    ///   - keys: The keys Shortcuts asks for.
    ///   - context: The context to search.
    /// - Returns: The matching spending categories, built-ins first.
    /// - Throws: An error if fetching or saving the built-ins fails.
    @MainActor
    static func spendingCategories(withKeys keys: [String], in context: ModelContext) throws -> [ExpenseCategory] {
        try allCategories(in: context).filter { keys.contains($0.key) && !$0.isIncome }
    }

    /// Returns every category, built-ins first, after making sure the built-ins exist.
    @MainActor
    private static func allCategories(in context: ModelContext) throws -> [ExpenseCategory] {
        try Store.ensureCategories(in: context)
        return try context.fetch(FetchDescriptor<ExpenseCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
    }
}
