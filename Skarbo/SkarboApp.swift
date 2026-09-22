import SwiftUI
import SwiftData

@main
struct SkarboApp: App {
    init() { if CommandLine.arguments.contains("--selfcheck") { MainActor.assumeIsolated { selfCheck() } } }

    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(Store.container)
    }
}

/// Доводить, що запис через Store.container (шлях App Intent / Back Tap)
/// читається тим самим запитом, яким його бачить список на екрані.
/// Запуск: xcrun simctl launch <sim> org.merzlov.skarbo --selfcheck
@MainActor
private func selfCheck() {
    let context = Store.container.mainContext
    // Прибрати хвости від попереднього прогону, інакше впалий прогін ламає наступний.
    try! context.delete(model: Expense.self, where: #Predicate { $0.note == "selfcheck" })

    let probe = Expense(amount: 42.5, category: .food, note: "selfcheck")
    context.insert(probe)
    try! context.save()

    let found = try! context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.note == "selfcheck" }))
    assert(found.count == 1, "витрата не дочиталась із контейнера")
    assert(found[0].amount == 42.5 && found[0].category == .food, "поля побились при збереженні")
    // Тільки цифри: форматер ставить нерозривний пробіл і залежить від локалі,
    // тому порівнювати з готовим рядком "42,50 ₴" не можна.
    assert(uah(42.5).filter(\.isNumber) == "4250", "копійки загубились: \(uah(42.5))")
    assert(uah(100).filter(\.isNumber) == "100", "цілі суми не мають тягти копійки: \(uah(100))")

    context.delete(probe)
    try! context.save()
    print("SELFCHECK OK")
    exit(0)  // інакше застосунок лишається жити і тримає консоль запуску
}
