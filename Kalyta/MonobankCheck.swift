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
    do {
        _ = try Monobank.statementItems(
            from: json([item("a1", -100, currency: 840)]), from: start, to: nowSeconds, now: nowSeconds)
        assertionFailure("A dollar account was accepted")
    } catch {
        assert(error as? MonobankError == .notHryvnia, "A dollar account was not reported as such: \(error)")
    }
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
    ]
    let added = try! MonobankSync.record(page, jarTitles: ["море"], in: context)
    let entries = try! context.fetch(FetchDescriptor<Expense>())
    func entry(_ id: String) -> Expense? { entries.first { $0.bankID == id } }
    assert(entry("a1") === applePay, "The bank payment did not merge with the Apple Pay entry")
    assert(entry("g1") != nil && entry("g1") !== applePay, "Two bank payments merged into one entry")
    assert(entry("e1") == nil, "Income was recorded as spending")
    assert(entry("f1")?.assignedCategory?.key == "transfers", "A transfer to a person is not in Transfers")
    assert(entry("j1") == nil, "A top-up of the person's own jar was recorded as spending")
    assert(entry("z1") == nil, "A zero amount was recorded")
    assert(entry("b1")?.assignedCategory?.key == "food", "The MCC did not categorize a new merchant")
    assert(entry("c1")?.assignedCategory?.key == "fun", "The MCC beat the person's own category")
    assert(entry("d1")?.assignedCategory?.key == "other", "An unknown MCC did not fall back to Other")
    assert(entry("b1")?.amount == 100 && entry("b1")?.note == "Novus", "A new entry has wrong fields")
    assert(added == 5, "Expected 5 new entries, got \(added)")

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
    let dollarPage = try! JSONSerialization.data(withJSONObject: [
        ["id": "u1", "time": seconds - 60, "mcc": 5411, "amount": -100, "currencyCode": 840]
    ])
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
    ])
    let info = FakeTransport.Answer.success((200, Data(#"{"name":"A","jars":[{"title":"Море"}]}"#.utf8)))
    let transport = FakeTransport(answers: [info, .success((200, body))])
    func run(at date: Date) {
        wait {
            await MonobankSync.run(
                token: "token", transport: transport, context: context, defaults: defaults, now: date)
        }
    }
    run(at: now)
    let path = Monobank.statementPath(from: seconds - Int(Monobank.window), to: seconds)
    let expected = [Monobank.clientInfoPath + " token", path + " token"]
    assert(transport.requests == expected, "Wrong requests: \(transport.requests)")
    assert(try! context.fetchCount(FetchDescriptor<Expense>()) == 1, "The run did not record the payment")
    let state = MonobankSync.loadState(from: defaults)
    assert(state.syncedUntil == seconds && state.lastSuccess == now && state.problem == nil, "State not advanced")
    run(at: now + 30)
    assert(transport.requests.count == 2, "A second run inside 60 s sent a request")

    for (answer, problem) in [
        (FakeTransport.Answer.success((429, Data())), MonobankSync.Problem.rateLimited),
        (.success((401, Data())), .rejected), (.failure(.offline), .offline),
        (.success((200, Data("{}".utf8))), .failed), (.success((200, dollarPage)), .notHryvnia),
    ] {
        transport.answers = [info, answer]
        let before = MonobankSync.loadState(from: defaults)
        run(at: before.lastAttempt! + 60)
        let after = MonobankSync.loadState(from: defaults)
        assert(after.problem == problem, "Expected \(problem), got \(String(describing: after.problem))")
        assert(after.syncedUntil == seconds, "A failed run moved the synced period")
    }
    #if DEBUG
        // The UI-test fixture must pass the same validation: 3 of its 5 items are spending to record.
        for (name, problem, count) in [
            ("ok", nil, 3), ("rejected", MonobankSync.Problem.rejected, 0), ("notHryvnia", .notHryvnia, 0),
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
    let info = Data(#"{"name":"A","jars":[{"title":"Море"}]}"#.utf8)
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
    assert(try! context.fetchCount(FetchDescriptor<Expense>()) == 0, "The first sync lost the jar list")
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
    /// An item for checks, spending in hryvnias by default.
    fileprivate static func sample(
        _ id: String, time: Int, amount: Int = -100, mcc: Int = 5411, hold: Bool = false, description: String = "Shop"
    ) -> StatementItem {
        let object: [String: Any] = [
            "id": id, "time": time, "description": description, "mcc": mcc, "hold": hold, "amount": amount,
            "currencyCode": 980,
        ]
        return try! JSONDecoder().decode(StatementItem.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
