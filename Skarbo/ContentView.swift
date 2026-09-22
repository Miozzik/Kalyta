import SwiftUI
import SwiftData
import Charts

struct CategoryTotal: Identifiable {
    let category: Category
    let total: Double
    var id: String { category.rawValue }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var adding = false

    private var monthExpenses: [Expense] {
        let from = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        return expenses.filter { $0.date >= from }
    }

    private var monthTotal: Double { monthExpenses.reduce(0) { $0 + $1.amount } }

    private var todayTotal: Double {
        expenses.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amount }
    }

    private var byCategory: [CategoryTotal] {
        Dictionary(grouping: monthExpenses, by: \.category)
            .map { CategoryTotal(category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    /// Витрати по днях, найсвіжіший день зверху.
    private var byDay: [(day: Date, items: [Expense])] {
        Dictionary(grouping: expenses) { Calendar.current.startOfDay(for: $0.date) }
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    SummaryCard(month: monthTotal, today: todayTotal)

                    if !byCategory.isEmpty {
                        CategoryBreakdown(rows: byCategory, total: monthTotal)
                    }

                    ForEach(byDay, id: \.day) { group in
                        DaySection(
                            title: dayTitle(group.day),
                            total: group.items.reduce(0) { $0 + $1.amount },
                            items: group.items,
                            delete: { context.delete($0) }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Skarbo")
            .toolbar {
                Button("Додати", systemImage: "plus") { adding = true }
                    .buttonStyle(.borderedProminent)
            }
            .sheet(isPresented: $adding) { AddExpenseView() }
            .overlay {
                if expenses.isEmpty {
                    ContentUnavailableView(
                        "Ще нічого не записано",
                        systemImage: "hryvniasign.circle",
                        description: Text("Натисни «+» або налаштуй подвійний тап по спинці")
                    )
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Сьогодні" }
        if Calendar.current.isDateInYesterday(day) { return "Вчора" }
        return day.formatted(.dateTime.day().month(.wide))
    }
}

private struct SummaryCard: View {
    let month: Double
    let today: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Витрачено цього місяця")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Text(uah(month))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Label("сьогодні \(uah(today))", systemImage: "clock")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [.teal, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 24)
        )
    }
}

private struct CategoryBreakdown: View {
    let rows: [CategoryTotal]
    let total: Double

    var body: some View {
        VStack(spacing: 16) {
            Chart(rows) { row in
                SectorMark(angle: .value("Сума", row.total), innerRadius: .ratio(0.62), angularInset: 2)
                    .foregroundStyle(row.category.color)
                    .cornerRadius(4)
            }
            .frame(height: 170)
            .chartLegend(.hidden)
            .overlay {
                if let top = rows.first {
                    VStack(spacing: 2) {
                        Text(share(top.total))
                            .font(.title2.bold().monospacedDigit())
                        Text(top.category.title)
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
                        Text(share(row.total))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(uah(row.total)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func share(_ value: Double) -> String {
        guard total > 0 else { return "" }
        return (value / total).formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct DaySection: View {
    let title: String
    let total: Double
    let items: [Expense]
    let delete: (Expense) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(uah(total)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ForEach(items) { expense in
                ExpenseRow(expense: expense)
                    .contextMenu {
                        Button("Видалити", systemImage: "trash", role: .destructive) { delete(expense) }
                    }
                if expense.id != items.last?.id {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

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

            Text(uah(expense.amount))
                .font(.body.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
