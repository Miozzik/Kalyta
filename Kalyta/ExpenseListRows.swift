import SwiftUI

/// The heading of a day section: the day's title and its total.
struct DayHeader: View {
    /// The day's name, such as "Сьогодні" or "21 вересня".
    let title: String
    /// The sum of the day's expenses.
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
struct UndoBanner: View {
    /// Called when the person taps Undo.
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
struct ExpenseRow: View {
    /// The expense the row shows.
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.categoryIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(expense.categoryColor)
                .frame(width: 40, height: 40)
                .background(expense.categoryColor.opacity(0.15), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.note.isEmpty ? expense.categoryTitle : expense.note)
                HStack(spacing: 4) {
                    Text(expense.date, format: .dateTime.hour().minute())
                    if expense.bankID != nil {
                        Image(systemName: "building.columns")
                            .font(.caption2)
                            .imageScale(.small)
                            .accessibilityLabel("from monobank")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Income reads as money in: a plus sign and green, so it is never mistaken for spending.
            Text(verbatim: formattedHryvnias(expense.amount, showsPlus: expense.isIncome))
                .foregroundStyle(expense.isIncome ? Color.green : Color.primary)
                .font(.body.weight(.medium))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
