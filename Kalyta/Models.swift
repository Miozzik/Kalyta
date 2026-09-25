import Foundation
import SwiftData
import SwiftUI

/// The built-in categories, as the first release stored them.
///
/// Stores from that release hold these values directly, so the cases and raw values
/// must never change. Each built-in also exists as an ``ExpenseCategory`` record
/// whose key is the raw value.
enum Category: String, Codable, CaseIterable, Identifiable {
    // New built-ins go at the end: a store's sort order for a built-in is its index here.
    case food, transport, home, health, fun, other, income, transfers

    var id: String { rawValue }

    /// The localized name shown in the interface.
    var title: String {
        switch self {
        case .food: String(localized: "Food")
        case .transport: String(localized: "Transport")
        case .home: String(localized: "Home")
        case .health: String(localized: "Health")
        case .fun: String(localized: "Entertainment")
        case .other: String(localized: "Other")
        case .income: String(localized: "Income")
        case .transfers: String(localized: "Transfers")
        }
    }

    /// The SF Symbol name used for the category icon.
    var icon: String {
        switch self {
        case .food: "fork.knife"
        case .transport: "bus.fill"
        case .home: "house.fill"
        case .health: "cross.case.fill"
        case .fun: "gamecontroller.fill"
        case .other: "ellipsis.circle.fill"
        case .income: "banknote.fill"
        case .transfers: "arrow.left.arrow.right"
        }
    }

    /// The palette colour a new store gives the built-in.
    var defaultColor: CategoryColor {
        switch self {
        case .food: .orange
        case .transport: .blue
        case .home: .purple
        case .health: .pink
        case .fun: .green
        case .other: .gray
        case .income: .green
        case .transfers: .teal
        }
    }
}

/// The colours a category can have: system colours, so they adapt to dark mode.
///
/// A fixed palette keeps the donut readable; a free colour picker allows two nearly
/// identical blues side by side.
enum CategoryColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    var id: String { rawValue }

    /// The colour's name for VoiceOver.
    var title: LocalizedStringResource {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .mint: "Mint"
        case .teal: "Teal"
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .brown: "Brown"
        case .gray: "Grey"
        }
    }

    /// The SwiftUI colour of the palette entry.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

/// The SF Symbols a person can pick for a category, grouped roughly by theme.
enum CategorySymbols {
    static let all = [
        "fork.knife", "cup.and.saucer.fill", "cart.fill", "basket.fill", "takeoutbag.and.cup.and.straw.fill",
        "bus.fill", "car.fill", "fuelpump.fill", "tram.fill", "airplane", "bicycle",
        "house.fill", "bolt.fill", "drop.fill", "wifi", "wrench.and.screwdriver.fill", "sofa.fill",
        "cross.case.fill", "pills.fill", "heart.fill", "figure.run", "dumbbell.fill",
        "gamecontroller.fill", "film.fill", "music.note", "book.fill", "ticket.fill", "paintpalette.fill",
        "tshirt.fill", "bag.fill", "gift.fill", "pawprint.fill", "leaf.fill", "graduationcap.fill",
        "iphone", "desktopcomputer", "creditcard.fill", "banknote.fill", "briefcase.fill", "ellipsis.circle.fill",
    ]
}

extension ExpenseCategory {
    /// The name shown in the interface: the person's name, or the built-in's localized one.
    var title: String {
        if let customName, !customName.isEmpty { return customName }
        return Category(rawValue: key)?.title ?? key
    }

    /// The SF Symbol name of the icon.
    var icon: String { symbol }

    /// The colour of the icon, chart sector and legend dot.
    var color: Color { (CategoryColor(rawValue: colorName) ?? .gray).color }

    /// Whether this is one of the built-in categories rather than one the person created.
    var isBuiltIn: Bool { Category(rawValue: key) != nil }

    /// Whether the person may hide it. "Other" always stays: Back Tap entries without a
    /// category land there. "Income" stays too: hiding it would leave income nowhere to go.
    var canHide: Bool { key != Category.other.rawValue && key != Category.income.rawValue }

    /// Whether the person may delete it for good: only custom categories without expenses.
    /// A used category is hidden instead, so past months keep their categories.
    var canDelete: Bool { !isBuiltIn && expenses.isEmpty }
}

extension Expense {
    /// The name of the expense's category, falling back to the legacy value until relinked.
    var categoryTitle: String { assignedCategory?.title ?? legacyCategory.title }

    /// The icon of the expense's category.
    var categoryIcon: String { assignedCategory?.icon ?? legacyCategory.icon }

    /// The colour of the expense's category.
    var categoryColor: Color { assignedCategory?.color ?? legacyCategory.defaultColor.color }
}

