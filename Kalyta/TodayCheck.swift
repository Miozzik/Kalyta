import Foundation
import SwiftData

/// Verifies today's total: the day's bounds, the stale-day rule, and that saving the shared
/// store publishes it for the widget even when the Shortcuts action records with no interface.
@MainActor
func runTodayCheck() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
    let dayStart = calendar.startOfDay(for: now)
    let url = FileManager.default.temporaryDirectory.appending(path: "selfcheck-today-\(UUID().uuidString).store")
    defer { removeStore(at: url) }
    let context = ModelContext(try! Store.makeContainer(url: url))
    try! Store.ensureCategories(in: context)
    let food = Store.category(withKey: "food", in: context)!
    let salary = Store.category(withKey: "income", in: context)!
    for (amount, date, isIncome) in [
        (1.0, dayStart, false), (10.0, now, false),
        (100.0, dayStart - 1, false),  // the last second of yesterday
        (1_000.0, now, true),  // income is never spending
        (10_000.0, dayStart + 86_400, false),  // the first second of tomorrow
    ] {
        context.insert(Expense(amount: amount, category: isIncome ? salary : food, date: date, isIncome: isIncome))
    }
    try! context.save()
    let entries = try! context.fetch(FetchDescriptor<Expense>())
    let total = TodayTotal.spending(of: entries, now: now, calendar: calendar)
    assert(total == 11, "Today's spending is \(total), expected 11 (midnight in, income and other days out)")

    // The widget shows 0 once the published day is over, and before anything was published.
    let suite = "selfcheck-today-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    assert(TodayTotal.storedTotal(in: defaults, now: now, calendar: calendar) == 0, "Nothing published must read as 0")
    TodayTotal.publish(from: context, to: defaults, now: now, calendar: calendar)
    let stored = TodayTotal.storedTotal(in: defaults, now: now + 3_600, calendar: calendar)
    assert(stored == 11, "The published total reads back as \(stored)")
    assert(
        TodayTotal.storedTotal(in: defaults, now: dayStart + 86_400, calendar: calendar) == 0,
        "Yesterday's total was shown after midnight")
    assert(TodayTotal.storedTotal(in: defaults, now: dayStart - 1, calendar: calendar) == 0, "A future day's total")

    // The widget's timeline: the total now, then 0 from the next midnight (DST-safe via the calendar).
    let timeline = TodayTotal.timeline(total: 11, now: now, calendar: calendar)
    assert(
        timeline.count == 2 && timeline[0] == (now, 11) && timeline[1] == (dayStart + 86_400, 0),
        "The widget timeline is wrong: \(timeline)")
    // The kind is the placed widgets' identity: the app must reload the widget that shows the total.
    assert(TodayTotal.widgetKind == "ScanReceipt", "The widget kind changed; placed widgets would disappear")

    // The hook: the Shortcuts action saves the shared store with no interface, and the widget's total follows.
    guard let shared = TodayTotal.sharedDefaults else { return assertionFailure("The App Group suite is missing") }
    shared.set(-1.0, forKey: TodayTotal.totalKey)
    shared.set(Calendar.current.startOfDay(for: .now), forKey: TodayTotal.dayStartKey)
    let intent = QuickAddExpense()
    intent.amount = 7
    intent.note = "selfcheck-today"
    _ = wait { (try? await intent.perform()) != nil }
    // The observer is called on the main queue after the save; let it run.
    RunLoop.main.run(until: .now + 0.2)
    let main = Store.container.mainContext
    let expected = TodayTotal.spending(of: try! main.fetch(FetchDescriptor<Expense>()))
    let published = TodayTotal.storedTotal(in: shared)
    deleteExpenses(where: #Predicate { $0.note == "selfcheck-today" }, in: main)
    assert(published == expected && expected >= 7, "A save by the Shortcuts action was not published: \(published)")

    // The CSV import saves on a background context of the same container; it must publish too.
    shared.set(-1.0, forKey: TodayTotal.totalKey)
    let imported = ExpenseRecord(
        date: .now, amount: 5, categoryKey: "food", categoryName: "Їжа", note: "selfcheck-today-import")
    let plan = ImportPlan(toInsert: [imported], duplicateCount: 0, invalidLines: [])
    _ = wait { (try? await ImportWriter(modelContainer: Store.container).apply(plan)) != nil }
    RunLoop.main.run(until: .now + 0.2)
    let afterImport = TodayTotal.spending(of: try! main.fetch(FetchDescriptor<Expense>()))
    let publishedImport = TodayTotal.storedTotal(in: shared)
    deleteExpenses(where: #Predicate { $0.note == "selfcheck-today-import" }, in: main)
    assert(
        publishedImport == afterImport && afterImport >= 5, "A background import was not published: \(publishedImport)")
}
