import SwiftData
import SwiftUI

/// The sheet for entering a new expense: amount, category, and an optional note.
struct AddExpenseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double?
    @State private var category: Category = .food
    @State private var note = ""
    @FocusState private var isAmountFocused: Bool

    private var canSave: Bool { (amount ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("0", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                        .multilineTextAlignment(.trailing)
                        .fixedSize()
                    Text("₴").foregroundStyle(.secondary)
                }
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(Category.allCases) { item in
                        CategoryChip(category: item, isSelected: item == category)
                            .onTapGesture { category = item }
                    }
                }

                TextField("Нотатка", text: $note)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

                Spacer()
            }
            .padding(.horizontal)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Витрата")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Скасувати") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти") {
                        guard let amount, amount > 0 else { return }
                        context.insert(Expense(amount: amount, category: category, note: note))
                        dismiss()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
            .onAppear { isAmountFocused = true }
        }
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
