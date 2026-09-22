import SwiftUI
import SwiftData

@main
struct KalytaApp: App {
    init() {
        if CommandLine.arguments.contains("--selfcheck") { MainActor.assumeIsolated { selfCheck() } }
        if CommandLine.arguments.contains("--demo") { MainActor.assumeIsolated { seedDemo() } }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(Store.container)
    }
}

/// Доводить, що запис через Store.container (шлях App Intent / Back Tap)
/// читається тим самим запитом, яким його бачить список на екрані.
/// Запуск: xcrun simctl launch <sim> org.merzlov.kalyta --selfcheck
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


/// Наповнює базу прикладами для скріншотів: xcrun simctl launch <sim> org.merzlov.kalyta --demo
@MainActor
private func seedDemo() {
    let context = Store.container.mainContext
    try! context.delete(model: Expense.self)

    let samples: [(Double, Category, String, Int)] = [
        (248.90, .food, "АТБ", 0), (65, .transport, "Метро", 0), (120, .fun, "Кава з Оксаною", 0),
        (1450, .home, "Комуналка", 1), (89.50, .food, "Пекарня", 1), (320, .health, "Аптека", 2),
        (540, .food, "Сільпо", 3), (200, .transport, "Таксі", 4), (99, .fun, "Підписка", 6),
    ]
    for (amount, category, note, daysAgo) in samples {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        context.insert(Expense(amount: amount, category: category, note: note, date: date))
    }
    try! context.save()
}