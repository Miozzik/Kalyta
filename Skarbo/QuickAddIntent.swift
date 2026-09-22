import AppIntents
import SwiftData

/// Точка входу для Shortcuts — саме через неї працюють обидві "преміум" фічі Skarbo:
/// подвійний тап по спинці (Налаштування → Доступність → Дотик → Тап по задній панелі)
/// і автозапис оплат (Команди → Автоматизація → Транзакція).
struct QuickAddExpense: AppIntent {
    static var title: LocalizedStringResource = "Додати витрату"
    static var description = IntentDescription("Записує витрату в Skarbo без відкриття застосунку.")
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
        return .result(dialog: "Записав \(uah(amount))")
    }
}
