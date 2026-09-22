import Foundation
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

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Категорія" }

    static var caseDisplayRepresentations: [Category: DisplayRepresentation] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, DisplayRepresentation(title: "\($0.title)", image: .init(systemName: $0.icon))) })
    }
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

func uah(_ value: Double) -> String {
    value.formatted(.currency(code: "UAH").precision(.fractionLength(0...2)))
}
