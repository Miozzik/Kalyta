import Charts
import SwiftData
import SwiftUI

/// The total spent in one category during the selected period.
struct CategoryTotal: Identifiable {
    let category: Category
    let total: Double
    var id: String { category.rawValue }
}

/// The total spent during one period, shown as a bar in the period selector.
struct PeriodBar: Identifiable {
    let interval: DateInterval
    let total: Double
    let label: String
    var id: Date { interval.start }
}

/// The main screen: period selector, summary, category breakdown, and expenses by day.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var isAddingExpense = false
    @State private var period: Period = .month
    /// The start of the period picked from the bars, or `nil` for the current period.
    @State private var selectedStart: Date?

    private var intervals: [DateInterval] { period.intervals() }

    private var selectedInterval: DateInterval {
        intervals.first { $0.start == selectedStart } ?? intervals.last!
    }

    private var isCurrentPeriodSelected: Bool { selectedInterval == intervals.last }

    /// - Complexity: O(*n*), where *n* is the number of expenses.
    private var periodExpenses: [Expense] {
        expenses.filter { selectedInterval.containsExcludingEnd($0.date) }
    }

    private var periodTotal: Double { periodExpenses.reduce(0) { $0 + $1.amount } }

    /// - Complexity: O(*n*), where *n* is the number of expenses.
    private var todayTotal: Double {
        expenses.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amount }
    }

    /// - Complexity: O(*n* × *p*), where *n* is the number of expenses and *p* the number of bars.
    private var bars: [PeriodBar] {
        intervals.map { interval in
            PeriodBar(
                interval: interval,
                total: expenses.filter { interval.containsExcludingEnd($0.date) }.reduce(0) { $0 + $1.amount },
                label: period.shortLabel(for: interval)
            )
        }
    }

    private var summaryTitle: String {
        if isCurrentPeriodSelected {
            return period == .week ? String(localized: "Spent this week") : String(localized: "Spent this month")
        }
        return String(
            localized: "Spent in \(period.title(for: selectedInterval))",
            comment:
                "Summary card title for a past period; the argument is a month name or a week range such as 15–21 Sep.")
    }

    /// Category totals for the selected period, largest first.
    private var totalsByCategory: [CategoryTotal] {
        Dictionary(grouping: periodExpenses, by: \.category)
            .map { CategoryTotal(category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    /// Expenses of the selected period grouped by day, most recent day first.
    private var expensesByDay: [(day: Date, items: [Expense])] {
        Dictionary(grouping: periodExpenses) { Calendar.current.startOfDay(for: $0.date) }
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: period) { selectedStart = nil }

                    PeriodBars(bars: bars, selectedStart: selectedInterval.start) { start in
                        withAnimation(.snappy) { selectedStart = start }
                    }

                    SummaryCard(
                        title: summaryTitle,
                        total: periodTotal,
                        todayTotal: isCurrentPeriodSelected ? todayTotal : nil
                    )

                    if !totalsByCategory.isEmpty {
                        CategoryBreakdown(rows: totalsByCategory, total: periodTotal)
                    } else if !expenses.isEmpty {
                        Text("No expenses in this period")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                    }

                    ForEach(expensesByDay, id: \.day) { group in
                        DaySection(
                            title: title(forDay: group.day),
                            total: group.items.reduce(0) { $0 + $1.amount },
                            items: group.items,
                            onDelete: { context.delete($0) }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Kalyta")
            .toolbar {
                Button("Add", systemImage: "plus") { isAddingExpense = true }
                    .buttonStyle(.borderedProminent)
            }
            .sheet(isPresented: $isAddingExpense) { AddExpenseView() }
            .overlay {
                if expenses.isEmpty {
                    ContentUnavailableView(
                        "Nothing recorded yet",
                        systemImage: "hryvniasign.circle",
                        description: Text("Tap + or set up a double tap on the back of your iPhone")
                    )
                }
            }
        }
    }

    /// Returns "Сьогодні", "Вчора", or the date, for a day section heading.
    ///
    /// - Parameter day: The start of the day.
    /// - Returns: A localized heading.
    private func title(forDay day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.day().month(.wide))
    }
}

/// A row of bars, one per period, where tapping a bar selects that period.
private struct PeriodBars: View {
    let bars: [PeriodBar]
    let selectedStart: Date
    let onSelect: (Date) -> Void

    var body: some View {
        let peak = max(bars.map(\.total).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(bars) { bar in
                let isSelected = bar.id == selectedStart
                Button {
                    onSelect(bar.id)
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.indigo : Color.indigo.opacity(0.22))
                            .frame(height: max(4, 72 * bar.total / peak))
                        Text(bar.label)
                            .font(.caption2.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityText(for: bar))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(height: 100, alignment: .bottom)
        .padding(.horizontal, 4)
    }

    /// Returns the VoiceOver label for a bar, such as "Sep, 3,132.40 ₴".
    ///
    /// - Parameter bar: The bar to describe.
    /// - Returns: The period label and total, already localized by their formatters.
    private func accessibilityText(for bar: PeriodBar) -> String {
        "\(bar.label), \(formattedHryvnias(bar.total))"
    }
}

/// The gradient card with the period total and, for the current period, today's total.
private struct SummaryCard: View {
    let title: String
    let total: Double
    /// Today's total, or `nil` to hide the line when a past period is selected.
    let todayTotal: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Text(formattedHryvnias(total))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            if let todayTotal {
                Label("today \(formattedHryvnias(todayTotal))", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [.teal, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 24)
        )
    }
}

/// A donut chart of category shares with a legend of amounts.
private struct CategoryBreakdown: View {
    /// Category totals, largest first; the first one is highlighted in the center.
    let rows: [CategoryTotal]
    let total: Double

    var body: some View {
        VStack(spacing: 16) {
            Chart(rows) { row in
                SectorMark(angle: .value("Amount", row.total), innerRadius: .ratio(0.62), angularInset: 2)
                    .foregroundStyle(row.category.color)
                    .cornerRadius(4)
            }
            .frame(height: 170)
            .chartLegend(.hidden)
            .overlay {
                if let largest = rows.first {
                    VStack(spacing: 2) {
                        Text(formattedShare(of: largest.total))
                            .font(.title2.bold().monospacedDigit())
                        Text(largest.category.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Circle().fill(row.category.color).frame(width: 10, height: 10)
                        Text(row.category.title)
                        Spacer()
                        Text(formattedShare(of: row.total))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(formattedHryvnias(row.total)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    /// Formats an amount as a whole-number percentage of the period total.
    ///
    /// - Parameter amount: A part of ``total``.
    /// - Returns: A string such as "46 %", or an empty string when the total is zero.
    private func formattedShare(of amount: Double) -> String {
        guard total > 0 else { return "" }
        return (amount / total).formatted(.percent.precision(.fractionLength(0)))
    }
}

/// A card listing one day's expenses under a heading with the day's total.
private struct DaySection: View {
    let title: String
    let total: Double
    let items: [Expense]
    let onDelete: (Expense) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(formattedHryvnias(total))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ForEach(items) { expense in
                ExpenseRow(expense: expense)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(expense) }
                    }
                if expense.id != items.last?.id {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

/// A single expense: category icon, note or category name, time, and amount.
private struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(expense.category.color)
                .frame(width: 40, height: 40)
                .background(expense.category.color.opacity(0.15), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.note.isEmpty ? expense.category.title : expense.note)
                Text(expense.date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formattedHryvnias(expense.amount))
                .font(.body.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
