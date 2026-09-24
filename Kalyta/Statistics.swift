import Foundation

/// The span every Statistics screen covers, shared and remembered between launches.
enum StatisticsRange: String, CaseIterable, Identifiable {
    case sixMonths, twelveMonths, allTime

    var id: Self { self }

    /// The localized name shown in the segmented picker.
    var title: String {
        switch self {
        case .sixMonths: String(localized: "6 months")
        case .twelveMonths: String(localized: "12 months")
        case .allTime: String(localized: "All time")
        }
    }

    /// Returns the calendar months the range covers, oldest first, ending with the current one.
    ///
    /// - Parameters:
    ///   - earliest: The date of the oldest expense, used by ``allTime``.
    ///   - now: The moment the last month must contain.
    ///   - calendar: The calendar that defines months.
    /// - Returns: Adjacent month intervals from ``Period/intervals(count:now:calendar:)``.
    func months(earliest: Date?, now: Date = .now, calendar: Calendar = .current) -> [DateInterval] {
        let count: Int
        switch self {
        case .sixMonths: count = 6
        case .twelveMonths: count = 12
        case .allTime:
            let first = earliest ?? now
            let span = calendar.dateComponents([.month], from: calendar.startOfMonth(for: first), to: now).month ?? 0
            count = max(span + 1, 1)
        }
        return Period.month.intervals(count: count, now: now, calendar: calendar)
    }
}

/// Totals and rankings for the Statistics screens, as pure functions over expense snapshots.
enum Statistics {
    /// The total spent in one month.
    struct MonthTotal: Identifiable, Equatable {
        let month: DateInterval
        let total: Double
        var id: Date { month.start }
    }

    /// The total spent in one category during one month.
    struct CategoryMonthTotal: Identifiable, Equatable {
        let month: DateInterval
        /// The category key, or ``restKey`` for the categories folded together.
        let categoryKey: String
        let categoryName: String
        /// The ``CategoryColor`` name of the category.
        let colorName: String
        let total: Double
        var id: String { "\(month.start.timeIntervalSince1970)-\(categoryKey)" }
    }

    /// One place, grouped from notes that differ only in case, width or surrounding spaces.
    struct Place: Identifiable, Equatable {
        /// The most frequent original spelling of the note.
        let name: String
        let count: Int
        let total: Double
        var id: String { name }
    }

    /// The key of the bar segment that holds every category outside the largest ones.
    static let restKey = "_rest"

    /// How many categories get their own segment before the rest are folded together.
    ///
    /// HIG Charts: keep charts simple; more segments than this turn into colour noise.
    static let maximumCategorySegments = 5

    /// Returns the spending whose dates fall within the given months.
    ///
    /// The one place Statistics leaves income out: every screen starts from this.
    ///
    /// - Parameters:
    ///   - records: All entries.
    ///   - months: Adjacent months, oldest first.
    /// - Returns: The expenses, not income, from the start of the first month to the end of the last.
    /// - Complexity: O(*n*).
    static func records(_ records: [ExpenseRecord], within months: [DateInterval]) -> [ExpenseRecord] {
        guard let first = months.first, let last = months.last else { return [] }
        let span = DateInterval(start: first.start, end: last.end)
        return records.filter { !$0.isIncome && span.containsExcludingEnd($0.date) }
    }

    /// Returns the total of each month, including months without expenses.
    ///
    /// - Parameters:
    ///   - records: The expenses to add up.
    ///   - months: Adjacent months, oldest first.
    /// - Returns: One total per month, in the same order.
    /// - Complexity: O(*n* × *m*), where *m* is the number of months.
    static func monthlyTotals(_ records: [ExpenseRecord], months: [DateInterval]) -> [MonthTotal] {
        months.map { month in
            MonthTotal(
                month: month,
                total: records.filter { month.containsExcludingEnd($0.date) }.reduce(0) { $0 + $1.amount })
        }
    }

