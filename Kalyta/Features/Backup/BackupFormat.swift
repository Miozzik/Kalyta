import CoreTransferable
import Foundation
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// A full backup: every entry, category and subscription, as written to a `.json` file.
///
/// Plain values, never the `@Model` classes, so the file holds exactly the fields listed here
/// and a schema change cannot add one by accident. It never holds the monobank token, the
/// sync state or any setting.
struct Backup: Sendable {
    /// The `format` value that marks a Kalyta backup.
    static let formatName = "kalyta-backup"
    /// The newest `version` this build reads, and the one it writes.
    static let currentVersion = 1
    /// The most entries a file may hold; more is refused whole.
    static let maximumEntries = 100_000
    /// The most categories, or subscriptions, a file may hold; more is refused whole.
    static let maximumOthers = 1_000

    var format = formatName
    var version = currentVersion
    /// When the backup was made.
    var exportedAt: Date
    var entries: [Entry]
    var categories: [CategoryItem]
    var subscriptions: [SubscriptionItem]
    /// How many items the decoder could not read (a wrong type, a missing field); never written.
    var unreadableCount = 0

    /// One entry; the category is named by its key.
    struct Entry: Codable, Hashable, Sendable {
        var date: Date
        var amount: Double
        var categoryKey: String
        var note: String
        var isIncome: Bool
        var bankID: String?
        var originalAmount: Double?
        var currencyCode: String?
        var rate: Double?
        var isRateEstimated: Bool
    }

    /// One category, built-in or custom.
    struct CategoryItem: Codable, Hashable, Sendable {
        var key: String
        var customName: String?
        var symbol: String
        var colorName: String
        var isHidden: Bool
        var sortOrder: Int
        var isIncome: Bool
    }

    /// One subscription; its icon is not kept and is looked up again after a restore.
    struct SubscriptionItem: Codable, Hashable, Sendable {
        var key: String
        var name: String
        var amount: Double
        var period: BillingPeriod
        var firstChargeDate: Date
        var categoryKey: String
        var colorName: String
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, exportedAt, entries, categories, subscriptions
    }
}

extension Backup: Codable {
    /// Reads a backup, refusing the whole file when it is not one this build can restore.
    ///
    /// A single item that cannot be decoded is counted in ``unreadableCount`` instead.
    ///
    /// - Throws: ``ImportError/notKalytaExport`` for another format, ``ImportError/newerBackup``
    ///   for a later version, ``ImportError/tooLarge`` past the item limits, or a `DecodingError`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        guard format == Self.formatName, version >= 1 else { throw ImportError.notKalytaExport }
        guard version <= Self.currentVersion else { throw ImportError.newerBackup }
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        let entries = try container.decode([Lossy<Entry>].self, forKey: .entries)
        let categories = try container.decode([Lossy<CategoryItem>].self, forKey: .categories)
        let subscriptions = try container.decode([Lossy<SubscriptionItem>].self, forKey: .subscriptions)
        guard entries.count <= Self.maximumEntries, categories.count <= Self.maximumOthers,
            subscriptions.count <= Self.maximumOthers
        else { throw ImportError.tooLarge }
        self.entries = entries.compactMap(\.value)
        self.categories = categories.compactMap(\.value)
        self.subscriptions = subscriptions.compactMap(\.value)
        unreadableCount =
            entries.count + categories.count + subscriptions.count - self.entries.count - self.categories.count
            - self.subscriptions.count
    }

    /// Copies everything a context holds; the entries in date order, the categories in list order.
    ///
    /// - Parameters:
    ///   - context: The context to read.
    ///   - now: The time stamped as ``exportedAt``.
    /// - Returns: The backup.
    /// - Throws: An error if fetching fails.
    static func snapshot(of context: ModelContext, now: Date = .now) throws -> Backup {
        Backup(
            exportedAt: now,
            entries: try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)])).map {
                Entry(
                    date: $0.date, amount: $0.amount,
                    categoryKey: $0.assignedCategory?.key ?? $0.legacyCategory.rawValue,
                    note: $0.note, isIncome: $0.isIncome, bankID: $0.bankID, originalAmount: $0.originalAmount,
                    currencyCode: $0.currencyCode, rate: $0.rate, isRateEstimated: $0.isRateEstimated)
            },
            categories: try context.fetch(FetchDescriptor<ExpenseCategory>(sortBy: [SortDescriptor(\.sortOrder)])).map {
                CategoryItem(
                    key: $0.key, customName: $0.customName, symbol: $0.symbol, colorName: $0.colorName,
                    isHidden: $0.isHidden, sortOrder: $0.sortOrder, isIncome: $0.isIncome)
            },
            subscriptions: try context.fetch(FetchDescriptor<Subscription>(sortBy: [SortDescriptor(\.firstChargeDate)]))
                .map {
                    SubscriptionItem(
                        key: $0.key, name: $0.name, amount: $0.amount, period: $0.period,
                        firstChargeDate: $0.firstChargeDate, categoryKey: $0.categoryKey, colorName: $0.colorName)
                })
    }

    /// Returns the file's bytes: compact JSON, ISO 8601 dates, amounts as plain numbers.
    ///
    /// - Throws: An error if encoding fails.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Reads a backup from the text of a picked file.
    ///
    /// - Parameter text: The file, as ``ExpenseImport/readText(from:limit:)`` returns it.
    /// - Returns: The backup; items are not validated yet (see ``BackupRestore``).
    /// - Throws: ``ImportError`` if the file is refused as a whole.
    static func decode(_ text: String) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Backup.self, from: Data(text.utf8))
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.notKalytaExport
        }
    }

    /// Returns the proposed file name, without the extension: `Kalyta-<yyyy-MM-dd>`.
    ///
    /// - Parameter date: The day to name.
    static func fileName(for date: Date) -> String {
        "Kalyta-\(date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()))"
    }
}

