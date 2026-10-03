import Foundation
import SwiftData

/// The category the person last gave each merchant, read with a single fetch.
///
/// Build it once per batch: a bank sync records many payments, and one fetch over
/// 10,000 entries takes about 0.1 s, too long to repeat per payment.
struct MerchantMemory {
    private let categories: [String: ExpenseCategory]

    /// Reads every spending entry, newest first, and keeps the first category per place.
    ///
    /// - Parameter context: The context to read.
    /// - Complexity: O(*n*) in the number of spending entries.
    init(context: ModelContext) {
        // ponytail: reads every spending row, since a predicate cannot fold case and width the way
        // placeKey does; add a stored folded note if this gets slow.
        let spending = FetchDescriptor<Expense>(
            predicate: #Predicate { !$0.isIncome }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        var categories: [String: ExpenseCategory] = [:]
        for expense in (try? context.fetch(spending)) ?? [] {
            let place = Statistics.placeKey(expense.note)
            guard !place.isEmpty, categories[place] == nil, let category = expense.assignedCategory else { continue }
            categories[place] = category
        }
        self.categories = categories
    }

    /// Returns the category of the newest spending whose note names the same place as `note`.
    ///
    /// - Parameter note: The merchant, compared trimmed and ignoring case and width.
    /// - Returns: The remembered category, or `nil` for a merchant not seen before.
    func category(forMerchant note: String) -> ExpenseCategory? {
        categories[Statistics.placeKey(note)]
    }
}

/// Built-in categories for merchant category codes (ISO 18245) that clearly belong to one.
///
/// Only a guess for a merchant the person has not categorized yet; their own choice
/// always wins through ``MerchantMemory``.
enum MerchantCategoryCode {
    /// The built-in category for each code; codes not listed go into "Other".
    static let categories: [Int: Category] = [
        // Groceries, bakeries, restaurants, cafés and fast food.
        5411: .food, 5422: .food, 5441: .food, 5451: .food, 5462: .food, 5499: .food,
        5811: .food, 5812: .food, 5813: .food, 5814: .food,
        // Public transport, rail, taxis, buses, fuel, tolls and parking.
        4111: .transport, 4112: .transport, 4121: .transport, 4131: .transport, 4784: .transport,
        5541: .transport, 5542: .transport, 7523: .transport,
        // Pharmacies, doctors, dentists, hospitals, labs and opticians.
        5912: .health, 8011: .health, 8021: .health, 8043: .health, 8062: .health, 8071: .health, 8099: .health,
        // Utilities, telecoms, home supplies, furniture and appliances.
        4814: .home, 4899: .home, 4900: .home, 5200: .home, 5211: .home, 5251: .home, 5712: .home, 5722: .home,
        // Cinemas, events, attractions, clubs, games, digital media and books.
        5735: .fun, 5815: .fun, 5816: .fun, 5817: .fun, 5818: .fun, 5942: .fun,
        7832: .fun, 7841: .fun, 7922: .fun, 7991: .fun, 7994: .fun, 7996: .fun, 7997: .fun,
        // Money transfers to cards and people.
        Monobank.transferMCC: .transfers,
    ]
}

extension Store {
    /// Returns the category for an entry recorded without one, such as a card payment.
    ///
    /// The person's last category for the merchant wins; then the merchant category code;
    /// otherwise "Other". Used by every automatic source: the Shortcuts action and bank sync.
    ///
    /// - Parameters:
    ///   - note: The merchant, compared trimmed and ignoring case and width.
    ///   - mcc: The merchant category code, when the source has one.
    ///   - memory: A memory already read for a batch, or `nil` to read one now.
    ///   - context: The context to search; the built-ins must exist in it.
    /// - Returns: The category to record into.
    /// - Complexity: O(*n*) in the number of spending entries when `memory` is `nil`.
    static func category(
        forMerchant note: String, mcc: Int? = nil, memory: MerchantMemory? = nil, in context: ModelContext
    ) -> ExpenseCategory {
        (memory ?? MerchantMemory(context: context)).category(forMerchant: note)
            ?? mcc.flatMap { MerchantCategoryCode.categories[$0] }.flatMap {
                category(withKey: $0.rawValue, in: context)
            }
            ?? category(forKey: nil, in: context)
    }
}
