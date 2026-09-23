import AppIntents
import Foundation
import SwiftData
import SwiftUI

/// A spending category with its display title, SF Symbol, and color.
///
/// Conforms to `AppEnum` so the Shortcuts action can take a category as a parameter.
enum Category: String, Codable, CaseIterable, Identifiable, AppEnum {
    case food, transport, home, health, fun, other

    var id: String { rawValue }

    /// The localized name shown in the interface.
    var title: String {
        switch self {
        case .food: "Їжа"
        case .transport: "Транспорт"
        case .home: "Дім"
        case .health: "Здоров'я"
        case .fun: "Розваги"
        case .other: "Інше"
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
        }
    }

    /// The accent color used for the icon, chart sector, and legend dot.
    var color: Color {
        switch self {
        case .food: .orange
        case .transport: .blue
        case .home: .purple
        case .health: .pink
        case .fun: .green
        case .other: .gray
        }
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Категорія" }

    // The AppIntents metadata extractor reads this at build time and only accepts
    // a dictionary literal. Building it with `map` fails the build, so the titles
    // and icons are intentionally repeated here.
    static var caseDisplayRepresentations: [Category: DisplayRepresentation] = [
        .food: DisplayRepresentation(title: "Їжа", image: .init(systemName: "fork.knife")),
        .transport: DisplayRepresentation(title: "Транспорт", image: .init(systemName: "bus.fill")),
        .home: DisplayRepresentation(title: "Дім", image: .init(systemName: "house.fill")),
        .health: DisplayRepresentation(title: "Здоров'я", image: .init(systemName: "cross.case.fill")),
        .fun: DisplayRepresentation(title: "Розваги", image: .init(systemName: "gamecontroller.fill")),
        .other: DisplayRepresentation(title: "Інше", image: .init(systemName: "ellipsis.circle.fill")),
    ]
}

/// A single recorded expense.
@Model
final class Expense {
    /// The amount spent, in hryvnias.
    var amount: Double
    var category: Category
    /// An optional free-form description, such as the shop name.
    var note: String
    /// The moment the expense happened.
    var date: Date

    /// Creates an expense with the given amount, defaulting to the current moment.
    init(amount: Double, category: Category = .other, note: String = "", date: Date = .now) {
        self.amount = amount
        self.category = category
        self.note = note
        self.date = date
    }
}

/// The app's persistent storage.
enum Store {
    /// The single model container shared by the interface and the App Intent.
    ///
    /// Both must use the same container: if the intent opened its own, an expense
    /// recorded through Back Tap would be saved but never appear in the list.
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Expense.self)
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
    }()
}

/// Formats an amount as hryvnias, for example "42,50 ₴" or "100 ₴".
///
/// Kopiykas are shown either in full or not at all: a `0...2` precision range
/// renders 42.5 as "42,5 ₴", which reads like a typo.
///
/// - Parameter amount: The amount in hryvnias.
/// - Returns: The amount formatted in the current locale.
func formattedHryvnias(_ amount: Double) -> String {
    let fractionDigits = amount == amount.rounded() ? 0 : 2
    return amount.formatted(.currency(code: "UAH").precision(.fractionLength(fractionDigits)))
}
