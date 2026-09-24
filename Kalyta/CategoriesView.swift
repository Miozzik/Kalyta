import SwiftData
import SwiftUI

/// The list of categories, where they are created, edited, hidden and deleted.
struct CategoriesView: View {
    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]
    /// The category open in the editor, or `nil` when none is being edited.
    @State private var editing: ExpenseCategory?
    @State private var isCreating = false

    var body: some View {
        List {
            Section {
                ForEach(categories.filter { !$0.isHidden && !$0.isIncome }) { row(for: $0) }
            }
            Section("Income") {
                ForEach(categories.filter { !$0.isHidden && $0.isIncome }) { row(for: $0) }
            }
            let hidden = categories.filter(\.isHidden)
            if !hidden.isEmpty {
                Section("Hidden") {
                    ForEach(hidden) { row(for: $0) }
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            Button("New Category", systemImage: "plus") { isCreating = true }
        }
        .sheet(item: $editing) { CategoryEditor(category: $0) }
        .sheet(isPresented: $isCreating) { CategoryEditor() }
    }

    /// Returns a row that opens the category in the editor.
    ///
    /// - Parameter category: The category the row shows.
    private func row(for category: ExpenseCategory) -> some View {
        Button {
            editing = category
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .foregroundStyle(category.color)
                    .frame(width: 36, height: 36)
                    .background(category.color.opacity(0.15), in: .circle)
                Text(category.title)
                Spacer()
                Text(category.expenses.count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.primary)
    }
}

/// The sheet for creating a category or editing an existing one.
///
/// Like the expense editor, it edits copies and writes them back only on Save.
struct CategoryEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]

    /// The category being edited, or `nil` when creating one.
    private let category: ExpenseCategory?
    /// Called with the new category after it is created.
    private let onCreate: ((ExpenseCategory) -> Void)?
    /// Whether a new category is for income; an edited one keeps its kind.
    private let isIncome: Bool

    @State private var name: String
    @State private var symbol: String
    @State private var color: CategoryColor
    @State private var isHidden: Bool

    /// Creates the sheet for a new category, or for editing `category`.
    ///
    /// - Parameters:
    ///   - category: The category to edit, or `nil` to create one.
    ///   - isIncome: Whether a new category is for income.
    ///   - onCreate: Called with the created category, so the caller can select it.
    init(category: ExpenseCategory? = nil, isIncome: Bool = false, onCreate: ((ExpenseCategory) -> Void)? = nil) {
        self.category = category
        self.isIncome = category?.isIncome ?? isIncome
        self.onCreate = onCreate
        _name = State(initialValue: category?.customName ?? "")
        _symbol = State(initialValue: category?.symbol ?? CategorySymbols.all[0])
        _color = State(initialValue: category.flatMap { CategoryColor(rawValue: $0.colorName) } ?? .blue)
        _isHidden = State(initialValue: category?.isHidden ?? false)
    }

    /// The name shown when the field is empty: a built-in's own name, or a hint.
    private var namePlaceholder: String {
        category.flatMap { Category(rawValue: $0.key)?.title } ?? String(localized: "Name")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A custom category needs a name; a built-in may keep its own.
    private var canSave: Bool { category?.isBuiltIn == true || !trimmedName.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(namePlaceholder, text: $name)
                        .accessibilityIdentifier("categoryName")
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CategorySymbols.all, id: \.self) { item in
                            Button {
                                symbol = item
                            } label: {
                                Image(systemName: item)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(item == symbol ? .white : color.color)
                                    .background(item == symbol ? color.color : color.color.opacity(0.15), in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item)
                            .accessibilityAddTraits(item == symbol ? .isSelected : [])
                        }
                    }
                }
                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                        ForEach(CategoryColor.allCases) { item in
                            Button {
                                color = item
                            } label: {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if item == color { Image(systemName: "checkmark").foregroundStyle(.white) }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.rawValue)
                            .accessibilityAddTraits(item == color ? .isSelected : [])
                        }
                    }
                }
                if let category {
                    Section {
                        if category.canHide {
                            Toggle("Hide", isOn: $isHidden)
                        }
                        if category.canDelete {
                            Button("Delete Category", role: .destructive) {
                                context.delete(category)
                                try? context.save()
                                dismiss()
                            }
                        }
                    } footer: {
                        if !category.canDelete, category.canHide, !category.expenses.isEmpty {
                            Text("A category with expenses can only be hidden, so past months keep it.")
                        }
                    }
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
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
        }
    }

    /// Writes the fields to the edited category, or creates a new one, and closes the sheet.
    private func save() {
        let customName = trimmedName.isEmpty ? nil : trimmedName
        if let category {
            category.customName = customName
            category.symbol = symbol
            category.colorName = color.rawValue
            category.isHidden = category.canHide && isHidden
        } else {
            // A new key is made once and never changes, so renaming keeps the CSV key stable.
            let created = ExpenseCategory(
                key: UUID().uuidString, customName: customName, symbol: symbol, colorName: color.rawValue,
                sortOrder: (categories.map(\.sortOrder).max() ?? 0) + 1, isIncome: isIncome)
            context.insert(created)
            onCreate?(created)
        }
        try? context.save()
        dismiss()
    }
}
