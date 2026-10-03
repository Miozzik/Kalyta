import Foundation

/// Today's spending as the widget sees it: where the app publishes it and how it is read back.
///
/// Shared with the widget extension, so it uses no SwiftData; the app's side, adding up and
/// publishing after every save, is in `TodayTotalPublisher.swift`. The widget reads the total
/// with ``storedTotal(in:now:calendar:)``, which shows 0 once that day is over.
enum TodayTotal {
    /// The kind of the widget that shows the total: the receipt-scan widget, which has room for it.
    ///
    /// Must stay "ScanReceipt": a widget's kind is its identity, so a new one would drop the
    /// widgets people already placed.
    static let widgetKind = "ScanReceipt"
    /// The defaults key of the published total, in hryvnias.
    static let totalKey = "todayTotal"
    /// The defaults key of the start of the day the total belongs to.
    static let dayStartKey = "todayStart"

    /// The App Group's defaults, from `APP_GROUP_ID` in `Config/Kalyta.xcconfig`.
    static var sharedDefaults: UserDefaults? {
        (Bundle.main.object(forInfoDictionaryKey: "KalytaAppGroup") as? String).flatMap(UserDefaults.init(suiteName:))
    }

    /// Returns the published total, or 0 if it belongs to another day.
    ///
    /// A total written yesterday stays in the defaults until the app next saves or opens,
    /// so the day it belongs to is checked, never assumed.
    ///
    /// - Parameters:
    ///   - defaults: Where the app published the total.
    ///   - now: The current time.
    ///   - calendar: The calendar that defines the day.
    /// - Returns: Today's published spending, or 0.
    static func storedTotal(in defaults: UserDefaults, now: Date = .now, calendar: Calendar = .current) -> Double {
        guard let start = defaults.object(forKey: dayStartKey) as? Date,
            start == calendar.dateInterval(of: .day, for: now)!.start
        else { return 0 }
        return defaults.double(forKey: totalKey)
    }

    /// Returns the widget's timeline: the published total now, then 0 from the next midnight.
    ///
    /// - Parameters:
    ///   - total: Today's published total, from ``storedTotal(in:now:calendar:)``.
    ///   - now: The current time.
    ///   - calendar: The calendar that defines the day.
    /// - Returns: The two entries' dates and totals; the timeline ends after the second.
    static func timeline(total: Double, now: Date = .now, calendar: Calendar = .current) -> [(
        date: Date, total: Double
    )] {
        [(now, total), (calendar.dateInterval(of: .day, for: now)!.end, 0)]
    }
}
