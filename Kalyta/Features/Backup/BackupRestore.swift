import Foundation
import SwiftData

/// What restoring a backup will do, worked out before anything is written.
///
/// The preview shows these numbers and the writer executes this plan, so the two agree.
struct BackupPlan: Sendable {
    /// The entries to add.
    var entries: [Backup.Entry] = []
    /// The categories to add; none of them exists here.
    var categories: [Backup.CategoryItem] = []
    /// The built-in categories that take the backup's name, icon, colour, order and hidden state.
    ///
    /// Only in an empty app (no entries, no subscriptions), and only where a value differs.
    var builtInUpdates: [Backup.CategoryItem] = []
    /// The subscriptions to add, with their own keys.
    var subscriptions: [Backup.SubscriptionItem] = []
    /// The entries already here (or repeated in the file), skipped.
    var knownEntries = 0
    /// The categories already here, which keep this phone's values.
    var knownCategories = 0
    /// The subscriptions already here, skipped.
    var knownSubscriptions = 0
    /// The items that could not be read or failed validation.
    var invalidCount = 0
    /// Whether the store had no entries and no subscriptions when planned.
    var isEmptyApp = false

    /// Whether confirming would change nothing.
    var isEmpty: Bool { entries.isEmpty && categories.isEmpty && builtInUpdates.isEmpty && subscriptions.isEmpty }
}

/// What the store holds, as plain values the planner can use off the main actor.
struct BackupLocal: Sendable {
    var entryKeys: Set<ExpenseImport.DuplicateKey>
    var bankIDs: Set<String>
    var categories: [String: Backup.CategoryItem]
    var subscriptionKeys: Set<String>

    /// Reads what a context holds.
    ///
    /// - Parameter context: The app's context.
    /// - Throws: An error if fetching fails.
    init(_ context: ModelContext) throws {
        let backup = try Backup.snapshot(of: context)
        entryKeys = Set(backup.entries.map { ExpenseImport.DuplicateKey($0.record) })
        bankIDs = Set(backup.entries.compactMap(\.bankID))
        categories = Dictionary(backup.categories.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        subscriptionKeys = Set(backup.subscriptions.map(\.key))
    }
}

/// Plans and writes the restore of a JSON backup.
///
/// The invariant: a restore only inserts. It never deletes, and never changes an entry or a
/// subscription that is already here, so restoring the same file twice adds nothing. The one
/// exception is ``BackupPlan/builtInUpdates``, for a fresh install.
enum BackupRestore {
    /// Works out which items of a backup are new, already here, or unreadable.
    ///
    /// A category or subscription already here by key keeps its local values. An entry is
    /// already here if an entry with its bank transaction id exists, or one alike by
    /// ``ExpenseImport/DuplicateKey`` (the rules of ``StoreMerge``). An entry whose category is
    /// neither in the file nor here is invalid.
    ///
    /// - Parameters:
    ///   - backup: The decoded file.
    ///   - local: What the store holds.
    ///   - now: The current time, for the date bounds.
    /// - Returns: The plan.
    static func plan(_ backup: Backup, local: BackupLocal, now: Date = .now) -> BackupPlan {
        var plan = BackupPlan(
            invalidCount: backup.unreadableCount, isEmptyApp: local.entryKeys.isEmpty && local.subscriptionKeys.isEmpty)

        var fileCategoryKeys = Set<String>()
        for item in backup.categories {
            guard item.isValid, fileCategoryKeys.insert(item.key).inserted else {
                plan.invalidCount += 1
                continue
            }
            let item = item.normalized()
            guard let current = local.categories[item.key] else {
                plan.categories.append(item)
                continue
            }
            // The kind of a category never changes, so it is not compared.
            var incoming = item
            incoming.isIncome = current.isIncome
            if plan.isEmptyApp, Category(rawValue: item.key) != nil, incoming != current {
                plan.builtInUpdates.append(incoming)
            } else {
                plan.knownCategories += 1
            }
        }

        let categoryKeys = fileCategoryKeys.union(local.categories.keys)
        var seen = local.entryKeys
        var bankIDs = local.bankIDs
        for entry in backup.entries {
            guard entry.isValid(now: now), categoryKeys.contains(entry.categoryKey) else {
                plan.invalidCount += 1
                continue
            }
            if let id = entry.bankID, !bankIDs.insert(id).inserted {
                plan.knownEntries += 1
            } else if !seen.insert(ExpenseImport.DuplicateKey(entry.record)).inserted {
                plan.knownEntries += 1
            } else {
                plan.entries.append(entry)
            }
        }

        var fileSubscriptionKeys = Set<String>()
        for item in backup.subscriptions {
            guard item.isValid(now: now), fileSubscriptionKeys.insert(item.key).inserted else {
                plan.invalidCount += 1
                continue
            }
            if local.subscriptionKeys.contains(item.key) {
                plan.knownSubscriptions += 1
            } else {
                plan.subscriptions.append(item.normalized())
            }
        }
        return plan
    }