extension Backup: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        // Encoded only when the person saves, not when the screen is drawn.
        DataRepresentation(exportedContentType: .json) { try $0.encoded() }
    }
}

/// Decodes a value, or `nil` when that one item is malformed, so the rest of the array still reads.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// Item validation: the limits of the CSV import, so both paths accept the same values.

extension Backup.Entry {
    /// The dates an entry may have: as in the CSV import, 2000 to tomorrow.
    static func dates(now: Date) -> ClosedRange<Date> { ExpenseImport.earliestDate...now.addingTimeInterval(86_400) }

    /// Whether the entry can be stored: a valid amount and date, short texts, and a consistent currency.
    func isValid(now: Date) -> Bool {
        guard Self.dates(now: now).contains(date), isValidAmount(amount), !categoryKey.isEmpty,
            categoryKey.count <= ExpenseImport.maximumKeyLength, note.count <= maximumNoteLength,
            bankID.map({ !$0.isEmpty && $0.count <= ExpenseImport.maximumKeyLength }) ?? true
        else { return false }
        guard let currencyCode else { return originalAmount == nil && rate == nil }
        return Currency.isCurrencyCode(currencyCode) && currencyCode != hryvniaCurrencyCode
            && originalAmount.map(isValidAmount) == true && rate.map(Currency.rateBounds.contains) == true
    }

    /// The entry as the CSV import sees it, for ``ExpenseImport/DuplicateKey``.
    var record: ExpenseRecord {
        ExpenseRecord(
            date: date, amount: amount, categoryKey: categoryKey, categoryName: "", note: note, isIncome: isIncome,
            originalAmount: originalAmount, currencyCode: currencyCode, rate: rate, isRateEstimated: isRateEstimated)
    }
}

extension Backup.CategoryItem {
    /// Whether the key and name fit the CSV limits.
    var isValid: Bool {
        !key.isEmpty && key.count <= ExpenseImport.maximumKeyLength
            && (customName?.count ?? 0) <= ExpenseImport.maximumNameLength
    }

    /// Returns the item with an unknown icon or colour replaced, as the CSV import does.
    ///
    /// A built-in falls back to its own icon and colour; "Other" and "Income" are never hidden.
    func normalized() -> Self {
        var item = self
        let builtIn = Category(rawValue: key)
        if UIImage(systemName: symbol) == nil { item.symbol = builtIn?.icon ?? CategorySymbols.all[0] }
        if CategoryColor(rawValue: colorName) == nil {
            let palette = CategoryColor.allCases
            item.colorName =
                (builtIn?.defaultColor ?? palette[(sortOrder % palette.count + palette.count) % palette.count]).rawValue
        }
        if builtIn == .other || builtIn == .income { item.isHidden = false }
        return item
    }
}

extension Backup.SubscriptionItem {
    /// Whether the subscription can be stored; its first charge may lie up to a year ahead.
    func isValid(now: Date) -> Bool {
        !key.isEmpty && key.count <= ExpenseImport.maximumKeyLength && !name.isEmpty
            && name.count <= ExpenseImport.maximumNameLength && isValidAmount(amount) && !categoryKey.isEmpty
            && categoryKey.count <= ExpenseImport.maximumKeyLength
            && (ExpenseImport.earliestDate...now.addingTimeInterval(366 * 86_400)).contains(firstChargeDate)
    }

    /// Returns the item with an unknown avatar colour replaced by the one a new subscription gets.
    func normalized() -> Self {
        var item = self
        if CategoryColor(rawValue: colorName) == nil {
            item.colorName = SubscriptionMath.avatarColor(for: name).rawValue
        }
        return item
    }
}
