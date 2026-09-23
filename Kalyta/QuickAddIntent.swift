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
    var category: Category?

    @Parameter(title: "Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            throw $amount.needsValueError("The amount must be greater than zero.")
        }
        let context = Store.container.mainContext
        context.insert(Expense(amount: amount, category: category ?? .other, note: note ?? ""))
        try context.save()
        return .result(dialog: "Recorded \(formattedHryvnias(amount))")
    }
}
