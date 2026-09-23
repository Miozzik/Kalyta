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
    /// How long a deletion can be undone before it is committed.
    ///
    /// A design constant rather than a user setting: long enough to read the banner
    /// and reach the button, short enough not to cover the list for long.
    private static let undoBannerDuration: Duration = .seconds(5)

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var isAddingExpense = false
    @State private var period: Period = .month
    /// The start of the period picked from the bars, or `nil` for the current period.
    @State private var selectedStart: Date?
    /// The expense the person just deleted, hidden but not yet removed from the store.
    ///
    /// SwiftData's undo cannot restore a deletion once it has been saved, and the main
    /// context saves right after every change, so the deletion is deferred instead:
    /// ``commitPendingDeletion()`` removes the expense when the undo window closes.
    @State private var pendingDeletion: Expense?

    /// Every expense except the one pending deletion.
    ///
    /// All derived values read this, never `expenses`, so totals drop the moment
    /// an expense is deleted and come back on undo.
    ///
    /// - Complexity: O(*n*), where *n* is the number of expenses.
    private var visibleExpenses: [Expense] {
        expenses.filter { $0 !== pendingDeletion }
    }

    private var intervals: [DateInterval] { period.intervals() }

    private var selectedInterval: DateInterval {
        intervals.first { $0.start == selectedStart } ?? intervals.last!
    }

    private var isCurrentPeriodSelected: Bool { selectedInterval == intervals.last }

    /// - Complexity: O(*n*), where *n* is the number of expenses.
    private var periodExpenses: [Expense] {
        visibleExpenses.filter { selectedInterval.containsExcludingEnd($0.date) }
    }

    private var periodTotal: Double { periodExpenses.reduce(0) { $0 + $1.amount } }

    /// - Complexity: O(*n*), where *n* is the number of expenses.
    private var todayTotal: Double {
        visibleExpenses.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amount }
    }

    /// - Complexity: O(*n* × *p*), where *n* is the number of expenses and *p* the number of bars.
    private var bars: [PeriodBar] {
        intervals.map { interval in
            PeriodBar(
                interval: interval,
                total: visibleExpenses.filter { interval.containsExcludingEnd($0.date) }.reduce(0) { $0 + $1.amount },
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
            List {
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
                    } else if !visibleExpenses.isEmpty {
                        Text("No expenses in this period")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(expensesByDay, id: \.day) { group in
                    Section {
                        ForEach(group.items) { expense in
                            ExpenseRow(expense: expense)
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", systemImage: "trash", role: .destructive) { delete(expense) }
                                }
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) { delete(expense) }
                                }
                        }
                    } header: {
                        DayHeader(title: title(forDay: group.day), total: group.items.reduce(0) { $0 + $1.amount })
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) {
                if pendingDeletion != nil {
                    UndoBanner {
                        withAnimation { pendingDeletion = nil }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task(id: pendingDeletion?.persistentModelID) {
                // No time limit for VoiceOver users: reaching the Undo button takes longer.
                // The deletion still commits on the next deletion or when the app leaves the foreground.
                guard pendingDeletion != nil, !isVoiceOverEnabled else { return }
                do {
                    try await Task.sleep(for: Self.undoBannerDuration)
                } catch {
                    return  // Cancelled by Undo or by another deletion: nothing to commit here.
                }
                withAnimation { commitPendingDeletion() }
            }
            .onChange(of: scenePhase) {
                if scenePhase != .active { commitPendingDeletion() }
            }
            .onDisappear { commitPendingDeletion() }
            .navigationTitle("Kalyta")
            .toolbar {
                Button("Add", systemImage: "plus") { isAddingExpense = true }
                    .buttonStyle(.borderedProminent)
            }
            .sheet(isPresented: $isAddingExpense) { AddExpenseView() }
            .overlay {
                if visibleExpenses.isEmpty {
                    ContentUnavailableView(
                        "Nothing recorded yet",
                        systemImage: "hryvniasign.circle",
                        description: Text("Tap + or set up a double tap on the back of your iPhone")
                    )
                }
            }
        }
    }

    /// Hides an expense and offers to undo the deletion.
    ///
    /// A deletion that is still pending is committed first, so only the latest one
    /// can be undone.
    ///
    /// - Parameter expense: The expense to delete.
    private func delete(_ expense: Expense) {
        commitPendingDeletion()
        withAnimation { pendingDeletion = expense }
        AccessibilityNotification.Announcement(String(localized: "Expense deleted")).post()
    }

    /// Removes the expense pending deletion from the store, if there is one.
    ///
    /// Saves at once instead of waiting for autosave: autosave runs later, and an app
    /// killed in between would bring back an expense whose undo window had already closed.
    private func commitPendingDeletion() {
        guard let expense = pendingDeletion else { return }
        context.delete(expense)
        pendingDeletion = nil
        try? context.save()
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
                .accessibilityIdentifier("periodBar")
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
                .accessibilityIdentifier("summaryTitle")
            Text(formattedHryvnias(total))
                .accessibilityIdentifier("summaryTotal")
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

/// The heading of a day section: the day's title and its total.
private struct DayHeader: View {
    let title: String
    let total: Double

    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(formattedHryvnias(total)).font(.subheadline).monospacedDigit()
        }
        .textCase(nil)
    }
}

/// The bar shown after a deletion, with a button that undoes it.
private struct UndoBanner: View {
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Label("Expense deleted", systemImage: "trash")
            Spacer()
            Button("Undo", action: onUndo)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .capsule)
        .padding(.horizontal)
        .padding(.bottom, 8)
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
        .padding(.vertical, 2)
    }
}
