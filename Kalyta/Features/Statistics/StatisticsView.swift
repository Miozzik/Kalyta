import Charts
import SwiftData
import SwiftUI

/// The Statistics tab: a list of submenus sharing one remembered range.
struct StatisticsView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    /// Six months by default, so the first visit shows a trend rather than a single bar.
    @AppStorage("statisticsRange") private var range: StatisticsRange = .sixMonths

    private var months: [DateInterval] { range.months(earliest: expenses.last?.date) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Range", selection: $range) {
                        ForEach(StatisticsRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    NavigationLink {
                        MonthlyTotalsView(expenses: expenses, months: months)
                    } label: {
                        Label("Months", systemImage: "chart.bar.fill")
                    }
                    NavigationLink {
                        CategoryMonthsView(expenses: expenses, months: months)
                    } label: {
                        Label("Categories by Month", systemImage: "chart.bar.doc.horizontal.fill")
                    }
                    NavigationLink {
                        PlacesView(expenses: expenses, months: months)
                    } label: {
                        Label("Places", systemImage: "mappin.and.ellipse")
                    }
                    NavigationLink {
                        BiggestExpensesView(expenses: expenses, months: months)
                    } label: {
                        Label("Biggest Expenses", systemImage: "arrow.up.circle.fill")
                    }
                }
            }
            .navigationTitle("Statistics")
        }
    }
}

/// Monthly totals with the average of complete months: "am I spending more than usual?"
private struct MonthlyTotalsView: View {
    /// The stored expenses; copied into ``records`` once when the screen appears.
    let expenses: [Expense]
    let months: [DateInterval]
    /// The expenses inside the range. Copying 10,000 rows takes about 50 ms, too long to
    /// repeat on every redraw, so it happens once per visit.
    @State private var records: [ExpenseRecord] = []

