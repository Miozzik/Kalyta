import Foundation
import SwiftData

/// Brings back into the app's store the entries that builds from stage 14 wrote to the App Group.
///
/// `ModelConfiguration(schema:)` defaults to `groupContainer: .automatic`, which "tells SwiftData
/// to use the app's primary group container as the root location for the persistent storage"
/// (https://developer.apple.com/documentation/swiftdata/modelconfiguration/groupcontainer-swift.struct/automatic).
/// Once stage 14 gave the app an App Group, those builds opened a new, empty store there, while
/// the person's history stayed in the app's own container. ``Store/makeContainer(url:)`` now asks
/// for `.none`; this copies whatever was recorded meanwhile, once, and keeps the old files.
enum StoreMerge {
    /// What a merge copied.
    struct Result: Equatable {
        var expenses = 0
        var categories = 0
        var subscriptions = 0
    }

    /// The store a stage 14 build created in the App Group, if it is still there.
    static var groupStoreURL: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "KalytaAppGroup") as? String,
            let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        let url = container.appending(path: "Library/Application Support/default.store")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Merges the App Group's store into `container` and renames its files, if that store exists.
    ///
    /// A failure leaves the files where they are, so the next launch tries again; the merge
    /// skips everything it already copied, so trying again adds nothing twice.
    ///
    /// - Parameters:
    ///   - container: The app's container.
    ///   - now: The time stamped on the renamed files.
    static func mergeGroupStoreIfPresent(into container: ModelContainer, now: Date = .now) {
        guard let url = groupStoreURL else { return }
        do {
            try merge(from: url, into: ModelContext(container))
            try archive(url, now: now)
        } catch {
            // Nothing to show the person; the untouched files are retried at the next launch.
        }
    }

    /// Copies the entries, categories and subscriptions of the store at `url` that `target` lacks.
    ///
    /// A category or subscription already present by key keeps its local values. An entry is
    /// skipped if an entry with its bank transaction id exists, or one alike by
    /// ``ExpenseImport/DuplicateKey`` (the rule the CSV import uses).
    ///
    /// - Parameters:
    ///   - url: The store to copy from; it is opened read-only.
    ///   - target: The app's context; the result is saved.
    /// - Returns: How many of each were copied.
    /// - Throws: An error if either store cannot be opened, read or saved.
    @discardableResult
    static func merge(from url: URL, into target: ModelContext) throws -> Result {
        let schema = Schema(versionedSchema: SchemaV5.self)
        let source = ModelContext(
            try ModelContainer(
                for: schema, migrationPlan: KalytaMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, url: url, allowsSave: false)))
        try Store.ensureCategories(in: target)
        var result = Result()

        var categories = Dictionary(
            try target.fetch(FetchDescriptor<ExpenseCategory>()).map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first })
        var nextSortOrder = (categories.values.map(\.sortOrder).max() ?? 0) + 1
        let sourceCategories = try source.fetch(FetchDescriptor<ExpenseCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
        for category in sourceCategories where categories[category.key] == nil {
            let copy = ExpenseCategory(
                key: category.key, customName: category.customName, symbol: category.symbol,
                colorName: category.colorName, sortOrder: nextSortOrder, isIncome: category.isIncome)
            copy.isHidden = category.isHidden
            target.insert(copy)
            categories[category.key] = copy
            nextSortOrder += 1
            result.categories += 1
        }

        let existing = try target.fetch(FetchDescriptor<Expense>())
        var seen = Set(existing.map { ExpenseImport.DuplicateKey(ExpenseRecord($0)) })
        var bankIDs = Set(existing.compactMap(\.bankID))
        for expense in try source.fetch(FetchDescriptor<Expense>()) {
            if let id = expense.bankID, bankIDs.contains(id) { continue }
            guard seen.insert(ExpenseImport.DuplicateKey(ExpenseRecord(expense))).inserted else { continue }
            let key = expense.assignedCategory?.key ?? expense.legacyCategory.rawValue
            target.insert(
                Expense(
                    amount: expense.amount, category: categories[key] ?? Store.category(forKey: nil, in: target),
                    note: expense.note, date: expense.date, isIncome: expense.isIncome, bankID: expense.bankID))
            if let id = expense.bankID { bankIDs.insert(id) }
            result.expenses += 1
        }

        var subscriptionKeys = Set(try target.fetch(FetchDescriptor<Subscription>()).map(\.key))
        for subscription in try source.fetch(FetchDescriptor<Subscription>())
        where subscriptionKeys.insert(subscription.key).inserted {
            let copy = Subscription(
                name: subscription.name, amount: subscription.amount, period: subscription.period,
                firstChargeDate: subscription.firstChargeDate, categoryKey: subscription.categoryKey)
            copy.key = subscription.key
            copy.colorName = subscription.colorName
            copy.iconData = subscription.iconData
            copy.iconSlugTried = subscription.iconSlugTried
            target.insert(copy)
            result.subscriptions += 1
        }
        try target.save()
        return result
    }

    /// Renames a store's files to `<name>.merged-<time>.store` with its `-wal` and `-shm`; nothing is deleted.
    ///
    /// The journals keep their pairing with the database (SQLite finds `X-wal` next to `X`), and
    /// the hidden `.<name>_SUPPORT` folder of externally stored data (subscription icons) is
    /// renamed to match, so the archived store still opens with everything it held.
    ///
    /// - Parameters:
    ///   - url: The store's database file.
    ///   - now: The time in the new name.
    /// - Returns: The archived database file.
    /// - Throws: An error if a file cannot be renamed.
    @discardableResult
    static func archive(_ url: URL, now: Date) throws -> URL {
        let stamp = now.formatted(
            Date.ISO8601FormatStyle(dateSeparator: .omitted, dateTimeSeparator: .standard, timeSeparator: .omitted))
        let archived = url.deletingPathExtension().appendingPathExtension("merged-\(stamp).\(url.pathExtension)")
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
            try FileManager.default.moveItem(atPath: url.path + suffix, toPath: archived.path + suffix)
        }
        let support = supportFolder(of: url)
        if FileManager.default.fileExists(atPath: support.path) {
            try FileManager.default.moveItem(at: support, to: supportFolder(of: archived))
        }
        return archived
    }

    /// Returns the hidden folder where SwiftData keeps a store's externally stored data.
    ///
    /// - Parameter store: The store's database file.
    /// - Returns: `.<name>_SUPPORT` next to it.
    static func supportFolder(of store: URL) -> URL {
        store.deletingLastPathComponent().appending(path: ".\(store.deletingPathExtension().lastPathComponent)_SUPPORT")
    }
}
