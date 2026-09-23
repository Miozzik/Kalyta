import Foundation

/// The length of the time span the main screen summarizes.
enum Period: String, CaseIterable, Identifiable {
    case week, month

    var id: Self { self }

    /// The localized name shown in the segmented picker.
    var title: String { self == .week ? String(localized: "Week") : String(localized: "Month") }

    private var component: Calendar.Component { self == .week ? .weekOfYear : .month }

    /// Returns consecutive periods ending with the one that contains `now`.
    ///
    /// The first day of the week comes from the calendar, so it follows the
    /// device's region setting (Monday in Ukraine).
    ///
    /// - Parameters:
    ///   - count: The number of periods to return.
    ///   - now: The moment that the last period must contain.
    ///   - calendar: The calendar that defines period boundaries.
    /// - Returns: Adjacent intervals, oldest first, where each interval ends
    ///   exactly where the next one starts.
    func intervals(count: Int = 6, now: Date = .now, calendar: Calendar = .current) -> [DateInterval] {
        (0..<count).reversed().compactMap { periodsBack in
            calendar.date(byAdding: component, value: -periodsBack, to: now)
                .flatMap { calendar.dateInterval(of: component, for: $0) }
        }
    }

    /// Returns the heading for a period, such as "вересень" or "15–21 вер.".
    ///
    /// Months outside the current year get the year appended.
    ///
    /// - Parameters:
    ///   - interval: A period produced by ``intervals(count:now:calendar:)``.
    ///   - calendar: The calendar used to find the period's last day and year.
    /// - Returns: A localized, human-readable heading.
    func title(for interval: DateInterval, calendar: Calendar = .current) -> String {
        switch self {
        case .month:
            let monthName = interval.start.formatted(.dateTime.month(.wide))
            let isThisYear = calendar.isDate(interval.start, equalTo: .now, toGranularity: .year)
            return isThisYear ? monthName : "\(monthName) \(calendar.component(.year, from: interval.start))"
        case .week:
            let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let firstDayText = interval.start.formatted(.dateTime.day())
            let lastDayText = lastDay.formatted(.dateTime.day().month(.abbreviated))
            return "\(firstDayText)–\(lastDayText)"
        }
    }

    /// Returns the compact label shown under a bar, such as "вер." or "15.09".
    ///
    /// - Parameter interval: A period produced by ``intervals(count:now:calendar:)``.
    /// - Returns: A label short enough to fit under a narrow bar.
    func shortLabel(for interval: DateInterval) -> String {
        switch self {
        case .month: interval.start.formatted(.dateTime.month(.abbreviated))
        case .week: interval.start.formatted(.dateTime.day().month(.twoDigits))
        }
    }
}

extension DateInterval {
    /// Returns whether a date falls within the interval, excluding its end.
    ///
    /// The built-in `contains(_:)` includes `end`, which is also the start of the
    /// next period, so an expense at exactly midnight would be counted twice.
    ///
    /// - Parameter date: The date to test.
    /// - Returns: `true` if `start <= date < end`.
    func containsExcludingEnd(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
