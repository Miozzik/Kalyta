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
    static var title: LocalizedStringResource = "Додати витрату"
    static var description = IntentDescription("Записує витрату в Kalyta без відкриття застосунку.")
    static var openAppWhenRun = false

    @Parameter(title: "Сума", requestValueDialog: "Скільки?")
    var amount: Double

    @Parameter(title: "Категорія")
    var category: Category?

    @Parameter(title: "Нотатка")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            throw $amount.needsValueError("Сума має бути більшою за нуль")
        }
        let context = Store.container.mainContext
        context.insert(Expense(amount: amount, category: category ?? .other, note: note ?? ""))
        try context.save()
        return .result(dialog: "Записав \(formattedHryvnias(amount))")
    }
}
