import SwiftData
import SwiftUI

/// The app entry point.
///
/// Two launch arguments exist for development:
/// - `--selfcheck` runs ``runSelfCheck()`` and exits.
/// - `--demo` replaces all expenses with sample data for screenshots.
@main
struct KalytaApp: App {
    init() {
        if CommandLine.arguments.contains("--selfcheck") { MainActor.assumeIsolated { runSelfCheck() } }
        if CommandLine.arguments.contains("--demo") { MainActor.assumeIsolated { seedDemoData() } }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(Store.container)
    }
}

/// Verifies the logic most likely to break silently, then exits the process.
///
/// Checks that an expense written through ``Store/container`` (the App Intent
/// path) is read back by the same query the list uses, that amounts are
/// formatted correctly, and that periods tile time without gaps or overlaps.
/// A failed check stops the app on an assertion that names the problem.
///
/// Run it with `xcrun simctl launch --console-pty <device> org.merzlov.kalyta --selfcheck`.
@MainActor
private func runSelfCheck() {
    let context = Store.container.mainContext
    // Remove leftovers from a previous run that crashed before cleaning up,
    // otherwise every later run would fail on the count check.
    try! context.delete(model: Expense.self, where: #Predicate { $0.note == "selfcheck" })

    let probe = Expense(amount: 42.5, category: .food, note: "selfcheck")
    context.insert(probe)
    try! context.save()

    let probeQuery = FetchDescriptor<Expense>(predicate: #Predicate { $0.note == "selfcheck" })
    let found = try! context.fetch(probeQuery)
    assert(found.count == 1, "The expense was not read back from the shared container")
    assert(found[0].amount == 42.5 && found[0].category == .food, "Expense fields changed on save")

    // Compare digits only: the formatter inserts a non-breaking space and depends
    // on the locale, so comparing with a literal such as "42,50 ₴" is unreliable.
    assert(formattedHryvnias(42.5).filter(\.isNumber) == "4250", "Kopiykas were dropped: \(formattedHryvnias(42.5))")
    assert(
        formattedHryvnias(100).filter(\.isNumber) == "100", "Whole amounts gained kopiykas: \(formattedHryvnias(100))")

    // CSV export: a note that needs quoting, a large amount, and a known moment
    // (2026-09-23 09:18 UTC) written in Kyiv time.
    let exportedNote = "He said \"hi\", ok\nnext"
    let record = ExpenseRecord(
        date: Date(timeIntervalSince1970: 1_790_155_080), amount: 1_234_567.89,
        categoryKey: "food", categoryName: "Їжа", note: exportedNote)
    let csv = ExpenseCSV.document(for: [record], timeZone: TimeZone(identifier: "Europe/Kyiv")!)
    let csvLines = csv.components(separatedBy: "\r\n")
    assert(csvLines.first == "date,amount,currency,category,category_name,note", "CSV header changed: \(csvLines[0])")
    assert(csv.hasSuffix("\r\n") && csvLines.count == 3, "CSV records must end in CRLF")
    assert(csvLines[1].hasPrefix("2026-09-23T12:18:00+03:00,"), "CSV date not in local time: \(csvLines[1])")
    assert(csvLines[1].contains(",1234567.89,UAH,food,Їжа,"), "CSV amount not plain with a dot: \(csvLines[1])")
    assert(
        csvLines[1].hasSuffix(",\"He said \"\"hi\"\", ok\nnext\""), "CSV note not quoted per RFC 4180: \(csvLines[1])")
    assert(ExpenseCSV.field("plain") == "plain", "A plain field must not be quoted")

    for period in Period.allCases {
        let intervals = period.intervals()
        assert(intervals.count == 6, "\(period): expected 6 intervals, got \(intervals.count)")
        assert(intervals.last!.containsExcludingEnd(.now), "\(period): the last interval does not contain now")
        for (earlier, later) in zip(intervals, intervals.dropFirst()) {
            assert(earlier.end == later.start, "\(period): gap or overlap between \(earlier) and \(later)")
            // An expense at the exact boundary belongs to the later period only.
            assert(!earlier.containsExcludingEnd(later.start), "\(period): boundary counted in the earlier period")
            assert(later.containsExcludingEnd(later.start), "\(period): boundary missing from the later period")
        }
    }

    context.delete(probe)
    try! context.save()
    assert(try! context.fetchCount(probeQuery) == 0, "The expense was not deleted")

    try! context.delete(model: Expense.self, where: #Predicate { $0.note == "selfcheck" })
    try! context.save()
    print("SELFCHECK OK")
    exit(0)  // Without this the app keeps running and holds the launching console open.
}

/// Replaces all expenses with sample data spread over the last week.
///
/// The optional `-demoOffsetDays <n>` argument moves every sample `n` days further
/// back, so tests can reproduce dates near a month boundary on any calendar day.
///
/// Run it with `xcrun simctl launch <device> org.merzlov.kalyta --demo`.
@MainActor
private func seedDemoData() {
    // Launch arguments in "-key value" form are readable through the argument domain of UserDefaults.
    let offsetDays = UserDefaults.standard.integer(forKey: "demoOffsetDays")
    let context = Store.container.mainContext
    try! context.delete(model: Expense.self)

    let samples: [(amount: Double, category: Category, note: String, daysAgo: Int)] = [
        (248.90, .food, "АТБ", 0), (65, .transport, "Метро", 0), (120, .fun, "Кава з Оксаною", 0),
        (1450, .home, "Комуналка", 1), (89.50, .food, "Пекарня", 1), (320, .health, "Аптека", 2),
        (540, .food, "Сільпо", 3), (200, .transport, "Таксі", 4), (99, .fun, "Підписка", 6),
    ]
    for sample in samples {
        let date = Calendar.current.date(byAdding: .day, value: -(sample.daysAgo + offsetDays), to: .now)!
        context.insert(Expense(amount: sample.amount, category: sample.category, note: sample.note, date: date))
    }
    try! context.save()
}
