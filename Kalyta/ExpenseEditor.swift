import SwiftData
import SwiftUI

/// The sheet for entering a new expense or editing a saved one.
///
/// The fields edit copies of the expense's values, which are written back only on
/// Save. Binding them to the model directly would let autosave persist every
/// keystroke, and Cancel could not discard the changes.
struct ExpenseEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The expense being edited, or `nil` when entering a new one.
    private let expense: Expense?
    /// Deletes the edited expense through the list's deferred deletion, so the undo banner appears.
    private let onDelete: ((Expense) -> Void)?

    @State private var amount: Double?
    @State private var category: Category
    @State private var note: String
    @State private var date: Date
    @FocusState private var isAmountFocused: Bool

    /// Creates the sheet for a new expense, or for editing `expense`.
    ///
    /// - Parameters:
    ///   - expense: The expense to edit, or `nil` to enter a new one.
    ///   - onDelete: Called with the edited expense when the person taps Delete.
    init(expense: Expense? = nil, onDelete: ((Expense) -> Void)? = nil) {
        self.expense = expense
        self.onDelete = onDelete
        _amount = State(initialValue: expense?.amount)
        _category = State(initialValue: expense?.category ?? .food)
        _note = State(initialValue: expense?.note ?? "")
        _date = State(initialValue: expense?.date ?? .now)
    }

    private var canSave: Bool { (amount ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                            .multilineTextAlignment(.trailing)
                            .fixedSize()
                            .accessibilityIdentifier("amountField")
                        Text(verbatim: "₴").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(Category.allCases) { item in
                            Button {
                                category = item
                            } label: {
                                CategoryChip(category: item, isSelected: item == category)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(item == category ? .isSelected : [])
                        }
                    }

                    VStack(spacing: 0) {
                        TextField("Note", text: $note)
                            .textFieldStyle(.plain)
                            .padding(14)
                        Divider().padding(.leading, 14)
                        // People record money already spent; a future date would inflate the current period.
                        DatePicker(
                            "Date", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute]
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

                    if let expense, let onDelete {
                        Button("Delete Expense", role: .destructive) {
                            onDelete(expense)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    }
                }
                .padding(.horizontal)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(expense == nil ? "New Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { isAmountFocused = expense == nil }
        }
    }

    /// Writes the fields to the edited expense, or inserts a new one, and closes the sheet.
    ///
    /// Saves at once instead of waiting for autosave, which runs later: an app killed
    /// right after Save would otherwise lose the expense.
    private func save() {
        guard let amount, amount > 0 else { return }
        if let expense {
            expense.amount = amount
            expense.category = category
            expense.note = note
            expense.date = date
        } else {
            context.insert(Expense(amount: amount, category: category, note: note, date: date))
        }
        try? context.save()
        dismiss()
    }
}

/// A tappable tile for one category, outlined in the category color when selected.
private struct CategoryChip: View {
    let category: Category
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: category.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? .white : category.color)
                .frame(width: 48, height: 48)
                .background(isSelected ? category.color : category.color.opacity(0.15), in: .circle)
            Text(category.title)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? category.color : .clear, lineWidth: 2)
        }
        .animation(.snappy(duration: 0.15), value: isSelected)
    }
}
