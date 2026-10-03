import Foundation
import SwiftData

/// Verifies the JSON backup: only whitelisted fields and never the token, a full round trip,
/// refused files, skipped items, and that a restore only inserts. Uses in-memory stores.
@MainActor
func runBackupCheck() {
    let day = Date(timeIntervalSince1970: 1_790_155_080.75)  // 2026-09-23, with a fraction of a second
    let source = emptyBackupStore()
    let food = Store.category(withKey: "food", in: source)!
    food.customName = "Їжа й кава"
    food.symbol = "cart.fill"
    food.colorName = "red"
    food.sortOrder = 30
    let fun = Store.category(withKey: "fun", in: source)!
    fun.isHidden = true
    let cafe = ExpenseCategory(
        key: "7F1C-backup", customName: "Кафе, бари", symbol: "cup.and.saucer.fill", colorName: "brown", sortOrder: 12,
        isIncome: true)
    cafe.isHidden = true
    source.insert(cafe)
    source.insert(Expense(amount: 248.9, category: food, note: "АТБ", date: day, bankID: "mono-1"))
    let foreign = Expense(
        amount: 4_497.29, category: cafe, note: "Переказ від Олени", date: day.addingTimeInterval(3_600),
        isIncome: true)
    foreign.originalAmount = 100
    foreign.currencyCode = "USD"
    foreign.rate = 44.9729
    foreign.isRateEstimated = true
    source.insert(foreign)
    let netflix = Subscription(
        name: "Netflix", amount: 299, period: .yearly, firstChargeDate: day.addingTimeInterval(-86_400),
        categoryKey: "fun")
    netflix.key = "sub-key-1"
    netflix.colorName = "indigo"
    netflix.iconData = Data([1, 2, 3])
    netflix.iconSlugTried = "netflix"
    source.insert(netflix)
    try! source.save()

    // The token sits in the Keychain while exporting and must not reach the file.
    let token = "uSelfcheckFixtureToken0123456789abcdefABCDEF"
    let previousToken = MonobankToken.read()
    assert(MonobankToken.save(token), "The fixture token was not stored, so the check would prove nothing")
    let exported = try! Backup.snapshot(of: source, now: day)
    let data = try! exported.encoded()
    if let previousToken { MonobankToken.save(previousToken) } else { MonobankToken.delete() }
    let text = String(decoding: data, as: UTF8.self)
    assert(!text.contains(token), "The backup contains the monobank token")

    // Only the whitelisted fields; the fixture sets every one, so each must be present.
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    func keys(_ list: String) -> Set<String> { Set((json[list] as! [[String: Any]]).flatMap(\.keys)) }
    assert(
        Set(json.keys) == ["format", "version", "exportedAt", "entries", "categories", "subscriptions"],
        "Top-level fields: \(json.keys.sorted())")
    assert(
        keys("entries") == [
            "date", "amount", "categoryKey", "note", "isIncome", "bankID", "originalAmount", "currencyCode", "rate",
            "isRateEstimated",
        ], "Entry fields: \(keys("entries").sorted())")
    assert(
        keys("categories") == ["key", "customName", "symbol", "colorName", "isHidden", "sortOrder", "isIncome"],
        "Category fields: \(keys("categories").sorted())")
    assert(
        keys("subscriptions") == ["key", "name", "amount", "period", "firstChargeDate", "categoryKey", "colorName"],
        "Subscription fields: \(keys("subscriptions").sorted())")
    assert(json["format"] as? String == "kalyta-backup" && json["version"] as? Int == 1, "Wrong format or version")

    // Round trip into an empty app: every field comes back (dates to the whole second, as ISO 8601 writes them).
    let target = emptyBackupStore()
    let first = restore(text, into: target)
    assert(first.isEmptyApp && first.builtInUpdates.map(\.key).sorted() == ["food", "fun"], "Empty-app rule: \(first)")
    let restored = try! Backup.snapshot(of: target, now: day)
    var expected = exported
    func wholeSecond(_ date: Date) -> Date { Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)) }
    for index in expected.entries.indices { expected.entries[index].date = wholeSecond(expected.entries[index].date) }
    for index in expected.subscriptions.indices {
        expected.subscriptions[index].firstChargeDate = wholeSecond(expected.subscriptions[index].firstChargeDate)
    }
    assert(Set(restored.entries) == Set(expected.entries), "Entries changed in the round trip: \(restored.entries)")
    assert(Set(restored.categories) == Set(expected.categories), "Categories changed: \(restored.categories)")
    assert(
        Set(restored.subscriptions) == Set(expected.subscriptions), "Subscriptions changed: \(restored.subscriptions)")
    assert(
        try! target.fetch(FetchDescriptor<Subscription>()).map(\.key) == ["sub-key-1"],
        "A restored subscription lost its key")

    // Restoring the same file again inserts nothing and changes nothing, in the copy and in the original.
    let again = restore(text, into: target)
    assert(
        again.isEmpty && again.knownEntries == 2 && again.knownCategories == 9 && again.knownSubscriptions == 1,
        "A second restore planned changes: \(again)")
    let afterAgain = try! Backup.snapshot(of: target, now: day)
    assert(afterAgain.entries == restored.entries, "A second restore changed entries")
    assert(afterAgain.categories == restored.categories, "A second restore changed categories")
    assert(afterAgain.subscriptions == restored.subscriptions, "A second restore changed subscriptions")
    let intoSource = BackupRestore.plan(try! Backup.decode(text), local: try! BackupLocal(source))
    assert(intoSource.isEmpty && intoSource.knownEntries == 2, "Restoring into the original adds: \(intoSource)")

    // A bank id already here is a duplicate, however the entry changed since; the app is not empty,
    // so the built-ins keep this phone's values.
    let synced = emptyBackupStore()
    synced.insert(
        Expense(amount: 1, category: Store.category(forKey: nil, in: synced), note: "edited", bankID: "mono-1"))
    try! synced.save()
    let syncedBefore = try! Backup.snapshot(of: synced, now: day)
    let bankPlan = restore(text, into: synced)
    assert(
        bankPlan.knownEntries == 1 && bankPlan.entries.map(\.bankID) == [nil],
        "A known bank id was not a duplicate: \(bankPlan)")
    assert(!bankPlan.isEmptyApp && bankPlan.builtInUpdates.isEmpty, "The empty-app rule fired with entries here")
    let syncedAfter = try! Backup.snapshot(of: synced, now: day)
    assert(
        syncedBefore.categories.allSatisfy(syncedAfter.categories.contains)
            && syncedBefore.entries.allSatisfy(syncedAfter.entries.contains),
        "A restore changed an existing object")

    // A subscription alone also makes the app not empty.
    let subscribed = emptyBackupStore()
    subscribed.insert(
        Subscription(name: "Spotify", amount: 99, period: .monthly, firstChargeDate: day, categoryKey: "fun"))
    try! subscribed.save()
    let subscribedPlan = BackupRestore.plan(try! Backup.decode(text), local: try! BackupLocal(subscribed))
    assert(subscribedPlan.builtInUpdates.isEmpty, "The empty-app rule fired with a subscription here")

    runBackupRefusalCheck(json)
}

