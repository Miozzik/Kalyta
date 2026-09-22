import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var adding = false

    private var monthTotal: Double {
        let from = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        return expenses.filter { $0.date >= from }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Цього місяця", value: uah(monthTotal))
                        .font(.title3.bold())
                }
                ForEach(expenses) { e in
                    HStack {
                        Image(systemName: e.category.icon)
                            .frame(width: 28)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(e.note.isEmpty ? e.category.title : e.note)
                            Text(e.date, format: .dateTime.day().month().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(uah(e.amount)).monospacedDigit()
                    }
                }
                .onDelete { $0.forEach { context.delete(expenses[$0]) } }
            }
            .navigationTitle("Skarbo")
            .toolbar {
                Button("Додати", systemImage: "plus") { adding = true }
            }
            .sheet(isPresented: $adding) { AddExpenseView() }
            .overlay {
                if expenses.isEmpty {
                    ContentUnavailableView("Ще нічого не записано", systemImage: "hryvniasign.circle")
                }
            }
        }
    }
}

struct AddExpenseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double?
    @State private var category: Category = .food
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Сума", value: $amount, format: .number)
                    .keyboardType(.decimalPad)
                    .font(.largeTitle.bold())
                Picker("Категорія", selection: $category) {
                    ForEach(Category.allCases) { c in
                        Label(c.title, systemImage: c.icon).tag(c)
                    }
                }
                TextField("Нотатка", text: $note)
            }
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
                    .disabled((amount ?? 0) <= 0)
                }
            }
        }
    }
}