    /// Writes a plan: the built-in updates, then new categories, entries and subscriptions.
    ///
    /// Everything already here is checked again, so a bank sync that ran after the preview
    /// cannot lead to a duplicate. Everything is saved at once, so a crash never leaves half a restore.
    ///
    /// - Parameters:
    ///   - plan: The plan made by ``plan(_:local:now:)``.
    ///   - context: The context to insert into.
    /// - Returns: How many of each were added.
    /// - Throws: An error if fetching or saving fails.
    @discardableResult
    static func apply(_ plan: BackupPlan, in context: ModelContext) throws -> StoreMerge.Result {
        try Store.ensureCategories(in: context)
        var result = StoreMerge.Result()
        var categories = Dictionary(
            try context.fetch(FetchDescriptor<ExpenseCategory>()).map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first })
        // A bank sync may have recorded entries since the preview; then the app is no longer empty.
        let isStillEmpty =
            try context.fetchCount(FetchDescriptor<Expense>()) == 0
            && context.fetchCount(FetchDescriptor<Subscription>()) == 0
        for item in plan.builtInUpdates where isStillEmpty {
            guard let category = categories[item.key] else { continue }
            category.customName = item.customName
            category.symbol = item.symbol
            category.colorName = item.colorName
            category.isHidden = item.isHidden
            category.sortOrder = item.sortOrder
        }
        // In an empty app the backup's order is the whole order; otherwise new ones go last.
        var nextSortOrder = (categories.values.map(\.sortOrder).max() ?? 0) + 1
        for item in plan.categories where categories[item.key] == nil {
            let category = ExpenseCategory(
                key: item.key, customName: item.customName, symbol: item.symbol, colorName: item.colorName,
                sortOrder: plan.isEmptyApp ? item.sortOrder : nextSortOrder, isIncome: item.isIncome)
            category.isHidden = item.isHidden
            context.insert(category)
            categories[item.key] = category
            nextSortOrder += 1
            result.categories += 1
        }

        let existing = try context.fetch(FetchDescriptor<Expense>())
        var seen = Set(existing.map { ExpenseImport.DuplicateKey(ExpenseRecord($0)) })
        var bankIDs = Set(existing.compactMap(\.bankID))
        for entry in plan.entries {
            guard let category = categories[entry.categoryKey] else { continue }
            if let id = entry.bankID, !bankIDs.insert(id).inserted { continue }
            guard seen.insert(ExpenseImport.DuplicateKey(entry.record)).inserted else { continue }
            let expense = Expense(
                amount: entry.amount, category: category, note: entry.note, date: entry.date, isIncome: entry.isIncome,
                bankID: entry.bankID)
            expense.originalAmount = entry.originalAmount
            expense.currencyCode = entry.currencyCode
            expense.rate = entry.rate
            expense.isRateEstimated = entry.isRateEstimated
            context.insert(expense)
            result.expenses += 1
        }

        var subscriptionKeys = Set(try context.fetch(FetchDescriptor<Subscription>()).map(\.key))
        for item in plan.subscriptions where subscriptionKeys.insert(item.key).inserted {
            let subscription = Subscription(
                name: item.name, amount: item.amount, period: item.period, firstChargeDate: item.firstChargeDate,
                categoryKey: item.categoryKey)
            subscription.key = item.key
            subscription.colorName = item.colorName
            context.insert(subscription)
            result.subscriptions += 1
        }
        try context.save()
        return result
    }
}

/// Writes a restore on a background context, like ``ImportWriter`` for the CSV import.
@ModelActor
actor BackupWriter {
    /// Writes a plan; see ``BackupRestore/apply(_:in:)``.
    ///
    /// - Parameter plan: The plan the person confirmed in the preview.
    /// - Returns: How many of each were added.
    /// - Throws: An error if fetching or saving fails.
    func apply(_ plan: BackupPlan) throws -> StoreMerge.Result {
        try BackupRestore.apply(plan, in: modelContext)
    }
}
