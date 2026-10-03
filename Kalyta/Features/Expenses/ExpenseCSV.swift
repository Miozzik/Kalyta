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
    /// The amount in ``currencyCode`` as entered, or `nil` for a hryvnia entry.
    var originalAmount: Double?
    /// The ISO 4217 code of ``originalAmount``; `nil` means hryvnias.
    var currencyCode: String?
    /// Hryvnias per unit of ``currencyCode`` that ``amount`` was converted at.
    var rate: Double?
    /// Whether ``rate`` was a stand-in waiting for the NBU rate.
    var isRateEstimated: Bool = false
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
            isIncome: expense.isIncome,
            originalAmount: expense.originalAmount,
            currencyCode: expense.currencyCode,
            rate: expense.rate,
            isRateEstimated: expense.isRateEstimated
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
        "original_amount", "original_currency", "rate", "rate_estimated",
    ]

    /// The `kind` value of an income row; spending is ``expenseKind``, and older files have no `kind`.
    static let incomeKind = "income"
    /// The `kind` value of a spending row.
    static let expenseKind = "expense"

    /// The columns every export since the first has had; an import requires them, in order.
    static let requiredColumns = Array(columns.prefix(6))

    /// The `rate_estimated` values of a foreign row; a hryvnia row leaves it empty.
    static let estimatedValues = ["true": true, "false": false]

    /// RFC 4180 ends every record, including the header, with CRLF.
    private static let recordTerminator = "\r\n"

    /// Formats amounts with a dot and no grouping, whatever the device's region.
    private static let amountFormat = FloatingPointFormatStyle<Double>.number
        .locale(Locale(identifier: "en_US_POSIX"))
        .grouping(.never)
        .precision(.fractionLength(0...2))

    /// Formats foreign amounts and rates with a dot and up to six decimals, enough for any NBU rate.
    private static let preciseFormat = FloatingPointFormatStyle<Double>.number
        .locale(Locale(identifier: "en_US_POSIX"))
        .grouping(.never)
        .precision(.fractionLength(0...6))

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
                neutralized(record.categoryKey),
                neutralized(record.categoryName),
                neutralized(record.note),
                record.categorySymbol,
                record.categoryColorName,
                record.isIncome ? incomeKind : expenseKind,
                record.originalAmount?.formatted(preciseFormat) ?? "",
                record.currencyCode ?? "",
                record.rate?.formatted(preciseFormat) ?? "",
                record.currencyCode == nil ? "" : String(record.isRateEstimated),
            ]
            .map(field)
            .joined(separator: ",")
        }
        return ([header] + rows).map { $0 + recordTerminator }.joined()
    }

    /// The first characters that make a spreadsheet read a cell as a formula (CSV injection).
    static let formulaStarts: Set<Character> = ["=", "+", "-", "@", "\t", "\r", "\n", "\r\n", "＝", "＋", "－", "＠"]

    /// Returns typed text that a spreadsheet opens as text, never as a formula.
    ///
    /// A leading formula character gets a `'` in front (OWASP's advice for CSV injection).
    /// A leading `'` gets one too, so ``restored(_:)`` removes exactly the one added here.
    ///
    /// - Parameter value: A note, category name or key.
    /// - Returns: The value, prefixed with `'` if needed.
    static func neutralized(_ value: String) -> String {
        guard let first = value.first, formulaStarts.contains(first) || first == "'" else { return value }
        return "'" + value
    }

    /// Undoes ``neutralized(_:)`` when importing.
    ///
    /// - Parameter value: A field as read from the file.
    /// - Returns: The value without the `'` that export added.
    static func restored(_ value: String) -> String {
        guard value.first == "'", let second = value.dropFirst().first, formulaStarts.contains(second) || second == "'"
        else { return value }
        return String(value.dropFirst())
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

/// The backup offered by the share button: a snapshot of the entries when it was made.
struct ExpenseExport: Transferable {
    /// The entries to export.
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
