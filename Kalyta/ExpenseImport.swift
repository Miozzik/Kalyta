import Foundation
import SwiftData
import UIKit

/// Reads CSV text into rows of fields, following RFC 4180.
enum CSVParser {
    /// One record of a CSV file with the line it starts on.
    struct Row: Equatable {
        /// The 1-based line of the file where the record starts; records can span lines.
        let line: Int
        let fields: [String]
    }

    /// Splits CSV text into records and fields.
    ///
    /// Walks Unicode scalars rather than `Character`s: in Swift "\r\n" is a single
    /// `Character`, so a check for "\n" would never see it. CRLF, LF and CR all end a
    /// record outside quotes; inside quotes every character is kept as written, and a
    /// doubled quote stands for one quote. A leading byte-order mark is dropped.
    ///
    /// - Parameter text: The whole file.
    /// - Returns: The records in order; a trailing empty line yields no record.
    /// - Complexity: O(*n*), where *n* is the length of `text`.
    static func rows(in text: String) -> [Row] {
        var scalars = Substring(text).unicodeScalars[...]
        if scalars.first == "\u{FEFF}" { scalars = scalars.dropFirst() }

        var rows: [Row] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var isQuoted = false
        var line = 1
        var rowStart = 1
        var iterator = scalars.makeIterator()
        var pending = iterator.next()

        func endField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
        }
        func endRow() {
            endField()
            if !(fields.count == 1 && fields[0].isEmpty) { rows.append(Row(line: rowStart, fields: fields)) }
            fields = []
        }

        while let scalar = pending {
            pending = iterator.next()
            if isQuoted {
                if scalar == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        isQuoted = false
                    }
                } else {
                    if scalar == "\n" || (scalar == "\r" && pending != "\n") { line += 1 }
                    field.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"" where field.isEmpty:
                isQuoted = true
            case ",":
                endField()
            case "\r", "\n":
                if scalar == "\r", pending == "\n" { pending = iterator.next() }
                endRow()
                line += 1
                rowStart = line
            default:
                field.append(scalar)
            }
        }
        if !field.isEmpty || !fields.isEmpty { endRow() }
        return rows
    }
}

/// What an import will do, worked out before anything is written.
///
/// The preview shows these numbers and the insert executes exactly this plan, so the
/// two cannot disagree.
struct ImportPlan: Sendable {
    /// The expenses that are new and will be added.
    let toInsert: [ExpenseRecord]
    /// How many rows are already in the store (or repeated in the file) and are skipped.
    let duplicateCount: Int
    /// The lines of rows that could not be read.
    let invalidLines: [Int]
}

/// Why a file cannot be imported at all.
enum ImportError: LocalizedError, Equatable {
    /// The file was opened and saved again in a spreadsheet, which rewrote its format.
    case resavedBySpreadsheet
    /// The file is not a Kalyta export.
    case notKalytaExport
    /// A row is in a currency other than the hryvnia.
    case unsupportedCurrency(line: Int)
    /// The file is larger than an import accepts.
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .resavedBySpreadsheet:
            String(localized: "This file was re-saved by Excel. Import the original Kalyta export.")
        case .notKalytaExport:
            String(localized: "This is not a Kalyta export.")
        case .unsupportedCurrency(let line):
            String(localized: "Line \(line) is not in hryvnias. Kalyta only imports hryvnia amounts.")
        case .tooLarge:
            String(localized: "The file is too large to import.")
        }
    }
}

/// Plans and applies imports of Kalyta's own CSV export.
enum ExpenseImport {
    /// The largest file an import reads, so a wrong pick cannot exhaust memory.
    ///
    /// About 100 bytes per row, so this allows roughly 100,000 expenses: decades of use.
    static let maximumFileSize = 10_000_000
    /// The earliest date a row may have; anything older is a broken or crafted file.
    static let earliestDate = Date(timeIntervalSince1970: 946_684_800)  // 2000-01-01T00:00:00Z
    /// The longest category key a row may have; built-in keys and UUIDs are far shorter.
    static let maximumKeyLength = 64
    /// The longest category name a row may have.
    static let maximumNameLength = 100

