import Foundation
import SwiftData

/// Verifies where the store lives and that entries left in the App Group's store come back once.
@MainActor
func runStoreCheck() {
    // The store stays in the app's own container, where every release before stage 14 kept it.
    let storeURL = Store.container.configurations.first?.url
    assert(
        storeURL?.path.hasPrefix(URL.applicationSupportDirectory.path) == true,
        "The store left the app's container: \(storeURL as Any)")

    let temporary = FileManager.default.temporaryDirectory
    let targetURL = temporary.appending(path: "selfcheck-merge-target-\(UUID().uuidString).store")
    let sourceURL = temporary.appending(path: "selfcheck-merge-source-\(UUID().uuidString).store")
    defer {
        removeStore(at: targetURL)
        removeStore(at: sourceURL)
    }
    let day = Date(timeIntervalSince1970: 1_790_000_000)
    /// Opens a temporary store with the built-ins and one custom category "c1" named `cafeName`.
    func store(_ url: URL, cafeName: String) -> ModelContext {
        let context = ModelContext(try! Store.makeContainer(url: url))
        try! Store.ensureCategories(in: context)
        context.insert(
            ExpenseCategory(
                key: "c1", customName: cafeName, symbol: "cup.and.saucer.fill", colorName: "brown", sortOrder: 20))
        return context
    }
    func add(_ note: String, _ amount: Double, key: String = "food", bankID: String? = nil, in context: ModelContext) {
        let category = Store.category(withKey: key, in: context)!
        context.insert(Expense(amount: amount, category: category, note: note, date: day, bankID: bankID))
    }
    func subscription(_ key: String, in context: ModelContext) {
        let item = Subscription(name: key, amount: 99, period: .monthly, firstChargeDate: day, categoryKey: "fun")
        item.key = key
        context.insert(item)
    }

    // The app's store: the person's history.
    let target = store(targetURL, cafeName: "Кафе")
    add("A", 10, in: target)
    add("bank", 5, bankID: "b1", in: target)
    subscription("S1", in: target)
    try! target.save()
    // The App Group's store: one entry alike, one with a known bank id, new ones, a new category.
    // Built in its own scope, so it is closed before the merge renames its files, as in the app.
    do {
        let source = store(sourceURL, cafeName: "Other name")
        source.insert(
            ExpenseCategory(key: "c2", customName: "Нова", symbol: "gift.fill", colorName: "pink", sortOrder: 21))
        try! source.save()
        add("A", 10, in: source)
        add("bank, settled", 4.5, bankID: "b1", in: source)
        add("B", 20, in: source)
        add("C", 30, key: "c2", in: source)
        subscription("S1", in: source)
        subscription("S2", in: source)
        try! source.save()
    }

    let first = try! StoreMerge.merge(from: sourceURL, into: target)
    assert(first == StoreMerge.Result(expenses: 2, categories: 1, subscriptions: 1), "Merge copied \(first)")
    let notes = Set(try! target.fetch(FetchDescriptor<Expense>()).map(\.note))
    assert(notes == ["A", "bank", "B", "C"], "Merged entries are wrong: \(notes)")
    let copied = try! target.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.note == "C" })).first
    assert(copied?.assignedCategory?.key == "c2", "A merged entry lost its category")
    assert(Store.category(withKey: "c1", in: target)?.customName == "Кафе", "The merge renamed a local category")
    let second = try! StoreMerge.merge(from: sourceURL, into: target)
    assert(second == StoreMerge.Result(), "A second merge copied \(second)")

    // The merged store is renamed, never deleted, and stays openable with what its journal holds.
    let stamp = Date(timeIntervalSince1970: 1_790_000_000)
    let archived = try! StoreMerge.archive(sourceURL, now: stamp)
    defer { removeStore(at: archived) }
    assert(!FileManager.default.fileExists(atPath: sourceURL.path), "The merged store is still in place")
    assert(
        FileManager.default.fileExists(atPath: StoreMerge.supportFolder(of: archived).path),
        "The archived store lost its folder of externally stored data")
    assert(
        archived.lastPathComponent.hasSuffix(".merged-20260921T141320Z.store"),
        "Archived as \(archived.lastPathComponent)")
    let reopened = ModelContext(try! Store.makeContainer(url: archived))
    assert(try! reopened.fetchCount(FetchDescriptor<Expense>()) == 4, "The archived store lost entries")
}

/// Deletes a temporary store with its SQLite journals and external-data folder, which removing
/// the database file alone leaves behind.
///
/// - Parameter url: The store's database file.
func removeStore(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
    try? FileManager.default.removeItem(at: StoreMerge.supportFolder(of: url))
}
