import Foundation
import SwiftUI
import SwiftData
import AppIntents

enum Category: String, Codable, CaseIterable, Identifiable, AppEnum {
    case food, transport, home, health, fun, other

    var id: String { rawValue }

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

    // Екстрактор метаданих AppIntents читає це статично — тільки буквальний словник,
    // жодних map/Dictionary(uniqueKeysWithValues:), інакше збірка падає.
    static var caseDisplayRepresentations: [Category: DisplayRepresentation] = [
        .food: DisplayRepresentation(title: "Їжа", image: .init(systemName: "fork.knife")),
        .transport: DisplayRepresentation(title: "Транспорт", image: .init(systemName: "bus.fill")),
        .home: DisplayRepresentation(title: "Дім", image: .init(systemName: "house.fill")),
        .health: DisplayRepresentation(title: "Здоров'я", image: .init(systemName: "cross.case.fill")),
        .fun: DisplayRepresentation(title: "Розваги", image: .init(systemName: "gamecontroller.fill")),
        .other: DisplayRepresentation(title: "Інше", image: .init(systemName: "ellipsis.circle.fill")),
    ]
}

@Model
final class Expense {
    var amount: Double
    var category: Category
    var note: String
    var date: Date

    init(amount: Double, category: Category = .other, note: String = "", date: Date = .now) {
        self.amount = amount
        self.category = category
        self.note = note
        self.date = date
    }
}

/// Один контейнер на застосунок і на App Intent — інтент пише в ту саму базу,
/// що й UI, інакше витрата з Back Tap просто не з'явиться у списку.
enum Store {
    static let container: ModelContainer = {
        do { return try ModelContainer(for: Expense.self) }
        catch { fatalError("SwiftData: \(error)") }
    }()
}

/// Копійки або показуємо повністю, або не показуємо зовсім:
/// діапазон 0...2 давав "42,5 ₴", що читається як зламане.
func uah(_ value: Double) -> String {
    let digits = value == value.rounded() ? 0 : 2
    return value.formatted(.currency(code: "UAH").precision(.fractionLength(digits)))
}