    var body: some View {
        let totals = Statistics.monthlyTotals(records, months: months)
        let average = Statistics.averageOfCompleteMonths(totals)
        List {
            Section {
                Chart {
                    ForEach(totals) { month in
                        BarMark(x: .value("Month", month.month.start, unit: .month), y: .value("Amount", month.total))
                            .foregroundStyle(Color.indigo.gradient)
                            .accessibilityLabel(month.month.start.formatted(.dateTime.month(.wide).year()))
                            .accessibilityValue(formattedHryvnias(month.total))
                    }
                    if let average {
                        RuleMark(y: .value("Average", average))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(localized: "Average"))
                            .accessibilityValue(formattedHryvnias(average))
                    }
                }
                .chartXAxis { monthAxis(monthCount: months.count) }
                .frame(height: 220)
                if let average {
                    LabeledContent("Average per month", value: formattedHryvnias(average))
                }
            } footer: {
                Text("The average counts only finished months with expenses.")
            }
            Section {
                ForEach(totals.reversed()) { month in
                    LabeledContent(month.month.start.formatted(.dateTime.month(.wide).year())) {
                        Text(formattedHryvnias(month.total)).monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Months")
        .onAppear { records = Statistics.records(expenses.map(ExpenseRecord.init), within: months) }
        .overlay { if records.isEmpty { NoStatisticsView() } }
    }
}

/// Spending per category, stacked by month: "is Food growing?"
private struct CategoryMonthsView: View {
    /// The stored expenses; copied into ``records`` once when the screen appears.
    let expenses: [Expense]
    let months: [DateInterval]
    /// The expenses inside the range. Copying 10,000 rows takes about 50 ms, too long to
    /// repeat on every redraw, so it happens once per visit.
    @State private var records: [ExpenseRecord] = []

    var body: some View {
        let segments = Statistics.categoryTotalsByMonth(records, months: months, restName: String(localized: "Rest"))
        let legend = Dictionary(grouping: segments, by: \.categoryKey)
            .map { key, items in
                (
                    key: key, name: items[0].categoryName, colorName: items[0].colorName,
                    total: items.reduce(0) { $0 + $1.total }
                )
            }
            .sorted { $0.total > $1.total }
        List {
            Section {
                Chart(segments) { segment in
                    BarMark(x: .value("Month", segment.month.start, unit: .month), y: .value("Amount", segment.total))
                        .foregroundStyle(CategoryColor(rawValue: segment.colorName)?.color ?? .gray)
                        .accessibilityLabel(segmentLabel(segment))
                        .accessibilityValue(formattedHryvnias(segment.total))
                }
                .chartXAxis { monthAxis(monthCount: months.count) }
                .frame(height: 220)
                .accessibilityChartDescriptor(CategoryChartDescriptor(segments: segments, months: months))
            }
            Section {
                ForEach(legend, id: \.key) { row in
                    HStack(spacing: 10) {
                        Circle().fill(CategoryColor(rawValue: row.colorName)?.color ?? .gray).frame(
                            width: 10, height: 10)
                        Text(row.name)
                        Spacer()
                        Text(formattedHryvnias(row.total)).monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Categories by Month")
        .onAppear { records = Statistics.records(expenses.map(ExpenseRecord.init), within: months) }
        .overlay { if records.isEmpty { NoStatisticsView() } }
    }
}

/// Returns the VoiceOver label of a chart segment, such as "Їжа, вересень 2026 р.".
///
/// Built as a `String` so the catalog does not get a data-only "%@, %@" key.
private func segmentLabel(_ segment: Statistics.CategoryMonthTotal) -> String {
    "\(segment.categoryName), \(segment.month.start.formatted(.dateTime.month(.wide).year()))"
}

/// Returns month labels for the x axis: abbreviated when they fit, a single letter when many are shown.
///
/// - Parameter monthCount: How many months the chart shows.
@AxisContentBuilder
private func monthAxis(monthCount: Int) -> some AxisContent {
    AxisMarks(values: .stride(by: .month)) { _ in
        AxisValueLabel(format: monthCount <= 6 ? .dateTime.month(.abbreviated) : .dateTime.month(.narrow))
    }
}

/// Describes the stacked category chart to Audio Graphs.
private struct CategoryChartDescriptor: AXChartDescriptorRepresentable {
    let segments: [Statistics.CategoryMonthTotal]
    let months: [DateInterval]

    func makeChartDescriptor() -> AXChartDescriptor {
        let names = months.map { $0.start.formatted(.dateTime.month(.abbreviated).year()) }
        let peak =
            Dictionary(grouping: segments, by: \.month.start).values.map { $0.reduce(0) { $0 + $1.total } }.max() ?? 0
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: "Month"), categoryOrder: names)
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Amount"), range: 0...max(peak, 1), gridlinePositions: []
        ) { formattedHryvnias($0) }
        let series = Dictionary(grouping: segments, by: \.categoryKey).map { _, items in
            AXDataSeriesDescriptor(
                name: items[0].categoryName, isContinuous: false,
                dataPoints: items.map {
                    AXDataPoint(x: $0.month.start.formatted(.dateTime.month(.abbreviated).year()), y: $0.total)
                })
        }
        return AXChartDescriptor(
            title: String(localized: "Categories by Month"), summary: nil, xAxis: xAxis, yAxis: yAxis,
            additionalAxes: [], series: series)
    }
}

/// Where the money goes, grouped by note.
private struct PlacesView: View {
    /// The stored expenses; copied into ``records`` once when the screen appears.
    let expenses: [Expense]
    let months: [DateInterval]
    /// The expenses inside the range. Copying 10,000 rows takes about 50 ms, too long to
    /// repeat on every redraw, so it happens once per visit.
    @State private var records: [ExpenseRecord] = []

    /// How many places the screen lists.
    private static let limit = 15

    var body: some View {
        let places = Statistics.topPlaces(records, limit: Self.limit)
        List(places) { place in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                    Text("\(place.count) times").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(formattedHryvnias(place.total)).monospacedDigit()
            }
        }
        .navigationTitle("Places")
        .onAppear { records = Statistics.records(expenses.map(ExpenseRecord.init), within: months) }
        .overlay { if places.isEmpty { NoStatisticsView() } }
    }
}

/// The largest single expenses: "what hit me?"
private struct BiggestExpensesView: View {
    /// The stored expenses; copied into ``records`` once when the screen appears.
    let expenses: [Expense]
    let months: [DateInterval]
    /// The expenses inside the range. Copying 10,000 rows takes about 50 ms, too long to
    /// repeat on every redraw, so it happens once per visit.
    @State private var records: [ExpenseRecord] = []

    /// How many expenses the screen lists.
    private static let limit = 20

    var body: some View {
        let biggest = Statistics.biggest(records, limit: Self.limit)
        // Two expenses can share a timestamp, so rows are identified by rank.
        List(Array(biggest.enumerated()), id: \.offset) { _, record in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.note.isEmpty ? record.categoryName : record.note)
                    Text(record.date, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(formattedHryvnias(record.amount)).monospacedDigit()
            }
        }
        .navigationTitle("Biggest Expenses")
        .onAppear { records = Statistics.records(expenses.map(ExpenseRecord.init), within: months) }
        .overlay { if biggest.isEmpty { NoStatisticsView() } }
    }
}

/// Shown on a Statistics screen when the range has no expenses.
private struct NoStatisticsView: View {
    var body: some View {
        ContentUnavailableView("No expenses in this range", systemImage: "chart.bar")
    }
}