    /// Returns the average monthly spending over complete months that have expenses.
    ///
    /// The current month is left out because it is not over yet: counting it would pull
    /// the average down every early month. Months without any expense are left out too,
    /// so a gap before the person started using the app does not count as zero spending.
    ///
    /// - Parameters:
    ///   - totals: Monthly totals, oldest first, the last being the current month.
    ///   - now: The current moment.
    /// - Returns: The average, or `nil` when no complete month has expenses.
    static func averageOfCompleteMonths(_ totals: [MonthTotal], now: Date = .now) -> Double? {
        let complete = totals.filter { $0.month.end <= now && $0.total > 0 }
        guard !complete.isEmpty else { return nil }
        return complete.reduce(0) { $0 + $1.total } / Double(complete.count)
    }

    /// Returns each month's spending split by category, folding smaller categories together.
    ///
    /// The categories with the largest totals over the whole range keep their own segment;
    /// the rest become one segment keyed ``restKey``.
    ///
    /// - Parameters:
    ///   - records: The expenses to split.
    ///   - months: Adjacent months, oldest first.
    ///   - restName: The localized name of the folded segment.
    /// - Returns: One entry per month and category that has spending.
    /// - Complexity: O(*n* × *m*).
    static func categoryTotalsByMonth(
        _ records: [ExpenseRecord], months: [DateInterval], restName: String
    ) -> [CategoryMonthTotal] {
        let totalsByKey = Dictionary(grouping: records, by: \.categoryKey).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let kept = Set(
            totalsByKey.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .prefix(maximumCategorySegments).map(\.key))
        let looks = Dictionary(records.map { ($0.categoryKey, $0) }, uniquingKeysWith: { first, _ in first })

        return months.flatMap { month -> [CategoryMonthTotal] in
            let inMonth = records.filter { month.containsExcludingEnd($0.date) }
            let grouped = Dictionary(grouping: inMonth) { kept.contains($0.categoryKey) ? $0.categoryKey : restKey }
            return grouped.map { key, items in
                let look = looks[key]
                return CategoryMonthTotal(
                    month: month, categoryKey: key, categoryName: look?.categoryName ?? restName,
                    colorName: look?.categoryColorName ?? CategoryColor.gray.rawValue,
                    total: items.reduce(0) { $0 + $1.amount })
            }
            .sorted { $0.total > $1.total }
        }
    }

    /// Returns the largest expenses, largest first.
    ///
    /// - Parameters:
    ///   - records: The expenses to rank.
    ///   - limit: How many to return.
    /// - Returns: At most `limit` expenses; equal amounts keep the newer one first.
    static func biggest(_ records: [ExpenseRecord], limit: Int) -> [ExpenseRecord] {
        Array(records.sorted { $0.amount == $1.amount ? $0.date > $1.date : $0.amount > $1.amount }.prefix(limit))
    }

    /// Returns the places spent at most, by total, grouping notes that name the same place.
    ///
    /// Notes are compared ignoring case, character width and surrounding spaces, so "АТБ",
    /// "атб " and "ＡＴＢ" are one place. Diacritics are NOT ignored: in Ukrainian that would
    /// merge different letters ("Київ" would become "киів", "Мій" would equal "Міи").
    ///
    /// - Parameters:
    ///   - records: The expenses to group; those without a note are skipped.
    ///   - limit: How many places to return.
    /// - Returns: At most `limit` places, by total spent, largest first.
    static func topPlaces(_ records: [ExpenseRecord], limit: Int) -> [Place] {
        let groups = Dictionary(grouping: records.filter { !$0.note.trimmingCharacters(in: .whitespaces).isEmpty }) {
            placeKey($0.note)
        }
        let places = groups.values.map { items -> Place in
            let spellings = Dictionary(grouping: items) { $0.note.trimmingCharacters(in: .whitespaces) }
            let name = spellings.max {
                $0.value.count == $1.value.count ? $0.key > $1.key : $0.value.count < $1.value.count
            }!.key
            return Place(name: name, count: items.count, total: items.reduce(0) { $0 + $1.amount })
        }
        return Array(places.sorted { $0.total == $1.total ? $0.name < $1.name : $0.total > $1.total }.prefix(limit))
    }

    /// Returns the key two notes share when they name the same place.
    ///
    /// - Parameter note: A note as typed or filled in by an automation.
    /// - Returns: The note trimmed and folded for case and width only.
    static func placeKey(_ note: String) -> String {
        note.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }
}

extension Calendar {
    /// Returns the start of the month that contains `date`.
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? date
    }
}
