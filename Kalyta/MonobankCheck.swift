import Foundation
import SwiftData

/// Verifies the monobank sync on canned JSON: validation, the sync period, paging, and how
/// statement items become entries. Uses a temporary store and `UserDefaults` suite, and no network.
@MainActor
func runMonobankCheck() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let nowSeconds = Int(now.timeIntervalSince1970)
    let start = nowSeconds - Int(Monobank.window)
    /// A statement item as the API sends it.
    func item(
        _ id: String, _ amount: Any, at time: Int = nowSeconds - 3_600, mcc: Int = 5411, hold: Bool = false,
        currency: Int = 980, description: String = "Shop"
    ) -> [String: Any] {
        [
            "id": id, "time": time, "description": description, "mcc": mcc, "originalMcc": mcc, "hold": hold,
            "amount": amount, "operationAmount": amount, "currencyCode": currency, "balance": 100,
        ]
    }
    func json(_ items: [[String: Any]]) -> Data { try! JSONSerialization.data(withJSONObject: items) }
    func page(_ items: [[String: Any]]) -> [StatementItem]? {
        try? Monobank.statementItems(from: json(items), from: start, to: nowSeconds, now: nowSeconds)
    }

    // Validation: one bad item refuses the whole page.
    assert(page([item("a1", -100)])?.count == 1, "A valid page was refused")
    // The spec marks nothing required: a missing description or hold must not stall the sync.
    var sparse = item("a1", -100)
    sparse.removeValue(forKey: "hold")
    sparse.removeValue(forKey: "description")
    assert(page([sparse])?.first.map { $0.description == "" && !$0.hold } == true, "Optional fields were required")
    assert(page([item("a1", 0)])?.count == 1, "A zero amount refused the whole page")
    // A purchase in dollars on the hryvnia card: `amount` is in hryvnias, `operationAmount` in dollars.
    var abroad = item("a1", -4_150, currency: 840)
    abroad["operationAmount"] = -100
    assert(page([abroad])?.first?.amount == -4_150, "A purchase abroad refused the page or lost its hryvnia amount")
    // Fields that can name or identify the other party are never decoded, so nothing can store them.
    var hidden = item("a1", 1_000, mcc: Monobank.transferMCC, description: "Від: Олена К.")
    for key in ["counterName", "counterIban", "counterEdrpou", "comment", "invoiceId", "receiptId"] {
        hidden[key] = "x"
    }
    let decoded = page([hidden])?.first.map { Mirror(reflecting: $0).children.compactMap(\.label) }
    assert(decoded == ["id", "time", "description", "mcc", "hold", "amount"], "Extra fields decoded: \(decoded ?? [])")
    // The account: hryvnias only, the black card first, then other cards, then FOP; ties keep the API order.
    func account(_ accounts: [[String: Any]]) -> String?? {
        // Not `try?`: it would flatten "no account" and "refused" into one `nil`.
        let body = try! JSONSerialization.data(withJSONObject: ["accounts": accounts])
        guard case .success(let id) = Result(catching: { try Monobank.hryvniaAccount(from: body) }) else { return nil }
        return .some(id)
    }
    let usd: [String: Any] = ["id": "usd", "currencyCode": 840, "type": "black"]
    let fop: [String: Any] = ["id": "fop", "currencyCode": 980, "type": "fop"]
    let white: [String: Any] = ["id": "white", "currencyCode": 980, "type": "white"]
    let black: [String: Any] = ["id": "black", "currencyCode": 980, "type": "black"]
    assert(account([usd, fop, white, black]) == "black", "The hryvnia black card was not chosen over the default")
    assert(account([usd, fop, white, ["id": "iron", "currencyCode": 980]]) == "white", "A card lost to FOP or order")
    assert(account([usd, fop]) == "fop", "A FOP hryvnia account was ignored when it is the only one")
    assert(account([usd]) == .some(nil), "No hryvnia account must be reported, not guessed")
    assert(account([["id": "a/b", "currencyCode": 980]]) == nil, "An account id unsafe in a path was accepted")
    var bad = item("a1", -100)
    bad.removeValue(forKey: "amount")
    for (name, items) in [
        ("fractional amount", [item("a1", -100.5)]), ("amount beyond 1e9", [item("a1", -1_000_000_001)]),
        ("long id", [item(String(repeating: "a", count: 65), -100)]), ("id with <", [item("a<1", -100)]),
        ("time before the period", [item("a1", -100, at: start - 1)]),
        ("time in the future", [item("a1", -100, at: nowSeconds + 301)]),
        ("mcc 10000", [item("a1", -100, mcc: 10_000)]),
        ("missing field", [bad]), ("501 items", (0...500).map { item("i\($0)", -100) }),
    ] {
        assert(page([item("ok", -100)] + items) == nil, "A page with a \(name) was accepted")
    }
    // The period normally ends now; the bound still holds when it does not.
    let ahead = try? Monobank.statementItems(
        from: json([item("a1", -100, at: nowSeconds + 301)]), from: start, to: nowSeconds + 3_600, now: nowSeconds)
    assert(ahead == nil, "An item more than 5 minutes in the future was accepted")
    // Control characters and invisible formatting, such as a right-to-left override, are removed.
    let noisy = page([item("a1", -100, description: "АТБ\u{7}\n\u{202E}" + String(repeating: "x", count: 300))])!
    assert(noisy[0].description.hasPrefix("АТБx") && noisy[0].description.count == 200, "Description not cleaned")
    let jars = try? Monobank.jarTitles(from: Data(#"{"name":"A","jars":[{"id":"j","title":"На\u202eморе"}]}"#.utf8))
    assert(jars == ["Наморе"], "Jar titles not read or cleaned: \(String(describing: jars))")
    assert((try? Monobank.jarTitles(from: Data(#"{"name":"A"}"#.utf8))) == [], "No jars must mean an empty list")
    let longTitle = String(repeating: "я", count: 150)
    let bounded = try? Monobank.jarTitles(from: Data(#"{"jars":[{"title":"\#(longTitle)"},{"title":"\u200b"}]}"#.utf8))
    assert(bounded == [String(repeating: "я", count: 100)], "Jar titles not cut to 100 or empty ones kept")
    let manyJars = (0...100).map { _ in #"{"title":"x"}"# }.joined(separator: ",")
    assert((try? Monobank.jarTitles(from: Data(#"{"jars":[\#(manyJars)]}"#.utf8))) == nil, "101 jars were accepted")
    assert(Monobank.isTokenShaped("u3AulkpZFI1lIuGsik6vuPsVWqN7GoWs6o_MO2sdf301"), "A real token shape was refused")
    assert(!Monobank.isTokenShaped("short") && !Monobank.isTokenShaped("u3AulkpZFI1lIuGsik6 vuPsVWqN7"), "Bad token")
    assert(
        Monobank.allowsRedirect(to: URL(string: "https://api.monobank.ua/x"))
            && !Monobank.allowsRedirect(to: URL(string: "https://evil.example/x"))
            && !Monobank.allowsRedirect(to: URL(string: "http://api.monobank.ua/x")),
        "A redirect off the API was allowed")

    // The period: the whole window first, then back to shortly before the last complete sync.
    typealias State = MonobankSync.State
    assert(MonobankSync.period(for: State(), now: now) == start...nowSeconds, "The first sync must cover the window")
    assert(MonobankSync.period(for: State(lastAttempt: now - 59), now: now) == nil, "The 60 s throttle did not hold")
    assert(MonobankSync.period(for: State(lastAttempt: now - 60), now: now) != nil, "The throttle held past 60 s")
    let since = MonobankSync.period(for: State(syncedUntil: nowSeconds - 1_000), now: now)
    assert(since?.lowerBound == nowSeconds - 1_000 - 3 * 86_400, "Pending payments are not fetched again")
    assert(
        MonobankSync.period(for: State(syncedUntil: start - 99_999), now: now)?.lowerBound == start,
        "The period exceeds the API window")
    // A full page may be cut short: the next sync fetches the older part, then the sync is complete.
    let full = (0..<Monobank.pageLimit).map { StatementItem.sample("p\($0)", time: nowSeconds - 10 - $0) }
    let paging = MonobankSync.state(after: State(), period: start...nowSeconds, items: full, now: now)
    assert(paging.pageCursor == nowSeconds - 509 && paging.syncedUntil == nil, "A full page did not fetch the next one")
    let older = MonobankSync.period(for: paging, now: now + 60)!
    assert(older.upperBound == nowSeconds - 509, "The next page does not end at the oldest item")
    let done = MonobankSync.state(after: paging, period: older, items: [], now: now + 60)
    assert(done.syncedUntil == nowSeconds && done.pageCursor == nil, "Paging did not finish the sync")

    runMonobankRecordCheck(now: now)
    runMonobankRunCheck(now: now)
    runMonobankConnectCheck(now: now)
    runMonobankDeletionCheck(now: now)
}

/// Verifies how statement items become entries: filters, dedupe, merge and categories.
@MainActor
private func runMonobankRecordCheck(now: Date) {
    let url = FileManager.default.temporaryDirectory.appending(path: "selfcheck-mono-\(UUID().uuidString).store")
    defer { removeStore(at: url) }
    let context = ModelContext(try! Store.makeContainer(url: url))
    try! Store.ensureCategories(in: context)
    let t = Int(now.timeIntervalSince1970) - 7_200
    let at = { (seconds: Int) in Date(timeIntervalSince1970: TimeInterval(seconds)) }
    let fun = Store.category(withKey: "fun", in: context)!
    context.insert(Expense(amount: 50, category: fun, note: "Сільпо", date: at(t - 86_400)))
    // The Wallet automation already recorded this payment 10 minutes before the bank's time.
    let applePay = Expense(amount: 432.90, category: fun, note: "АТБ", date: at(t - 600))
    context.insert(applePay)
    // Spending and income of one amount near the bank's time: income must merge only with income.
    context.insert(Expense(amount: 77, category: fun, note: "Кава", date: at(t)))
    let income = Store.category(withKey: "income", in: context)!
    let manualSalary = Expense(amount: 1_000, category: income, note: "Зарплата", date: at(t - 300), isIncome: true)
    context.insert(manualSalary)
    // A transfer synced before transfers were labelled, and one whose note the person edited.
    let transfers = Store.category(withKey: "transfers", in: context)!
    context.insert(Expense(amount: 5, category: transfers, note: "Петро П.", date: at(t), bankID: "o1"))
    context.insert(Expense(amount: 6, category: transfers, note: "Оренда", date: at(t), bankID: "o2"))
    // A transfer recategorized by hand must not steer every later transfer: they share one note.
    context.insert(Expense(amount: 9, category: fun, note: String(localized: "Transfer"), date: at(t - 3_600)))
    try! context.save()

    let page = [
        StatementItem.sample("a1", time: t, amount: -43_290, description: "ATB-MARKET"),
        StatementItem.sample("b1", time: t, amount: -10_000, hold: true, description: "Novus"),
        StatementItem.sample("c1", time: t, amount: -5_000, description: "сільпо"),
        StatementItem.sample("d1", time: t, amount: -700, mcc: 1234, description: "Кіоск"),
        StatementItem.sample("e1", time: t, amount: 500_000, description: "Salary"),
        StatementItem.sample("f1", time: t, amount: -20_000, mcc: Monobank.transferMCC, description: "Олена К."),
        StatementItem.sample("j1", time: t, amount: -30_000, mcc: Monobank.transferMCC, description: "На банку «Море»"),
        StatementItem.sample("z1", time: t, amount: 0, description: "Перевірка картки"),
        // A second purchase of the same amount at the same time: its own entry, not merged into a1's.
        StatementItem.sample("g1", time: t, amount: -43_290, description: "ATB-MARKET"),
        StatementItem.sample(
            "w1", time: t, amount: 30_000, mcc: Monobank.transferMCC, description: "Часткове зняття банки «Море»"),
        // Names the jar but is no withdrawal from it: money from a person is income.
        StatementItem.sample("w2", time: t, amount: 15_000, mcc: Monobank.transferMCC, description: "Від: Морена"),
        StatementItem.sample("r1", time: t, amount: 43_290, description: "Скасування. ATB-MARKET"),
        StatementItem.sample("i1", time: t, amount: 20_000, mcc: Monobank.transferMCC, description: "Від: Олена К."),
        StatementItem.sample("k1", time: t, amount: 7_700, description: "Кешбек"),
        StatementItem.sample(
            "s1", time: t, amount: 100_000, mcc: Monobank.transferMCC, description: "ТОВ Роботодавець"),
        StatementItem.sample("o1", time: t, amount: -500, mcc: Monobank.transferMCC, description: "Петро П."),
        StatementItem.sample("o2", time: t, amount: -600, mcc: Monobank.transferMCC, description: "Петро П."),
    ]
    let added = try! MonobankSync.record(page, jarTitles: ["море"], in: context)
    let entries = try! context.fetch(FetchDescriptor<Expense>())
    func entry(_ id: String) -> Expense? { try! context.fetch(FetchDescriptor<Expense>()).first { $0.bankID == id } }
    let label = String(localized: "Transfer")
    assert(entry("a1") === applePay, "The bank payment did not merge with the Apple Pay entry")
    assert(entry("g1") != nil && entry("g1") !== applePay, "Two bank payments merged into one entry")
    assert(
        entry("e1").map { $0.isIncome && $0.amount == 5_000 && $0.assignedCategory?.key == "income" } == true,
        "A salary was not recorded as income")
    assert(entry("w1") == nil, "A withdrawal from the person's own jar was recorded as income")
    assert(entry("w2")?.isIncome == true, "Money from a person was hidden as a jar withdrawal")
    assert(
        entry("r1").map { $0.isIncome && $0.note == "ATB-MARKET" && $0.amount == 432.9 } == true,
        "A refund is not separate income under the merchant's name")
    assert(entry("k1").map { $0.isIncome && $0.note == "Кешбек" } == true, "Income merged with spending of its amount")
    assert(entry("s1") === manualSalary, "Bank income did not merge with the same income entered by hand")
    assert(
        entry("f1")?.note == label && entry("i1").map { $0.isIncome && $0.note == label } == true,
        "A transfer stored the bank's text instead of the label")
    assert(!entries.contains { $0.note.contains("Олена") }, "A person's name was stored")
    assert(entry("o1")?.note == label && entry("o2")?.note == "Оренда", "Old transfer notes were not relabelled safely")
    assert(entry("f1")?.assignedCategory?.key == "transfers", "A transfer to a person is not in Transfers")
    assert(entry("j1") == nil, "A top-up of the person's own jar was recorded as spending")
    assert(entry("z1") == nil, "A zero amount was recorded")
    assert(entry("b1")?.assignedCategory?.key == "food", "The MCC did not categorize a new merchant")
    assert(entry("c1")?.assignedCategory?.key == "fun", "The MCC beat the person's own category")
    assert(entry("d1")?.assignedCategory?.key == "other", "An unknown MCC did not fall back to Other")
    assert(entry("b1")?.amount == 100 && entry("b1")?.note == "Novus", "A new entry has wrong fields")
    assert(added == 10, "Expected 10 new entries, got \(added)")

    assert(try! MonobankSync.record(page, jarTitles: ["море"], in: context) == 0, "The same page recorded twice")
    // Without the jar list the same top-up is an ordinary transfer: nothing is guessed from the text.
    let unknownJar = [
        StatementItem.sample("j2", time: t, amount: -100, mcc: Monobank.transferMCC, description: "На банку «Море»")
    ]
    assert(try! MonobankSync.record(unknownJar, jarTitles: [], in: context) == 1, "A transfer was skipped by guesswork")
    // The hold settles with a smaller amount under the same id.
    let settled = StatementItem.sample("b1", time: t + 60, amount: -9_500, description: "Novus")
    assert(try! MonobankSync.record([settled], jarTitles: [], in: context) == 0, "A settled hold was added anew")
    assert(entry("b1")?.amount == 95 && entry("b1")?.date == at(t + 60), "A settled hold was not updated")
    // The same id may come back with the other sign: the entry moves between spending and income.
    for (amount, isIncome, key, hryvnias) in [(9_500, true, "income", 95.0), (-9_000, false, "food", 90)] {
        let flipped = StatementItem.sample("b1", time: t + 60, amount: amount, description: "Novus")
        assert(try! MonobankSync.record([flipped], jarTitles: [], in: context) == 0, "A sign change added an entry")
        assert(
            entry("b1").map { $0.isIncome == isIncome && $0.amount == hryvnias && $0.assignedCategory?.key == key }
                == true,
            "A sign change left the entry inconsistent")
    }
    // Before the one-time income re-fetch point, spending missing from the entries was deleted and stays so.
    let past = [
        StatementItem.sample("x1", time: t - 1, amount: -100), StatementItem.sample("x2", time: t - 1, amount: 100),
    ]
    assert(
        try! MonobankSync.record(past, jarTitles: [], incomeOnlyBefore: t, in: context) == 1, "Re-fetch added spending")
    assert(entry("x2")?.isIncome == true, "The re-fetch did not add past income")
    let huge = StatementItem.sample("h1", time: t, amount: 2_000_000_000)
    assert(try! MonobankSync.record([huge], jarTitles: [], in: context) == 0, "An amount over the maximum was stored")
}

/// Verifies one whole run through a fake transport: request, recording, state and errors.
@MainActor
private func runMonobankRunCheck(now: Date) {
    let url = FileManager.default.temporaryDirectory.appending(path: "selfcheck-mono-run-\(UUID().uuidString).store")
    defer { removeStore(at: url) }
    let context = ModelContext(try! Store.makeContainer(url: url))
    let suite = "selfcheck-monobank-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let seconds = Int(now.timeIntervalSince1970)
    let body = try! JSONSerialization.data(withJSONObject: [
        [
            "id": "r1", "time": seconds - 60, "description": "Novus", "mcc": 5411, "hold": false,
            "amount": -1_250, "currencyCode": 980,
        ],
        // A top-up of the jar that client-info lists: the run must pass the jar titles on.
        [
            "id": "r2", "time": seconds - 90, "description": "На банку «Море»", "mcc": 4829, "amount": -9_000,
            "currencyCode": 980,
        ],
        // A purchase abroad as the API may send it, with the purchase currency in the item.
        [
            "id": "r3", "time": seconds - 120, "description": "Amazon", "mcc": 5942, "amount": -4_150,
            "operationAmount": -100, "currencyCode": 840,
        ],
    ])
    // The default (first) account is in dollars; the hryvnia card comes later.
    let accounts = #""accounts":[{"id":"usd","currencyCode":840,"type":"black"},{"id":"uah","currencyCode":980}]"#
    let info = FakeTransport.Answer.success((200, Data(#"{"name":"A",\#(accounts),"jars":[{"title":"Море"}]}"#.utf8)))
    let transport = FakeTransport(answers: [info, .success((200, body))])
    func run(at date: Date) {
        wait {
            await MonobankSync.run(
                token: "token", transport: transport, context: context, defaults: defaults, now: date)
        }
    }
    run(at: now)
    let path = Monobank.statementPath(account: "uah", from: seconds - Int(Monobank.window), to: seconds)
    let expected = [Monobank.clientInfoPath + " token", path + " token"]
    assert(transport.requests == expected, "Wrong requests: \(transport.requests)")
    let recorded = try! context.fetch(FetchDescriptor<Expense>())
    assert(recorded.count == 2, "The run did not record the payments: \(recorded.count)")
    assert(recorded.first { $0.bankID == "r3" }?.amount == 41.5, "A purchase abroad was not recorded in hryvnias")
    let state = MonobankSync.loadState(from: defaults)
    assert(state.syncedUntil == seconds && state.lastSuccess == now && state.problem == nil, "State not advanced")
    assert(state.account == "uah", "The hryvnia account was not kept for runs without client-info")
    run(at: now + 30)
    assert(transport.requests.count == 2, "A second run inside 60 s sent a request")

    for (answer, problem) in [
        (FakeTransport.Answer.success((429, Data())), MonobankSync.Problem.rateLimited),
        (.success((401, Data())), .rejected), (.failure(.offline), .offline),
        (.success((200, Data("{}".utf8))), .failed),
    ] {
        transport.answers = [info, answer]
        let before = MonobankSync.loadState(from: defaults)
        run(at: before.lastAttempt! + 60)
        let after = MonobankSync.loadState(from: defaults)
        assert(after.problem == problem, "Expected \(problem), got \(String(describing: after.problem))")
        assert(after.syncedUntil == seconds, "A failed run moved the synced period")
    }
    #if DEBUG
        // The UI-test fixture must pass the same validation: 4 of its 5 items are entries to record.
        for (name, problem, count) in [
            ("ok", nil, 4), ("rejected", MonobankSync.Problem.rejected, 0), ("notHryvnia", .notHryvnia, 0),
            ("offline", .offline, 0),
        ] {
            let store = FileManager.default.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString).store")
            defer { removeStore(at: store) }
            let fixtureContext = ModelContext(try! Store.makeContainer(url: store))
            let fixtureDefaults = UserDefaults(suiteName: suite + name)!
            defer { fixtureDefaults.removePersistentDomain(forName: suite + name) }
            wait {
                await MonobankSync.run(
                    token: "token", transport: MonobankFixture(name: name, clientInfoDelay: .zero),
                    context: fixtureContext,
                    defaults: fixtureDefaults)
            }
            let entries = try! fixtureContext.fetchCount(FetchDescriptor<Expense>())
            let outcome = MonobankSync.loadState(from: fixtureDefaults).problem
            assert(
                entries == count && outcome == problem,
                "Fixture \(name): \(entries) entries, \(String(describing: outcome))")
        }
    #endif
    // A rejected token stops the run at client-info: one request, no statement.
    transport.answers = [.success((401, Data()))]
    transport.requests = []
    run(at: MonobankSync.loadState(from: defaults).lastAttempt! + 60)
    assert(MonobankSync.loadState(from: defaults).problem == .rejected, "A refused client-info was ignored")
    assert(transport.requests.count == 1, "The statement was fetched with a rejected token")
    // Any other client-info failure only loses the jar rule: the jar top-up is then imported.
    let topUp = try! JSONSerialization.data(withJSONObject: [
        [
            "id": "t1", "time": seconds - 30, "description": "На банку «Море»", "mcc": 4829, "amount": -500,
            "currencyCode": 980,
        ]
    ])
    for (index, (name, answer)) in [
        ("429", FakeTransport.Answer.success((429, Data()))), ("malformed", .success((200, Data("{".utf8)))),
        ("offline", .failure(.offline)),
    ].enumerated() {
        let before = try! context.fetchCount(FetchDescriptor<Expense>())
        let items = String(data: topUp, encoding: .utf8)!.replacingOccurrences(of: "t1", with: "t\(index)")
        transport.answers = [answer, .success((200, Data(items.utf8)))]
        transport.requests = []
        run(at: MonobankSync.loadState(from: defaults).lastAttempt! + 60)
        let after = try! context.fetchCount(FetchDescriptor<Expense>())
        assert(transport.requests.count == 2, "Client-info \(name): expected one client-info and one statement")
        assert(after == before + 1, "Client-info \(name) stopped the sync or kept the jar rule")
        assert(MonobankSync.loadState(from: defaults).problem == nil, "Client-info \(name) was reported as a problem")
    }
    // No hryvnia account: its own message, and no statement is asked for.
    transport.answers = [.success((200, Data(#"{"accounts":[{"id":"usd","currencyCode":840}]}"#.utf8)))]
    transport.requests = []
    run(at: MonobankSync.loadState(from: defaults).lastAttempt! + 60)
    assert(MonobankSync.loadState(from: defaults).problem == .notHryvnia, "No hryvnia account was not reported")
    assert(transport.requests.count == 1, "A statement was fetched without a hryvnia account")
    // With no account known, a failed client-info stops the run before the statement.
    transport.answers = [.success((429, Data()))]
    transport.requests = []
    run(at: MonobankSync.loadState(from: defaults).lastAttempt! + 60)
    assert(MonobankSync.loadState(from: defaults).problem == .rateLimited, "A 429 without an account was misreported")
    assert(transport.requests.count == 1, "A statement was fetched with no account known")
    // A state from before income was recorded still loads, and re-fetches the whole window once.
    defaults.set(Data(#"{"syncedUntil":\#(seconds),"account":"uah"}"#.utf8), forKey: MonobankSync.stateKey)
    let legacy = MonobankSync.loadState(from: defaults)
    assert(
        legacy.syncedUntil == nil && legacy.account == "uah" && legacy.incomeOnlyBefore == seconds - 3 * 86_400,
        "An older stored state was lost or not set to re-fetch income")
    let later = seconds + 600
    let backfill = try! JSONSerialization.data(withJSONObject: [
        ["id": "r1", "time": seconds - 60, "description": "Novus", "mcc": 5411, "amount": -1_250],
        ["id": "old", "time": seconds - 5 * 86_400, "description": "Deleted", "mcc": 5411, "amount": -700],
        ["id": "pay", "time": seconds - 5 * 86_400, "description": "Зарплата", "mcc": 1234, "amount": 500_000],
    ])
    transport.answers = [.success((429, Data())), .success((200, backfill))]
    transport.requests = []
    let before = try! context.fetchCount(FetchDescriptor<Expense>())
    run(at: Date(timeIntervalSince1970: TimeInterval(later)))
    let fetched = transport.requests.last?.hasPrefix(
        Monobank.statementPath(account: "uah", from: later - Int(Monobank.window), to: later))
    let added = try! context.fetch(FetchDescriptor<Expense>()).filter { ["r1", "old", "pay"].contains($0.bankID) }
    assert(
        fetched == true && (try! context.fetchCount(FetchDescriptor<Expense>())) == before + 1, "Backfill went wrong")
    assert(added.compactMap(\.bankID).sorted() == ["pay", "r1"], "The backfill added the wrong entries")
    let after = MonobankSync.loadState(from: defaults)
    assert(
        after.version == MonobankSync.stateVersion && after.syncedUntil == later
            && MonobankSync.period(for: after, now: Date(timeIntervalSince1970: TimeInterval(later + 60)))?.lowerBound
                == later - 3 * 86_400,
        "The income re-fetch did not run exactly once")
}

/// Verifies connecting: one `client-info` call serves both the token check and the first sync.
@MainActor
private func runMonobankConnectCheck(now: Date) {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "selfcheck-mono-connect-\(UUID().uuidString).store")
    defer { removeStore(at: url) }
    let context = ModelContext(try! Store.makeContainer(url: url))
    let suite = "selfcheck-monobank-connect-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let seconds = Int(now.timeIntervalSince1970)
    let info = Data(#"{"name":"A","accounts":[{"id":"uah","currencyCode":980}],"jars":[{"title":"Море"}]}"#.utf8)
    let topUp = try! JSONSerialization.data(withJSONObject: [
        [
            "id": "c1", "time": seconds - 60, "description": "На банку «Море»", "mcc": 4829, "amount": -500,
            "currencyCode": 980,
        ]
    ])
    let transport = FakeTransport(answers: [.success((200, info)), .success((200, topUp))])
    let status = wait {
        try? await MonobankSync.connect(
            token: "token", transport: transport, context: context, defaults: defaults, saveToken: { _ in true },
            now: now)
    }
    let infoCalls = transport.requests.filter { $0.hasPrefix(Monobank.clientInfoPath) }.count
    assert(
        status == 200 && defaults.bool(forKey: MonobankSync.linkedKey),
        "Connecting failed: \(String(describing: status))")
    assert(infoCalls == 1 && transport.requests.count == 2, "Connecting asked client-info \(infoCalls) times")
    assert(transport.requests.last?.hasPrefix("/personal/statement/uah/") == true, "Connecting synced another account")
    assert(try! context.fetchCount(FetchDescriptor<Expense>()) == 0, "The first sync lost the jar list")
}

/// Verifies that a deleted bank entry stays deleted: re-syncs skip its id until the id expires.
@MainActor
private func runMonobankDeletionCheck(now: Date) {
    let url = FileManager.default.temporaryDirectory.appending(path: "selfcheck-mono-del-\(UUID().uuidString).store")
    defer { removeStore(at: url) }
    let context = ModelContext(try! Store.makeContainer(url: url))
    let suite = "selfcheck-monobank-del-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: MonobankSync.linkedKey)
    let info = Data(#"{"accounts":[{"id":"uah","currencyCode":980}]}"#.utf8)
    let page = try! JSONSerialization.data(withJSONObject: [
        ["id": "d1", "time": Int(now.timeIntervalSince1970) - 60, "description": "Novus", "mcc": 5411, "amount": -900]
    ])
    let transport = FakeTransport(answers: [])
    func sync(at date: Date) -> Expense? {
        transport.answers = [.success((200, info)), .success((200, page))]
        wait {
            await MonobankSync.run(
                token: "token", transport: transport, context: context, defaults: defaults, now: date)
        }
        return try! context.fetch(FetchDescriptor<Expense>()).first { $0.bankID == "d1" }
    }
    let synced = sync(at: now)!
    MonobankSync.rememberDeletion(of: synced, defaults: defaults, now: now)
    context.delete(synced)
    try! context.save()
    let manual = Expense(amount: 5, category: Store.category(withKey: "fun", in: context)!, note: "Кава")
    MonobankSync.rememberDeletion(of: manual, defaults: defaults, now: now)
    assert(sync(at: now + 60) == nil, "A re-sync recreated a deleted bank entry")
    let kept = MonobankSync.loadState(from: defaults).deletedIDs
    assert(kept.map(Array.init)?.map(\.key) == ["d1"], "Wrong deleted ids: \(String(describing: kept))")
    transport.answers = []
    wait {
        await MonobankSync.run(
            token: "token", transport: transport, context: context, defaults: defaults,
            now: now + MonobankSync.tombstoneLifetime)
    }
    assert(MonobankSync.loadState(from: defaults).deletedIDs?.isEmpty == true, "An expired deleted id was kept")
    let other = Expense(amount: 9, category: manual.assignedCategory!, note: "Novus", bankID: "d2")
    MonobankSync.rememberDeletion(of: other, defaults: defaults, now: now)
    MonobankSync.forget(in: defaults)
    assert(MonobankSync.loadState(from: defaults).deletedIDs == nil, "Disconnecting kept the deleted ids")
}

/// Answers requests with canned responses and records what was asked.
private final class FakeTransport: MonobankTransport, @unchecked Sendable {
    typealias Answer = Result<(Int, Data), MonobankError>
    var answers: [Answer]
    /// Each request as "path token".
    var requests: [String] = []

    init(answers: [Answer]) { self.answers = answers }

    func get(_ path: String, token: String) async throws -> (status: Int, body: Data) {
        requests.append(path + " " + token)
        // An unexpected request fails the check through its assertions, not a trap.
        guard !answers.isEmpty else { throw MonobankError.offline }
        let (status, body) = try answers.removeFirst().get()
        return (status, body)
    }
}

extension StatementItem {
    /// An item for checks, spending by default.
    fileprivate static func sample(
        _ id: String, time: Int, amount: Int = -100, mcc: Int = 5411, hold: Bool = false, description: String = "Shop"
    ) -> StatementItem {
        let object: [String: Any] = [
            "id": id, "time": time, "description": description, "mcc": mcc, "hold": hold, "amount": amount,
        ]
        return try! JSONDecoder().decode(StatementItem.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
