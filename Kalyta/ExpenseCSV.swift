import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// One expense as plain values, safe to hand to the share sheet.
///
/// A `@Model` object is not `Sendable`, so the export copies the values it needs.
struct ExpenseRecord: Sendable, Equatable {
    /// The moment the expense happened.
    let date: Date
    /// The amount in hryvnias.
    let amount: Double
    /// The stable category key, such as "food"; it does not change with the language.
    let categoryKey: String
    /// The category name in the app's language, such as "Їжа".
    let categoryName: String
    /// The free-form description, exported unchanged.
    let note: String
    /// The SF Symbol name of the category icon.
    var categorySymbol: String = Category.other.icon
    /// The ``CategoryColor`` name of the category, not an RGB value, so it keeps adapting to dark mode.
    var categoryColorName: String = CategoryColor.gray.rawValue
    /// Whether the entry is income rather than spending.
    var isIncome: Bool = false
}

extension ExpenseRecord {
    /// Copies the values of a stored expense.
    ///
    /// - Parameter expense: The expense to copy.
    init(_ expense: Expense) {
        self.init(
            date: expense.date,
            amount: expense.amount,
            categoryKey: expense.assignedCategory?.key ?? expense.legacyCategory.rawValue,
            categoryName: expense.categoryTitle,
            note: expense.note,
            categorySymbol: expense.categoryIcon,
            categoryColorName: expense.assignedCategory?.colorName ?? expense.legacyCategory.defaultColor.rawValue,
            isIncome: expense.isIncome
        )
    }
}

/// Writes expenses as CSV following RFC 4180, for backup and spreadsheets.
///
/// The column order is a contract: new columns are only ever appended at the end,
/// so spreadsheets and scripts built on an older export keep working.
enum ExpenseCSV {
    /// The header names, in the order the columns are written. Append only.
    static let columns = [
        "date", "amount", "currency", "category", "category_name", "note", "category_symbol", "category_color", "kind",
    ]

    /// The `kind` value of an income row; spending is ``expenseKind``, and older files have no `kind`.
    static let incomeKind = "income"
    /// The `kind` value of a spending row.
    static let expenseKind = "expense"

    /// The columns every export since the first has had; an import requires them, in order.
    static let requiredColumns = Array(columns.prefix(6))

    /// RFC 4180 ends every record, including the header, with CRLF.
    private static let recordTerminator = "\r\n"

    /// Formats amounts with a dot and no grouping, whatever the device's region.
    private static let amountFormat = FloatingPointFormatStyle<Double>.number
        .locale(Locale(identifier: "en_US_POSIX"))
        .grouping(.never)
        .precision(.fractionLength(0...2))

    /// Returns the whole CSV document for the given expenses.
    ///
    /// - Parameters:
    ///   - records: The expenses to write, in the order they should appear.
    ///   - timeZone: The time zone for the dates; the device's zone by default.
    /// - Returns: The header followed by one record per expense, each ending in CRLF.
    /// - Complexity: O(*n*), where *n* is the number of records.
    static func document(for records: [ExpenseRecord], timeZone: TimeZone = .current) -> String {
        let dateFormat = Date.ISO8601FormatStyle(timeSeparator: .colon, timeZoneSeparator: .colon, timeZone: timeZone)
        let header = columns.joined(separator: ",")
        let rows = records.map { record in
            [
                record.date.formatted(dateFormat),
                record.amount.formatted(amountFormat),
                hryvniaCurrencyCode,
                record.categoryKey,
                record.categoryName,
                record.note,
                record.categorySymbol,
                record.categoryColorName,
                record.isIncome ? incomeKind : expenseKind,
            ]
            .map(field)
            .joined(separator: ",")
        }
        return ([header] + rows).map { $0 + recordTerminator }.joined()
    }

    /// Returns a value as a CSV field, quoted when RFC 4180 requires it.
    ///
    /// - Parameter value: The raw text of the field.
    /// - Returns: The value unchanged, or wrapped in quotes with inner quotes doubled
    ///   when it contains a comma, a quote, or a line break.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// The export offered by the share button: a snapshot of the expenses when it was made.
struct ExpenseExport: Transferable {
    /// The expenses to export, excluding one pending deletion.
    let records: [ExpenseRecord]
    /// The moment the snapshot was taken; its date names the file.
    let createdAt: Date

    static var transferRepresentation: some TransferRepresentation {
        // The CSV is built only when the person actually shares, not on every redraw.
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(ExpenseCSV.document(for: export.records).utf8)
        }
        .suggestedFileName { export in
            let day = export.createdAt.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
            return "Kalyta-\(day).csv"
        }
    }
}
