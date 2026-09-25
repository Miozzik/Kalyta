import Charts
import SwiftData
import SwiftUI

/// The total spent in one category during the selected period.
struct CategoryTotal: Identifiable {
    /// The category's stable key.
    let id: String
    let title: String
    let color: Color
    let total: Double
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
    /// The expense open in the editor sheet, or `nil` when no expense is being edited.
    @State private var editingExpense: Expense?
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

    /// The visible entries that are spending, not income.
    ///
    /// The one place income is left out: every total, bar and chart reads this.
    ///
    /// - Complexity: O(*n*).
    private var visibleSpending: [Expense] {
        visibleExpenses.filter { !$0.isIncome }
    }

    private var intervals: [DateInterval] { period.intervals() }

    private var selectedInterval: DateInterval {
        intervals.first { $0.start == selectedStart } ?? intervals.last!
    }

    private var isCurrentPeriodSelected: Bool { selectedInterval == intervals.last }

    /// Every visible entry of the selected period, income included, for the list.
    ///
    /// - Complexity: O(*n*), where *n* is the number of entries.
    private var periodEntries: [Expense] {
        visibleExpenses.filter { selectedInterval.containsExcludingEnd($0.date) }
    }

    /// The spending of the selected period.
    ///
    /// - Complexity: O(*n*), where *n* is the number of entries.
    private var periodExpenses: [Expense] {
        visibleSpending.filter { selectedInterval.containsExcludingEnd($0.date) }
    }

    private var periodTotal: Double { periodExpenses.reduce(0) { $0 + $1.amount } }

    /// The income of the selected period.
    private var periodIncome: Double { periodEntries.filter(\.isIncome).reduce(0) { $0 + $1.amount } }

    /// - Complexity: O(*n*), where *n* is the number of expenses.
    private var todayTotal: Double { TodayTotal.spending(of: visibleExpenses) }

    /// - Complexity: O(*n* × *p*), where *n* is the number of expenses and *p* the number of bars.
    private var bars: [PeriodBar] {
        intervals.map { interval in
            PeriodBar(
                interval: interval,
                total: visibleSpending.filter { interval.containsExcludingEnd($0.date) }.reduce(0) { $0 + $1.amount },
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
        Dictionary(grouping: periodExpenses) { $0.assignedCategory?.key ?? $0.legacyCategory.rawValue }
            .map { key, items in
                CategoryTotal(
                    id: key, title: items[0].categoryTitle, color: items[0].categoryColor,
                    total: items.reduce(0) { $0 + $1.amount })
            }
            .sorted { $0.total > $1.total }
    }

    /// Expenses of the selected period grouped by day, most recent day first.
    private var expensesByDay: [(day: Date, items: [Expense])] {
        Dictionary(grouping: periodEntries) { Calendar.current.startOfDay(for: $0.date) }
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
                        todayTotal: isCurrentPeriodSelected ? todayTotal : nil,
                        income: periodIncome > 0 ? periodIncome : nil
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
                            Button {
                                editingExpense = expense
                            } label: {
                                ExpenseRow(expense: expense)
                            }
                            // A Button in a List tints its label with the accent color; keep the text neutral.
                            .foregroundStyle(.primary)
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
                guard let expense = pendingDeletion, !isVoiceOverEnabled else { return }
                do {
                    try await Task.sleep(for: Self.undoBannerDuration)
                } catch {
                    return  // Cancelled by Undo or by another deletion: nothing to commit here.
                }
                // SwiftUI cancels a replaced task only on its next update, so this timer can
                // wake after a newer deletion took over. Commit only the one it was started for.
                guard pendingDeletion === expense else { return }
                withAnimation { commitPendingDeletion() }
            }
            .onChange(of: scenePhase) {
                if scenePhase != .active { commitPendingDeletion() }
            }
            .onDisappear { commitPendingDeletion() }
            .navigationTitle("Kalyta")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // One snapshot feeds both the file and the title, so the count shown is what is exported.
                    let export = ExpenseExport(records: visibleExpenses.map(ExpenseRecord.init), createdAt: .now)
                    ShareLink(
                        item: export, preview: SharePreview(String(localized: "\(export.records.count) entries"))
                    ) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") { isAddingExpense = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $isAddingExpense) { ExpenseEditor() }
            .sheet(item: $editingExpense) { expense in
                ExpenseEditor(expense: expense, onDelete: delete)
            }
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
    /// The period's income, or `nil` to show nothing about income when there is none.
    let income: Double?

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
            if let income {
                // What is left can be negative: spending more than came in.
                Label(
                    "earned \(formattedHryvnias(income)) · left \(formattedHryvnias(income - total))",
                    systemImage: "arrow.down.circle"
                )
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityIdentifier("summaryIncome")
            }
            if let todayTotal {
                Label("today \(formattedHryvnias(todayTotal))", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.summaryGradient, in: .rect(cornerRadius: 24))
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
                    .foregroundStyle(row.color)
                    .cornerRadius(4)
                    .accessibilityLabel(row.title)
                    .accessibilityValue(formattedHryvnias(row.total))
            }
            .frame(height: 170)
            .chartLegend(.hidden)
            .overlay {
                if let largest = rows.first {
                    VStack(spacing: 2) {
                        Text(formattedShare(of: largest.total))
                            .font(.title2.bold().monospacedDigit())
                        Text(largest.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Circle().fill(row.color).frame(width: 10, height: 10)
                        Text(row.title)
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