    /// Reads a picked file as UTF-8 text, never more than `limit` bytes.
    ///
    /// Reads through a `FileHandle` instead of trusting the file size, which a file
    /// provider may not report.
    ///
    /// - Parameters:
    ///   - url: The file to read.
    ///   - limit: The most bytes accepted.
    /// - Returns: The file's text.
    /// - Throws: ``ImportError/tooLarge`` past the limit, ``ImportError/notKalytaExport`` if the
    ///   bytes are not UTF-8, or the error of opening or reading the file.
    static func readText(from url: URL, limit: Int = maximumFileSize) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ImportError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw ImportError.notKalytaExport }
        return text
    }

    /// Identifies an expense regardless of precision lost in the export.
    ///
    /// The export writes whole seconds and at most two decimals, while the store keeps
    /// fractions of a second; comparing raw values would duplicate every re-imported row.
    struct DuplicateKey: Hashable {
        let second: Int
        let kopiykas: Int
        let categoryKey: String
        let note: String
        /// Part of the key, so an income and an expense alike in every other way stay apart.
        let isIncome: Bool

        /// Creates the key of a record.
        ///
        /// - Parameter record: The expense to identify.
        init(_ record: ExpenseRecord) {
            second = Int(record.date.timeIntervalSince1970.rounded(.down))
            kopiykas = Int((record.amount * 100).rounded())
            categoryKey = record.categoryKey
            note = record.note
            isIncome = record.isIncome
        }
    }

    /// Reads a CSV export and works out which rows are new.
    ///
    /// A row is refused when its date is outside ``earliestDate`` … `now` + 1 day, a text field
    /// is over its limit, or its kind contradicts the category with the same key.
    ///
    /// - Parameters:
    ///   - text: The whole file.
    ///   - existing: The expenses already stored.
    ///   - categoryKinds: Whether each stored custom category is for income, by key; the
    ///     built-ins are known without it.
    ///   - now: The current time, for the date bound.
    /// - Returns: The rows to add, the number of duplicates, and the lines that could not be read.
    /// - Throws: ``ImportError`` if the file is not a Kalyta export at all.
    /// - Complexity: O(*n* + *m*), where *n* is the file length and *m* the number of existing expenses.
    static func plan(
        csv text: String, existing: [ExpenseRecord], categoryKinds: [String: Bool] = [:], now: Date = .now
    ) throws -> ImportPlan {
        let rows = CSVParser.rows(in: text)
        guard let header = rows.first else { throw ImportError.notKalytaExport }
        // A spreadsheet in a European region saves with ";" and rewrites dates; say so plainly.
        if header.fields.count == 1, header.fields[0].contains(";") { throw ImportError.resavedBySpreadsheet }
        guard Array(header.fields.prefix(ExpenseCSV.requiredColumns.count)) == ExpenseCSV.requiredColumns else {
            throw ImportError.notKalytaExport
        }
        // Extra columns are allowed, so a name can repeat; the first one, the contract column, wins.
        let index = Dictionary(header.fields.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        var seen = Set(existing.map(DuplicateKey.init))
        // A category is either for income or for spending; the first row naming a new key decides.
        var kinds = Dictionary(uniqueKeysWithValues: Category.allCases.map { ($0.rawValue, $0 == .income) })
            .merging(categoryKinds) { builtIn, _ in builtIn }
        let dates = earliestDate...now.addingTimeInterval(86_400)
        var toInsert: [ExpenseRecord] = []
        var duplicateCount = 0
        var invalidLines: [Int] = []
        var sawSpreadsheetDate = false

        for row in rows.dropFirst() {
            func value(_ column: String) -> String? {
                index[column].flatMap { $0 < row.fields.count ? row.fields[$0] : nil }
            }
            guard let currency = value("currency"), currency == hryvniaCurrencyCode || currency.isEmpty else {
                throw ImportError.unsupportedCurrency(line: row.line)
            }
            guard
                let dateText = value("date"), let date = try? Date(dateText, strategy: .iso8601), dates.contains(date),
                let amountText = value("amount"), let amount = Double(amountText), isValidAmount(amount),
                let key = value("category").map(ExpenseCSV.restored), !key.isEmpty, key.count <= maximumKeyLength
            else {
                if value("date").map({ $0.contains(".") && !$0.contains("T") }) == true { sawSpreadsheetDate = true }
                invalidLines.append(row.line)
                continue
            }
            // Files from before income existed have no `kind`; an empty value means spending too.
            let kind = value("kind") ?? ""
            let isIncome = kind == ExpenseCSV.incomeKind
            let name = value("category_name").map(ExpenseCSV.restored) ?? key
            let note = value("note").map(ExpenseCSV.restored) ?? ""
            guard kind.isEmpty || kind == ExpenseCSV.expenseKind || isIncome,
                kinds[key, default: isIncome] == isIncome,
                name.count <= maximumNameLength, note.count <= maximumNoteLength
            else {
                invalidLines.append(row.line)
                continue
            }
            kinds[key] = isIncome
            let record = ExpenseRecord(
                date: date, amount: amount, categoryKey: key, categoryName: name, note: note,
                categorySymbol: value("category_symbol") ?? Category.other.icon,
                categoryColorName: value("category_color") ?? CategoryColor.gray.rawValue,
                isIncome: isIncome)
            if seen.insert(DuplicateKey(record)).inserted {
                toInsert.append(record)
            } else {
                duplicateCount += 1
            }
        }
        if toInsert.isEmpty, duplicateCount == 0, sawSpreadsheetDate { throw ImportError.resavedBySpreadsheet }
        if toInsert.isEmpty, duplicateCount == 0, !invalidLines.isEmpty { throw ImportError.notKalytaExport }
        return ImportPlan(toInsert: toInsert, duplicateCount: duplicateCount, invalidLines: invalidLines)
    }

    /// Adds the planned expenses, creating any categories the backup has and the store lacks.
    ///
    /// A category that already exists keeps its local name, icon, colour and hidden state:
    /// the person may have changed them after the backup. Everything is saved at once, so
    /// a crash never leaves half an import.
    ///
    /// - Parameters:
    ///   - plan: The plan made by ``plan(csv:existing:)``.
    ///   - context: The context to insert into.
    /// - Returns: How many categories were created.
    /// - Throws: An error if fetching or saving fails.
    @discardableResult
    static func apply(_ plan: ImportPlan, in context: ModelContext) throws -> Int {
        try Store.ensureCategories(in: context)
        var byKey = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<ExpenseCategory>()).map { ($0.key, $0) })
        var nextSortOrder = (byKey.values.map(\.sortOrder).max() ?? 0) + 1
        var createdCount = 0
        for record in plan.toInsert {
            let category: ExpenseCategory
            if let existing = byKey[record.categoryKey] {
                category = existing
            } else {
                let symbol =
                    UIImage(systemName: record.categorySymbol) == nil ? CategorySymbols.all[0] : record.categorySymbol
                let color =
                    CategoryColor(rawValue: record.categoryColorName)
                    ?? CategoryColor.allCases[nextSortOrder % CategoryColor.allCases.count]
                category = ExpenseCategory(
                    key: record.categoryKey, customName: record.categoryName, symbol: symbol, colorName: color.rawValue,
                    sortOrder: nextSortOrder, isIncome: record.isIncome)
                context.insert(category)
                byKey[record.categoryKey] = category
                nextSortOrder += 1
                createdCount += 1
            }
            // Always set the link: the launch relink would otherwise move a custom-category
            // row to its legacy built-in value.
            context.insert(
                Expense(
                    amount: record.amount, category: category, note: record.note, date: record.date,
                    isIncome: record.isIncome))
        }
        try context.save()
        return createdCount
    }
}

/// Writes an import on a background context, so a large restore does not freeze the interface.
///
/// Measured in a Release build: inserting 10,000 rows takes about 1.5 s, over the one
/// second the main actor may be blocked. The main context sees the rows after the save.
@ModelActor
actor ImportWriter {
    /// Adds the planned expenses; see ``ExpenseImport/apply(_:in:)``.
    ///
    /// - Parameter plan: The plan the person confirmed in the preview.
    /// - Returns: How many categories were created.
    /// - Throws: An error if fetching or saving fails.
    @discardableResult
    func apply(_ plan: ImportPlan) throws -> Int {
        try ExpenseImport.apply(plan, in: modelContext)
    }
}