/// Opens an empty in-memory store with the built-in categories.
@MainActor
private func emptyBackupStore() -> ModelContext {
    let schema = Schema(versionedSchema: SchemaV6.self)
    let context = ModelContext(
        try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    )
    try! Store.ensureCategories(in: context)
    return context
}

/// Plans and writes a restore of `text`, as the Backup screen does.
@MainActor
@discardableResult
private func restore(_ text: String, into context: ModelContext) -> BackupPlan {
    let plan = BackupRestore.plan(try! Backup.decode(text), local: try! BackupLocal(context))
    try! BackupRestore.apply(plan, in: context)
    return plan
}

/// Files refused whole, and single items skipped and counted.
///
/// - Parameter json: A valid backup to vary.
@MainActor
private func runBackupRefusalCheck(_ json: [String: Any]) {
    func varied(_ change: (inout [String: Any]) -> Void) -> String {
        var copy = json
        change(&copy)
        return String(decoding: try! JSONSerialization.data(withJSONObject: copy), as: UTF8.self)
    }
    func refusal(_ text: String) -> ImportError? {
        do {
            _ = try Backup.decode(text)
            return nil
        } catch {
            return error as? ImportError
        }
    }
    assert(refusal(varied { $0["version"] = 2 }) == .newerBackup, "Version 2 was not refused")
    assert(refusal(varied { $0["format"] = "other-app" }) == .notKalytaExport, "A wrong format was not refused")
    assert(refusal("{\"format\": \"kalyta-backup\",") == .notKalytaExport, "Malformed JSON was not refused")
    assert(
        refusal(varied { $0["entries"] = Array(repeating: [String: Any](), count: Backup.maximumEntries + 1) })
            == .tooLarge, "Too many entries were not refused")
    assert(
        refusal(varied { $0["subscriptions"] = Array(repeating: [String: Any](), count: Backup.maximumOthers + 1) })
            == .tooLarge, "Too many subscriptions were not refused")

    // Each bad item is skipped and counted; the good ones stay.
    let entries = json["entries"] as! [[String: Any]]
    let categories = json["categories"] as! [[String: Any]]
    let good = entries[0]
    func entry(_ key: String, _ value: Any) -> [String: Any] { good.merging([key: value]) { _, new in new } }
    let text = varied {
        $0["entries"] =
            entries + [
                entry("amount", -1), entry("amount", "12"), entry("date", "1990-01-01T00:00:00Z"),
                entry("note", String(repeating: "x", count: maximumNoteLength + 1)), entry("categoryKey", "nowhere"),
                entry("currencyCode", "usd"),
            ]
        $0["categories"] =
            categories + [
                categories[0],
                [
                    "key": "new-one", "symbol": "no.such.symbol", "colorName": "plaid", "isHidden": false,
                    "sortOrder": 40, "isIncome": false,
                ],
            ]
    }
    let plan = BackupRestore.plan(try! Backup.decode(text), local: try! BackupLocal(emptyBackupStore()))
    assert(plan.invalidCount == 7 && plan.entries.count == 2, "Bad items were not skipped one by one: \(plan)")
    let fallback = plan.categories.first { $0.key == "new-one" }
    assert(
        fallback?.symbol == CategorySymbols.all[0]
            && fallback.map { CategoryColor(rawValue: $0.colorName) != nil } == true,
        "An unknown icon or colour was kept: \(fallback as Any)")
}
