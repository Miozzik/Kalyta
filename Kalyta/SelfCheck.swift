import Foundation
import SwiftData
import UIKit

/// Verifies the logic most likely to break silently, then exits the process.
///
/// Checks that an expense written through ``Store/container`` (the App Intent
/// path) is read back by the same query the list uses, that amounts are
/// formatted correctly, and that periods tile time without gaps or overlaps.
/// A failed check stops the app on an assertion that names the problem.
///
/// Run it with `xcrun simctl launch --console-pty <device> org.merzlov.kalyta --selfcheck`.
@MainActor
func runSelfCheck() {
    let context = Store.container.mainContext
    try! Store.ensureCategories(in: context)
    let food = Store.category(withKey: Category.food.rawValue, in: context)!
    // Remove leftovers from a previous run that crashed before cleaning up,
    // otherwise every later run would fail on the count check.
    deleteExpenses(where: #Predicate { $0.note == "selfcheck" }, in: context)

    let probe = Expense(amount: 42.5, category: food, note: "selfcheck")
    context.insert(probe)
    try! context.save()

    let probeQuery = FetchDescriptor<Expense>(predicate: #Predicate { $0.note == "selfcheck" })
    let found = try! context.fetch(probeQuery)
    assert(found.count == 1, "The expense was not read back from the shared container")
    assert(found[0].amount == 42.5 && found[0].assignedCategory?.key == "food", "Expense fields changed on save")

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
    assert(
        csvLines.first == "date,amount,currency,category,category_name,note,category_symbol,category_color,kind",
        "CSV header changed: \(csvLines[0])")
    assert(csv.hasSuffix("\r\n") && csvLines.count == 3, "CSV records must end in CRLF")
    assert(csvLines[1].hasPrefix("2026-09-23T12:18:00+03:00,"), "CSV date not in local time: \(csvLines[1])")
    assert(csvLines[1].contains(",1234567.89,UAH,food,Їжа,"), "CSV amount not plain with a dot: \(csvLines[1])")
    assert(
        csvLines[1].contains(",\"He said \"\"hi\"\", ok\nnext\","), "CSV note not quoted per RFC 4180: \(csvLines[1])")
    assert(ExpenseCSV.field("plain") == "plain", "A plain field must not be quoted")
    // A custom category name is typed by the person, so it can need quoting too.
    let customRecord = ExpenseRecord(
        date: record.date, amount: 1, categoryKey: "7F1C", categoryName: "Кафе, бари", note: "")
    let customLine = ExpenseCSV.document(for: [customRecord]).components(separatedBy: "\r\n")[1]
    assert(customLine.contains(",7F1C,\"Кафе, бари\","), "A custom category name was not quoted: \(customLine)")

    runMigrationCheck()
    runImportCheck()
    runStatisticsCheck()
    runSubscriptionCheck()
    runReceiptCheck()

    // The Shortcuts action: an empty or unknown category must record into "Other", never fail.
    assert(Store.category(forKey: nil, in: context).key == "other", "An empty category did not fall back to Other")
    assert(
        Store.category(forKey: "no-such-key", in: context).key == "other",
        "An unknown category did not fall back to Other")
    assert(Store.category(forKey: "food", in: context).key == "food", "A known category was not used")

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

    deleteExpenses(where: #Predicate { $0.note == "selfcheck" }, in: context)
    try! context.save()
    print("SELFCHECK OK")
    exit(0)  // Without this the app keeps running and holds the launching console open.
}

/// Replaces all data with the built-in categories and sample expenses from the last week.
///
/// The optional `-demoOffsetDays <n>` argument moves every sample `n` days further
/// back, so tests can reproduce dates near a month boundary on any calendar day.
///
/// Run it with `xcrun simctl launch <device> org.merzlov.kalyta --demo`.
@MainActor
func seedDemoData() {
    // Launch arguments in "-key value" form are readable through the argument domain of UserDefaults.
    let offsetDays = UserDefaults.standard.integer(forKey: "demoOffsetDays")
    let context = Store.container.mainContext
    deleteExpenses(where: #Predicate { _ in true }, in: context)
    // Reset categories too, so every run starts from the built-ins alone.
    for category in try! context.fetch(FetchDescriptor<ExpenseCategory>()) { context.delete(category) }
    for subscription in try! context.fetch(FetchDescriptor<Subscription>()) { context.delete(subscription) }
    try! context.save()
    try! Store.ensureCategories(in: context)

    for sample in demoSamples {
        let date = Calendar.current.date(byAdding: .day, value: -(sample.daysAgo + offsetDays), to: .now)!
        let record = Store.category(withKey: sample.category.rawValue, in: context)!
        context.insert(
            Expense(
                amount: sample.amount, category: record, note: sample.note, date: date,
                isIncome: sample.category == .income))
    }
    try! context.save()
}

/// The sample expenses of `--demo`; also what ``runUpgradeCheck()`` expects to find.
let demoSamples: [(amount: Double, category: Category, note: String, daysAgo: Int)] = [
    (248.90, .food, "АТБ", 0), (65, .transport, "Метро", 0), (120, .fun, "Кава з Оксаною", 0),
    (1450, .home, "Комуналка", 1), (89.50, .food, "Пекарня", 1), (320, .health, "Аптека", 2),
    (540, .food, "Сільпо", 3), (200, .transport, "Таксі", 4), (99, .fun, "Підписка", 6),
    // Income: if any total, chart or statistic forgets to leave it out, a test sees 5,000 too many.
    (5_000, .income, "Зарплата", 1),
]

/// Verifies that a store in the first release's shape opens on the current schema and
/// that every expense is linked to the category it had.
///
/// Writes a V1 store to a temporary file with ``SchemaV1``, reopens it through
/// ``Store/makeContainer(url:)``, and runs the launch relink on it.
@MainActor
func runMigrationCheck() {
    let url = FileManager.default.temporaryDirectory.appending(path: "selfcheck-v1-\(UUID().uuidString).store")
    defer { try? FileManager.default.removeItem(at: url) }
    do {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let v1 = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(v1)
        for (index, category) in Category.allCases.enumerated() {
            context.insert(
                SchemaV1.Expense(amount: Double(index + 1), category: category, note: category.rawValue, date: .now))
        }
        try! context.save()
    }

    let context = ModelContext(try! Store.makeContainer(url: url))
    try! Store.ensureCategories(in: context)
    let migrated = try! context.fetch(FetchDescriptor<Expense>())
    assert(migrated.count == Category.allCases.count, "Migration lost expenses: \(migrated.count)")
    for expense in migrated {
        // Each V1 expense carries its category's key in the note, so the link can be checked.
        assert(
            expense.assignedCategory?.key == expense.note,
            "Migration linked \(expense.note) to \(expense.assignedCategory?.key ?? "nil")")
    }
}

/// Verifies that the `--demo` data written by an older release survived the upgrade:
/// every sample is present once, with its amount, note and category, then exits.
///
/// Run it after installing this build over an older one that was launched with `--demo`.
@MainActor
func runUpgradeCheck() {
    let context = Store.container.mainContext
    try! Store.ensureCategories(in: context)
    let stored = try! context.fetch(FetchDescriptor<Expense>())
    // Builds before income seeded no income sample, so only the spending samples are expected.
    let expected = demoSamples.filter { $0.category != .income }
    assert(stored.count == expected.count, "Upgrade changed the number of expenses: \(stored.count)")
    assert(stored.allSatisfy { !$0.isIncome }, "Upgrade turned existing expenses into income")
    for sample in expected {
        let matches = stored.filter { $0.note == sample.note }
        assert(matches.count == 1, "Sample \(sample.note) found \(matches.count) times")
        assert(matches[0].amount == sample.amount, "Sample \(sample.note) changed amount: \(matches[0].amount)")
        assert(
            matches[0].assignedCategory?.key == sample.category.rawValue,
            "Sample \(sample.note) is in \(matches[0].assignedCategory?.key ?? "nil"), expected \(sample.category.rawValue)"
        )
    }
    print("UPGRADE OK")
    exit(0)
}

/// Deletes the matching expenses one by one.
///
/// A batch `delete(model:where:)` fails once `Expense` has a relationship with an
/// inverse ("mandatory OTO nullify inverse"), so each object is deleted individually.
///
/// - Parameters:
///   - predicate: Which expenses to delete.
///   - context: The context to delete them from.
@MainActor
func deleteExpenses(where predicate: Predicate<Expense>, in context: ModelContext) {
    for expense in try! context.fetch(FetchDescriptor(predicate: predicate)) {
        context.delete(expense)
    }
    try! context.save()
}

/// Verifies the CSV import: a round trip through export, re-importing without
/// duplicates, a byte-order mark, line endings, line numbers, and a spreadsheet re-save.
@MainActor
func runImportCheck() {
    let kyiv = TimeZone(identifier: "Europe/Kyiv")!
    let tricky = ExpenseRecord(
        date: Date(timeIntervalSince1970: 1_790_155_080), amount: 89.5, categoryKey: "food", categoryName: "Їжа",
        note: "=SUM(A1), \"quoted\"\r\nnext line", categorySymbol: "fork.knife", categoryColorName: "orange")
    let custom = ExpenseRecord(
        date: Date(timeIntervalSince1970: 1_790_158_680), amount: 1_234_567.89,
        categoryKey: "7F1C2B0E-0000-4000-8000-000000000001", categoryName: "Кафе, бари", note: "",
        categorySymbol: "cup.and.saucer.fill", categoryColorName: "brown")
    let records = [tricky, custom]
    let csv = ExpenseCSV.document(for: records, timeZone: kyiv)

    /// Plans an import, turning a refused file into an assertion that names the check.
    func plan(_ text: String, existing: [ExpenseRecord] = [], _ check: String) -> ImportPlan {
        do {
            return try ExpenseImport.plan(csv: text, existing: existing)
        } catch {
            assertionFailure("\(check): the import refused the file with \(error)")
            return ImportPlan(toInsert: [], duplicateCount: 0, invalidLines: [])
        }
    }

    let first = plan(csv, "Round trip")
    assert(first.toInsert == records, "The round trip changed the records: \(first.toInsert)")
    assert(first.duplicateCount == 0 && first.invalidLines.isEmpty, "A clean export reported problems")

    // Stored dates keep fractions of a second; the export drops them. Still a duplicate.
    let stored = records.map {
        ExpenseRecord(
            date: $0.date.addingTimeInterval(0.4), amount: $0.amount, categoryKey: $0.categoryKey,
            categoryName: $0.categoryName, note: $0.note)
    }
    let again = plan(csv, existing: stored, "Re-import")
    assert(again.toInsert.isEmpty && again.duplicateCount == records.count, "Re-importing duplicated rows: \(again)")

    let withBOM = plan("\u{FEFF}" + csv, "Byte-order mark")
    assert(withBOM.toInsert == records, "A byte-order mark broke the header")

    let lfOnly = ExpenseCSV.document(for: [custom], timeZone: kyiv).replacingOccurrences(of: "\r\n", with: "\n")
    assert(plan(lfOnly, "LF line endings").toInsert == [custom], "LF line endings were not read")

    // Header on line 1, the tricky note spans lines 2–3, the custom row is line 4: a broken row is line 5.
    let broken = csv + "not-a-date,1,UAH,food,Їжа,,fork.knife,orange\r\n"
    assert(plan(broken, "Broken row").invalidLines == [5], "Wrong line number for a broken row")

    // A repeated column name among the extras must not trap; the first column wins.
    let repeatedHeader = csv.replacingOccurrences(of: "category_color\r\n", with: "category_color,note\r\n")
    assert(plan(repeatedHeader, "Repeated column").toInsert == records, "A repeated column name changed the import")

    // Double("inf") parses and is > 0; such a row would poison every total.
    let infinite = csv + "2026-09-23T12:18:00+03:00,inf,UAH,food,Їжа,,fork.knife,orange\r\n"
    assert(plan(infinite, "Infinite amount").invalidLines == [5], "An infinite amount was accepted")
    // Amounts are capped: two rows of 1e308 would sum to infinity, and one traps the duplicate key.
    let huge = csv + "2026-09-23T12:18:00+03:00,10000000.01,UAH,food,Їжа,,fork.knife,orange\r\n"
    assert(plan(huge, "Huge amount").invalidLines == [5], "An amount above the maximum was accepted")

    // Income survives a round trip; a file from before income existed imports as spending.
    let salary = ExpenseRecord(
        date: tricky.date, amount: 5_000, categoryKey: "income", categoryName: "Дохід", note: "Зарплата",
        categorySymbol: "banknote.fill", categoryColorName: "green", isIncome: true)
    assert(
        plan(ExpenseCSV.document(for: [salary], timeZone: kyiv), "Income").toInsert == [salary], "Income lost its kind")
    let oldFormat =
        "date,amount,currency,category,category_name,note\r\n2026-09-23T12:18:00+03:00,10,UAH,food,Їжа,Хліб\r\n"
    assert(
        plan(oldFormat, "Old file").toInsert.first?.isIncome == false, "A file without kind did not import as spending")
    let badKind = csv + "2026-09-23T12:18:00+03:00,1,UAH,food,Їжа,,fork.knife,orange,refund\r\n"
    assert(plan(badKind, "Unknown kind").invalidLines == [5], "An unknown kind was accepted")
    let spendingTwin = ExpenseRecord(
        date: salary.date, amount: 5_000, categoryKey: "income", categoryName: "", note: "Зарплата")
    assert(
        !SubscriptionMath.isAlreadyRecorded(spendingTwin, among: [salary]), "Income and spending merged as duplicates")

    let spreadsheet = "date;amount;currency;category;category_name;note\r\n23.09.2026 12:18;89,5;UAH;food;Їжа;\r\n"
    assert(
        (try? ExpenseImport.plan(csv: spreadsheet, existing: [])) == nil
            && {
                do { _ = try ExpenseImport.plan(csv: spreadsheet, existing: []) } catch {
                    return error as? ImportError == .resavedBySpreadsheet
                }
                return false
            }(),
        "A file re-saved by a spreadsheet was not recognised")
}

/// Times an import of 10,000 rows into a temporary store and prints the result.
///
/// Decides whether the insert may stay on the main actor: the gate A condition is to
/// move it to a background context only if it blocks the interface for over a second.
@MainActor
func measureImport() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let records = (0..<10_000).map { index in
        ExpenseRecord(
            date: start.addingTimeInterval(Double(index) * 3_600), amount: Double(index % 500) + 0.5,
            categoryKey: Category.allCases[index % Category.allCases.count].rawValue, categoryName: "",
            note: "Row \(index), with a comma")
    }
    let csv = ExpenseCSV.document(for: records)
    let url = FileManager.default.temporaryDirectory.appending(path: "measure-\(UUID().uuidString).store")
    defer { try? FileManager.default.removeItem(at: url) }
    let context = ModelContext(try! Store.makeContainer(url: url))

    let clock = ContinuousClock()
    var plan: ImportPlan!
    let planTime = clock.measure { plan = try! ExpenseImport.plan(csv: csv, existing: []) }
    let insertTime = clock.measure { try! ExpenseImport.apply(plan, in: context) }
    print("MEASURE bytes=\(csv.utf8.count) rows=\(plan.toInsert.count) plan=\(planTime) insert=\(insertTime)")

    // Statistics: copy the stored rows once, then every aggregate over twelve months.
    let stored = try! context.fetch(FetchDescriptor<Expense>())
    var snapshot: [ExpenseRecord] = []
    let snapshotTime = clock.measure { snapshot = stored.map(ExpenseRecord.init) }
    let months = StatisticsRange.allTime.months(earliest: start)
    let aggregateTime = clock.measure {
        _ = Statistics.monthlyTotals(snapshot, months: months)
        _ = Statistics.categoryTotalsByMonth(snapshot, months: months, restName: "Rest")
        _ = Statistics.biggest(snapshot, limit: 20)
        _ = Statistics.topPlaces(snapshot, limit: 15)
    }
    print("MEASURE statistics months=\(months.count) snapshot=\(snapshotTime) aggregates=\(aggregateTime)")
    exit(0)
}

/// Verifies the Statistics aggregates on a fixed calendar and moment.
@MainActor
func runStatisticsCheck() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
    func day(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    func record(_ amount: Double, _ date: Date, key: String = "food", note: String = "") -> ExpenseRecord {
        ExpenseRecord(date: date, amount: amount, categoryKey: key, categoryName: key, note: note)
    }

    let months = StatisticsRange.sixMonths.months(earliest: nil, now: now, calendar: calendar)
    assert(months.count == 6 && months.first?.start == day(4, 1, hour: 0), "Six months must start on 1 April")

    // Midnight on 1 September belongs to September, not August.
    let boundary = [record(10, day(9, 1, hour: 0))]
    let boundaryTotals = Statistics.monthlyTotals(boundary, months: months)
    assert(boundaryTotals[5].total == 10 && boundaryTotals[4].total == 0, "A midnight expense went to the wrong month")

    let spread = [record(300, day(7, 10)), record(100, day(8, 10)), record(50, day(9, 10))]
    let average = Statistics.averageOfCompleteMonths(Statistics.monthlyTotals(spread, months: months), now: now)
    assert(average == 200, "The average must use complete months with data only: \(average ?? -1)")

    let ranked = Statistics.biggest([record(5, day(9, 1)), record(50, day(9, 2)), record(20, day(9, 3))], limit: 2)
    assert(ranked.map(\.amount) == [50, 20], "Biggest expenses are not largest first: \(ranked.map(\.amount))")

    // "Мій" and "Міи" differ only by й/и, exactly what ignoring diacritics would merge.
    let places = Statistics.topPlaces(
        [
            record(10, day(9, 1), note: "АТБ"), record(20, day(9, 2), note: "атб "), record(30, day(9, 3), note: "АТБ"),
            record(1, day(9, 4), note: "Мій"), record(2, day(9, 5), note: "Міи"), record(99, day(9, 6), note: "  "),
        ], limit: 10)
    let atb = places.first { $0.name == "АТБ" }
    assert(atb?.count == 3 && atb?.total == 60, "Spellings of one place were not grouped: \(places)")
    assert(places.count == 3, "Different Ukrainian letters were merged, or an empty note became a place: \(places)")

    // Statistics count spending only.
    let withIncome = [
        record(100, day(9, 10)),
        ExpenseRecord(
            date: day(9, 11), amount: 5_000, categoryKey: "income", categoryName: "", note: "", isIncome: true),
    ]
    assert(
        Statistics.records(withIncome, within: months).map(\.amount) == [100], "Statistics counted income as spending")

    let manyCategories = (0..<7).map { record(Double(10 + $0), day(9, 10), key: "k\($0)") }
    let segments = Statistics.categoryTotalsByMonth(manyCategories, months: months, restName: "Rest")
        .filter { $0.month == months[5] }
    assert(segments.count == Statistics.maximumCategorySegments + 1, "Categories were not folded: \(segments.count)")
    assert(segments.first { $0.categoryKey == Statistics.restKey }?.total == 21, "The rest segment has the wrong total")
}

/// Verifies subscription date arithmetic, monthly cost, icon names and avatar colours.
@MainActor
func runSubscriptionCheck() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    let jan31 = date(2026, 1, 31)
    func charge(_ index: Int, from first: Date = jan31, _ period: BillingPeriod = .monthly) -> Date {
        SubscriptionMath.chargeDate(firstCharge: first, period: period, index: index, calendar: calendar)
    }
    func charge2() -> Date { charge(1) }
    // Counting from the first charge: the 31st comes back after a short month.
    assert(charge(1) == date(2026, 2, 28) && charge(2) == date(2026, 3, 31), "Monthly charges drift after February")
    assert(charge(1, from: date(2028, 1, 31)) == date(2028, 2, 29), "A leap-year February was missed")
    assert(charge(1, from: date(2024, 2, 29), .yearly) == date(2025, 2, 28), "A yearly charge from 29 February failed")

    let next = { SubscriptionMath.nextCharge(firstCharge: jan31, period: .monthly, now: $0, calendar: calendar) }
    assert(next(date(2026, 2, 15)) == date(2026, 2, 28), "The next charge after mid-February is wrong")
    assert(next(date(2026, 3, 1)) == date(2026, 3, 31), "The next charge in March is wrong")
    assert(next(date(2026, 2, 28)) == date(2026, 2, 28), "A charge today must still be the next one")
    assert(next(date(2025, 12, 1)) == jan31, "Before the first charge, the first charge is next")
    let last = SubscriptionMath.lastCharge(
        firstCharge: jan31, period: .monthly, now: date(2026, 3, 5), calendar: calendar)
    assert(last == date(2026, 2, 28), "The charge to record in early March is wrong")

    let cost = SubscriptionMath.monthlyCost(of: [(amount: 100, period: .monthly), (amount: 1_200, period: .yearly)])
    assert(cost == 200, "A yearly plan must count as a twelfth per month: \(cost)")

    assert(SubscriptionMath.iconSlug(for: " YouTube Music ") == "youtube-music", "Slug for a two-word name")
    assert(SubscriptionMath.iconSlug(for: "Café") == "cafe", "Diacritics must fold for Latin names")
    assert(SubscriptionMath.iconSlug(for: "Київстар") == nil, "A Cyrillic name must not be looked up")

    // An offline attempt must not be remembered as "no icon", or the icon never comes.
    let png = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData { _ in }
    let found = SubscriptionIcons.classify(statusCode: 200, mimeType: "image/png", data: png)
    assert(found == .found(png) && found.isFinal, "A valid icon was not accepted")
    assert(
        SubscriptionIcons.classify(statusCode: 404, mimeType: "text/plain", data: nil).isFinal, "A 404 must be final")
    assert(!SubscriptionIcons.classify(statusCode: nil, mimeType: nil, data: nil).isFinal, "Offline must be retried")
    assert(
        !SubscriptionIcons.classify(statusCode: 503, mimeType: nil, data: nil).isFinal, "A server error must be retried"
    )
    assert(
        SubscriptionIcons.classify(statusCode: 200, mimeType: "text/html", data: Data("<html>".utf8)) == .missing,
        "A page that is not an image must not count as an icon")

    // Recording the same charge twice must be caught, despite sub-second stored dates.
    let charge = ExpenseRecord(date: jan31, amount: 199, categoryKey: "fun", categoryName: "", note: "Netflix")
    let stored = ExpenseRecord(
        date: jan31.addingTimeInterval(0.3), amount: 199, categoryKey: "fun", categoryName: "Розваги", note: "Netflix")
    assert(SubscriptionMath.isAlreadyRecorded(charge, among: [stored]), "A recorded charge was not recognised")
    let other = ExpenseRecord(date: charge2(), amount: 199, categoryKey: "fun", categoryName: "", note: "Netflix")
    assert(
        !SubscriptionMath.isAlreadyRecorded(other, among: [stored]), "The next month's charge was taken for a duplicate"
    )

    // A fixed value (sum of scalars of "megogo" mod 13 = orange, computed independently),
    // so a colour that depends on the per-process hash seed fails here.
    assert(SubscriptionMath.avatarColor(for: "Megogo") == .orange, "The avatar colour is not stable")
}
