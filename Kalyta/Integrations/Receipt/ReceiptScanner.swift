import SwiftData
import SwiftUI
import VisionKit

/// The amount and moment read from the QR code of a Ukrainian fiscal receipt.
///
/// The code holds a link to the tax service's receipt search, for example
/// `https://cabinet.tax.gov.ua/cashregs/check?mac=…&date=20260924&time=1218&id=…&sm=432.90&fn=…`.
/// Everything needed is in the link itself, so it is parsed on the phone without any request.
struct FiscalReceipt: Equatable {
    /// The time zone receipt times are printed in; the link itself carries none.
    static let timeZone = TimeZone(identifier: "Europe/Kyiv")!

    /// The receipt total in hryvnias.
    let amount: Double
    /// When the receipt was issued, no later than the moment it was scanned.
    let date: Date

    /// Parses the payload of a scanned QR code.
    ///
    /// - Parameters:
    ///   - payload: The text of the code.
    ///   - now: The upper bound for the date, since the editor accepts no future dates.
    /// - Returns: `nil` if the payload is not a fiscal receipt link or lacks a valid amount, date or time.
    init?(payload: String, now: Date = .now) {
        // An exact host match rejects look-alikes such as "cabinet.tax.gov.ua.example.com".
        guard let components = URLComponents(string: payload), components.scheme == "https",
            components.host == "cabinet.tax.gov.ua", components.path == "/cashregs/check"
        else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        // Plain hryvnias and kopiykas only: `Double.init` would also take "1e308" and "0x10".
        guard let text = value("sm"), text.wholeMatch(of: /[0-9]{1,9}(\.[0-9]{1,2})?/) != nil,
            let sum = Double(text), isValidAmount(sum),
            let day = value("date"), day.count == 8, day.allSatisfy(\.isASCIIDigit),
            // Sources disagree on whether seconds are included, so both forms are accepted.
            let time = value("time"), [4, 6].contains(time.count), time.allSatisfy(\.isASCIIDigit)
        else { return nil }
        func number(_ text: String, _ offset: Int, _ length: Int) -> Int {
            let start = text.index(text.startIndex, offsetBy: offset)
            return Int(text[start..<text.index(start, offsetBy: length)])!
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        let parts = DateComponents(
            calendar: calendar, year: number(day, 0, 4), month: number(day, 4, 2), day: number(day, 6, 2),
            hour: number(time, 0, 2), minute: number(time, 2, 2), second: time.count == 6 ? number(time, 4, 2) : 0)
        // `Calendar.date(from:)` would roll month 13 over into the next year instead of failing.
        // Fiscal receipts with QR codes date from 2019; year 1 or a far future year is malformed.
        guard parts.isValidDate, let date = parts.date,
            (2019...calendar.component(.year, from: now)).contains(parts.year!)
        else { return nil }
        amount = sum
        self.date = min(date, now)
    }

    /// Returns the recorded expense this receipt most likely belongs to.
    ///
    /// - Parameter context: The context to search.
    /// - Returns: The matching expense, or `nil` if the receipt is a new purchase.
    func matchingExpense(in context: ModelContext) -> Expense? {
        Store.matchingExpense(amount: amount, date: date, in: context)
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}

/// The system QR scanner, reporting the payload of every code it recognizes.
struct ReceiptScannerView: UIViewControllerRepresentable {
    /// Receives each recognized payload.
    let onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onPayload = onPayload
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    /// Receives the scanner's delegate calls and passes on each recognized payload.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        /// Receives each recognized payload; updated with the view, so it always calls the current closure.
        var onPayload: (String) -> Void

        /// Creates a coordinator that reports payloads to a closure.
        ///
        /// - Parameter onPayload: Receives each recognized payload.
        init(onPayload: @escaping (String) -> Void) { self.onPayload = onPayload }

        func dataScanner(
            _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]
        ) {
            for case .barcode(let code) in addedItems {
                if let payload = code.payloadStringValue { onPayload(payload) }
            }
        }
    }
}
