import Foundation
import SwiftData

/// Verifies which category automatic entries go into, and the Shortcuts action around it.
///
/// Covers the merchant memory on a temporary store, then runs the action and the query
/// themselves against the shared store, which must hold the Food probe with the note
/// "selfcheck" that ``runSelfCheck()`` inserts.
@MainActor
func runQuickAddCheck() {
    let url = FileManager.default.temporaryDirectory.appending(path: "selfcheck-quickadd-\(UUID().uuidString).store")
    defer { removeStore(at: url) }
    let context = ModelContext(try! Store.makeContainer(url: url))
    try! Store.ensureCategories(in: context)
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    /// Inserts an entry `days` after a fixed moment, in the built-in category with `key`.
    func record(_ note: String, _ key: String, days: Double, isIncome: Bool = false) {
        let category = Store.category(withKey: key, in: context)!
        context.insert(
            Expense(
                amount: 10, category: category, note: note, date: start + days * 86_400, isIncome: isIncome))
    }
    record("Сільпо", "food", days: 0)
    // The newest is inserted between older ones, so taking the first or last fetched row fails.
    record("АТБ", "home", days: 1)
    record("атб", "fun", days: 5)
    record("АТБ", "health", days: 0)
    // The income row is the newest with this note, so a memory that reads income picks it.
    record("Нова пошта", "transport", days: 2)
    record("Нова пошта", "income", days: 6, isIncome: true)
    // A spending row without a note, so an empty note must not match it.
    record("", "food", days: 7)
    try! context.save()
    func category(_ note: String) -> String { Store.category(forMerchant: note, in: context).key }

    assert(category("Сільпо") == "food", "A known merchant did not bring back its category")
    assert(category("  сІЛЬПО ") == "food", "The merchant memory is case or whitespace sensitive")
    assert(category("АТБ") == "fun", "The newest entry with the note did not win: \(category("АТБ"))")
    assert(category("Нова пошта") == "transport", "The merchant memory used an income entry")
    assert(category("") == "other" && category("   ") == "other", "An empty note did not fall back to Other")
    assert(category("Нова кав'ярня") == "other", "An unknown merchant did not fall back to Other")
    let resolved = try! CategoryQuery.spendingCategories(withKeys: ["food", "income"], in: context).map(\.key)
    assert(resolved == ["food"], "Shortcuts could resolve an income category: \(resolved)")

    // The wiring, on the shared store: the action itself must use the memory, keep an explicit
    // category, refuse an amount above the maximum, and cut a long note.
    let shared = Store.container.mainContext
    /// Runs the action and returns the category key of the entry it added, or `nil` if it refused.
    func quickAdd(amount: Double, note: String, categoryKey: String? = nil) -> String? {
        let intent = QuickAddExpense()
        intent.amount = amount
        intent.note = note
        intent.category = categoryKey.map { CategoryEntity(Store.category(withKey: $0, in: shared)!) }
        let succeeded = wait { (try? await intent.perform()) != nil }
        let stored = String(note.prefix(maximumNoteLength))
        let added = try! shared.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.note == stored }))
        deleteExpenses(where: #Predicate { $0.note == stored }, in: shared)
        return succeeded && added.count == 1 ? added[0].assignedCategory?.key : nil
    }
    assert(quickAdd(amount: 1, note: " SELFCHECK") == "food", "The Shortcuts action does not use the merchant memory")
    assert(
        quickAdd(amount: 1, note: " SELFCHECK", categoryKey: "health") == "health",
        "A category set in the Shortcuts action did not win")
    assert(quickAdd(amount: maximumAmount + 1, note: " SELFCHECK") == nil, "The action accepted a huge amount")
    assert(
        quickAdd(amount: 1, note: String(repeating: "й", count: maximumNoteLength + 500)) == "other",
        "The action did not cut a long note")
    let offered = wait { try! await CategoryQuery().entities(for: ["food", "income"]) }.map(\.id)
    assert(offered == ["food"], "The Shortcuts query resolves income categories: \(offered)")
}

/// Runs main-actor async work to completion from the synchronous self-check.
///
/// Shared by the checks that drive async code: the Shortcuts action and the bank sync.
///
/// - Parameter work: The work to run.
/// - Returns: What the work returned.
@MainActor
func wait<T>(_ work: @escaping @MainActor () async -> T) -> T {
    let box = ResultBox<T>()
    Task { box.value = await work() }
    // The task runs on the main actor, so the main run loop has to turn for it to finish.
    while box.value == nil { RunLoop.main.run(until: .now + 0.01) }
    return box.value!
}

/// Holds the result of the work ``wait(_:)`` runs.
private final class ResultBox<T> {
    var value: T?
}