/// The app's persistent storage.
enum Store {
    /// The single model container shared by the interface and the App Intent.
    ///
    /// Both must use the same container: if the intent opened its own, an expense
    /// recorded through Back Tap would be saved but never appear in the list.
    static let container: ModelContainer = {
        do {
            let container = try makeContainer()
            // Before anything reads the store: entries a stage 14 build left in the App Group come back.
            StoreMerge.mergeGroupStoreIfPresent(into: container)
            // The notification center keeps a block observer registered for the life of the process.
            TodayTotal.observeSaves(of: container)
            return container
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
    }()

    /// Creates a container on the current schema, migrating older stores.
    ///
    /// - Parameter url: The store file, or `nil` for the app's default location.
    /// - Returns: A container whose stores use ``SchemaV5``.
    /// - Throws: An error if the store cannot be opened or migrated.
    static func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV5.self)
        // `.none`: the default (`.automatic`) moves the store into the App Group once the app has
        // one, and an updated iPhone would open an empty store instead of the person's data.
        let configuration =
            url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, groupContainer: .none)
        return try ModelContainer(for: schema, migrationPlan: KalytaMigrationPlan.self, configurations: configuration)
    }

    /// Creates the built-in categories that are missing and links every expense
    /// without a category to the record matching its legacy value.
    ///
    /// Idempotent and cheap once done, so it runs at every launch: a fresh install has
    /// no migration to hook into, and a relink cut short by a killed app finishes on
    /// the next start.
    ///
    /// - Parameter context: The context to update and save.
    /// - Throws: An error if fetching or saving fails.
    static func ensureCategories(in context: ModelContext) throws {
        var byKey = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<ExpenseCategory>()).map { ($0.key, $0) })
        for (index, builtIn) in Category.allCases.enumerated() where byKey[builtIn.rawValue] == nil {
            let record = ExpenseCategory(
                key: builtIn.rawValue, customName: nil, symbol: builtIn.icon,
                colorName: builtIn.defaultColor.rawValue, sortOrder: index, isIncome: builtIn == .income)
            context.insert(record)
            byKey[builtIn.rawValue] = record
        }
        let unlinked = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.assignedCategory == nil }))
        for expense in unlinked {
            expense.assignedCategory = byKey[expense.legacyCategory.rawValue]
        }
        if context.hasChanges { try context.save() }
    }

    /// Returns the category an expense recorded with `key` goes into.
    ///
    /// A missing key (the Shortcuts parameter left empty) or one that no longer exists
    /// falls back to "Other", so an old or broken shortcut still records instead of failing.
    ///
    /// - Parameters:
    ///   - key: The key the caller asked for, or `nil`.
    ///   - context: The context to search; the built-ins must exist in it.
    /// - Returns: The matching category, or "Other".
    static func category(forKey key: String?, in context: ModelContext) -> ExpenseCategory {
        key.flatMap { category(withKey: $0, in: context) } ?? category(withKey: Category.other.rawValue, in: context)!
    }

    /// How far apart two records of one purchase may be, such as a card payment and its receipt.
    static let purchaseMatchWindow: TimeInterval = 30 * 60

    /// Returns the recorded expense that is most likely the same purchase.
    ///
    /// The Wallet "Transaction" automation records a card payment the moment it happens, so
    /// the same amount within ``purchaseMatchWindow`` is the same purchase; the closest one wins.
    ///
    /// - Parameters:
    ///   - amount: The purchase amount in hryvnias.
    ///   - date: When the purchase happened.
    ///   - unlinkedOnly: Whether to skip entries a bank sync already linked to a transaction,
    ///     so two bank payments never merge into one entry.
    ///   - context: The context to search.
    /// - Returns: The matching expense, or `nil` if this is a new purchase.
    static func matchingExpense(
        amount: Double, date: Date, unlinkedOnly: Bool = false, in context: ModelContext
    ) -> Expense? {
        let start = date.addingTimeInterval(-purchaseMatchWindow)
        let end = date.addingTimeInterval(purchaseMatchWindow)
        // Amounts are doubles, so they are compared within half a kopiyka, never with `==`.
        let low = amount - 0.005
        let high = amount + 0.005
        let candidates = try? context.fetch(
            FetchDescriptor<Expense>(
                predicate: #Predicate {
                    !$0.isIncome && $0.date >= start && $0.date <= end && $0.amount > low && $0.amount < high
                }))
        return candidates?.filter { !unlinkedOnly || $0.bankID == nil }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// Returns the category record with a key, such as "other".
    ///
    /// - Parameters:
    ///   - key: The stable key.
    ///   - context: The context to search.
    /// - Returns: The record, or `nil` if there is none.
    static func category(withKey key: String, in context: ModelContext) -> ExpenseCategory? {
        try? context.fetch(FetchDescriptor<ExpenseCategory>(predicate: #Predicate { $0.key == key })).first
    }
}

/// The largest amount one entry may hold, in hryvnias.
///
/// Anything larger is a typo or a crafted input; the bound also keeps every sum of
/// entries finite, which `Double.isFinite` alone does not (two times `1e308` is infinity).
let maximumAmount: Double = 10_000_000

/// Returns whether an amount can be recorded: finite, positive and at most ``maximumAmount``.
///
/// - Parameter amount: The amount to check.
/// - Returns: `true` if the amount is valid.
func isValidAmount(_ amount: Double) -> Bool {
    amount.isFinite && amount > 0 && amount <= maximumAmount
}

/// The longest note an automatic source may store, in characters.
///
/// A note is a merchant name, but an automation or a bank can pass any text.
let maximumNoteLength = 1_000
