import Foundation
import SwiftData

/// Verifies currencies: the V5 → V6 migration, the merge, NBU and monobank decoding, the Kyiv date,
/// caching, the token-less request, rounding, estimated rates, CSV, and that hryvnias ask nothing.
/// Uses temporary stores and ``RateFixture``; never the network.
@MainActor
func runCurrencyCheck() {
    #if DEBUG
        runCurrencyStoreCheck()
        runCurrencyRatesCheck()
        runCurrencyCSVCheck()
    #endif
}

#if DEBUG
    /// Creates a cache answered by the `friday` fixture, or another named one.
    @MainActor
    private func fixtureRates(_ name: String = "friday") -> CurrencyRates {
        CurrencyRates(transport: RateFixture(name: name))
    }

    /// Check 1: a V5 store opens on V6 intact, and a merge keeps the four currency fields.
    @MainActor
    private func runCurrencyStoreCheck() {
        let url = FileManager.default.temporaryDirectory.appending(path: "selfcheck-v5-\(UUID().uuidString).store")
        defer { removeStore(at: url) }
        do {
            let schema = Schema(versionedSchema: SchemaV5.self)
            let v5 = ModelContext(
                try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url)))
            let food = SchemaV5.ExpenseCategory(
                key: "food", customName: nil, symbol: "fork.knife", colorName: "orange", sortOrder: 0)
            v5.insert(food)
            v5.insert(SchemaV5.Expense(amount: 248.9, category: food, note: "v5 bank", bankID: "b-v5"))
            v5.insert(SchemaV5.Expense(amount: 1_000, category: food, note: "v5 cash"))
            try! v5.save()
        }
        let context = ModelContext(try! Store.makeContainer(url: url))
        let entries = try! context.fetch(FetchDescriptor<Expense>())
        assert(entries.count == 2, "The V5 → V6 migration lost entries: \(entries.count)")
        assert(entries.map(\.amount).reduce(0, +) == 1_248.9, "The V5 → V6 migration changed the total")
        assert(entries.contains { $0.bankID == "b-v5" }, "The V5 → V6 migration lost a bank id")
        assert(
            entries.allSatisfy {
                $0.currencyCode == nil && $0.originalAmount == nil && $0.rate == nil && !$0.isRateEstimated
            }, "The V5 → V6 migration gave entries a currency")

        // The merge from the App Group's store copies a foreign entry whole.
        let sourceURL = FileManager.default.temporaryDirectory.appending(
            path: "selfcheck-fx-\(UUID().uuidString).store")
        let targetURL = FileManager.default.temporaryDirectory.appending(
            path: "selfcheck-fx-\(UUID().uuidString).store")
        defer {
            removeStore(at: sourceURL)
            removeStore(at: targetURL)
        }
        do {
            let source = ModelContext(try! Store.makeContainer(url: sourceURL))
            try! Store.ensureCategories(in: source)
            let entry = Expense(amount: 4_497.29, category: Store.category(forKey: "food", in: source), note: "fx")
            entry.originalAmount = 100
            entry.currencyCode = "USD"
            entry.rate = 44.9729
            entry.isRateEstimated = true
            source.insert(entry)
            try! source.save()
        }
        let target = ModelContext(try! Store.makeContainer(url: targetURL))
        try! StoreMerge.merge(from: sourceURL, into: target)
        let merged = try! target.fetch(FetchDescriptor<Expense>()).first
        assert(
            merged?.originalAmount == 100 && merged?.currencyCode == "USD" && merged?.rate == 44.9729
                && merged?.isRateEstimated == true, "The merge dropped currency fields")
    }

    /// Checks 2–5 and 7: decoding, the Kyiv day, caching, the request, pairs, rounding and estimated rates.
    @MainActor
    private func runCurrencyRatesCheck() {
        let friday = wait { try! await RateFixture(name: "friday").get(RatesHTTP.nbuURL).body }
        let list = NBURate.list(from: friday)
        assert(list?.first { $0.cc == "USD" }?.rate == 44.9729, "The NBU list was not read")
        assert(list?.contains { $0.cc == "XAU" } == false, "A rate out of bounds (gold) was kept")
        let text = String(decoding: friday, as: UTF8.self)
        let outOfRange = text.replacingOccurrences(of: "44.9729", with: "20000")
        assert(
            NBURate.list(from: Data(outOfRange.utf8))?.contains { $0.cc == "USD" } == false,
            "A rate over 10,000 was used")
        let tinyRate = text.replacingOccurrences(of: "44.9729", with: "0.00001")
        assert(
            NBURate.list(from: Data(tinyRate.utf8))?.contains { $0.cc == "USD" } == false,
            "A rate under 0.0001 was used")
        for bad in ["-1", "0", "1e999", "\"44.9729\""] {
            let broken = text.replacingOccurrences(of: "44.9729", with: bad)
            assert(NBURate.list(from: Data(broken.utf8)) == nil, "A malformed rate \(bad) was accepted")
        }
        let badCode = text.replacingOccurrences(of: "\"USD\"", with: "\"usd\"")
        assert(NBURate.list(from: Data(badCode.utf8)) == nil, "A malformed currency code was accepted")
        let padded = text.replacingOccurrences(
            of: "\"Євро\"", with: "\"" + String(repeating: "x", count: 70_000) + "\"")
        assert(NBURate.list(from: Data(padded.utf8)) == nil, "An answer over 64 KB was accepted")

        // The Kyiv calendar day: 22:30 UTC on 27.09 is already 28.09 in Kyiv.
        let lateSunday = Date(timeIntervalSince1970: 1_790_548_200)  // 2026-09-27T22:30:00Z
        assert(Currency.nbuDay(of: lateSunday) == "20260928", "Not the Kyiv day: \(Currency.nbuDay(of: lateSunday))")

        // A future day: the NBU answers [], which is no rate, never 1 or 0.
        assert(wait { await fixtureRates("empty").nbuRate("USD", on: lateSunday) } == nil, "[] gave a rate")
        assert(wait { await fixtureRates("offline").nbuRate("USD", on: lateSunday) } == nil, "Offline gave a rate")
        assert(wait { await fixtureRates("malformed").nbuRate("USD", on: lateSunday) } == nil, "Malformed gave a rate")

        // One request per Kyiv day.
        let rates = fixtureRates()
        let first = wait { await rates.nbuRate("USD", on: lateSunday) }
        let again = wait { await rates.nbuRate("EUR", on: lateSunday.addingTimeInterval(3_600)) }
        assert(first == 44.9729 && again == 52.6412, "The NBU rates were not read")
        assert(rates.requestCount == 1, "The same day was fetched \(rates.requestCount) times")
        assert(rates.lastKnownRate("USD") == 44.9729, "This launch's rate was not kept for offline use")

        // Check 3: no token and no device details; the pair found by the NBU's numeric code.
        let request = RatesHTTP.request(for: RatesHTTP.monobankURL)
        assert(request.value(forHTTPHeaderField: "X-Token") == nil, "The rates request carries a token")
        assert(request.allHTTPHeaderFields == ["User-Agent": "Kalyta"], "The rates request has extra headers")
        let now = Date(timeIntervalSince1970: 1_790_380_800)  // 2026-09-26T00:00:00Z
        let quotes = CurrencyRates(transport: RateFixture(name: "friday"), now: { now })
        let spending = wait { await quotes.quote(for: "USD", on: now, isIncome: false) }
        let income = wait { await quotes.quote(for: "USD", on: now, isIncome: true) }
        let euro = wait { await quotes.quote(for: "EUR", on: now, isIncome: false) }
        let zloty = wait { await quotes.quote(for: "PLN", on: now, isIncome: false) }
        assert(spending?.monobank == .sells(45.1998), "Spending did not get monobank's sell rate: \(spending as Any)")
        assert(income?.monobank == .buys(44.8), "Income did not get monobank's buy rate: \(income as Any)")
        assert(euro?.monobank == .sells(51.2505), "EUR took the wrong pair: \(euro as Any)")
        assert(zloty?.monobank == .cross(11.7898), "A cross-only pair gave no rate: \(zloty as Any)")
        assert(spending?.nbuOnDate == 44.9729 && spending?.nbuToday == 44.9729, "The NBU rates are missing")
        assert(quotes.requestCount == 2, "monobank was asked more than once in 5 minutes: \(quotes.requestCount)")

        // Check 4: Decimal, half-up to kopiykas.
        assert(
            Currency.hryvnias(3, at: 44.9729) == 134.92, "3 × 44.9729 is \(Currency.hryvnias(3, at: 44.9729) as Any)")
        assert(Currency.hryvnias(100, at: 44.9729) == 4_497.29, "100 × 44.9729 was not 4497.29")
        assert(Currency.hryvnias(1, at: 0.125) == 0.13, "A half kopiyka did not round up")
        assert(Currency.hryvnias(0, at: 44.9729) == nil, "A zero original was converted")
        assert(Currency.hryvnias(1, at: 20_000) == nil, "A rate out of bounds was used")
        assert(Currency.hryvnias(1_000_000, at: 44.9729) == nil, "A conversion over the amount limit was accepted")

        // The editor's rate: the NBU's for the date, else the stand-in marked as estimated; a typed rate stays.
        var conversion = Conversion()
        conversion.code = "USD"
        conversion.apply(RateQuote(nbuOnDate: 44.9729), fallback: 40)
        assert(conversion.rate == 44.9729 && !conversion.isEstimated, "The NBU rate was not used")
        conversion.apply(RateQuote(), fallback: 40)
        assert(conversion.rate == 40 && conversion.isEstimated, "Offline, the stand-in was not marked estimated")
        conversion.apply(RateQuote(), fallback: nil)
        assert(conversion.rate == nil && conversion.hryvnias(for: 100) == nil, "With no rate, Save was possible")
        conversion.rate = 41
        conversion.isManual = true
        conversion.apply(RateQuote(nbuOnDate: 44.9729), fallback: nil)
        assert(conversion.rate == 41, "A typed rate was replaced")

        // Check 5: an estimated entry gets the NBU rate when online, and the flag is cleared.
        let url = FileManager.default.temporaryDirectory.appending(path: "selfcheck-est-\(UUID().uuidString).store")
        defer { removeStore(at: url) }
        let context = ModelContext(try! Store.makeContainer(url: url))
        try! Store.ensureCategories(in: context)
        let estimated = Expense(amount: 4_000, category: Store.category(forKey: "food", in: context), date: now)
        estimated.originalAmount = 100
        estimated.currencyCode = "USD"
        estimated.rate = 40
        estimated.isRateEstimated = true
        context.insert(estimated)
        try! context.save()
        assert(wait { await fixtureRates("offline").refreshEstimated(in: context) } == 0, "Offline changed an entry")
        assert(estimated.isRateEstimated && estimated.amount == 4_000, "Offline cleared an estimate")
        assert(wait { await fixtureRates().refreshEstimated(in: context) } == 1, "The estimate was not refreshed")
        assert(
            estimated.rate == 44.9729 && estimated.amount == 4_497.29 && !estimated.isRateEstimated,
            "The estimated entry was not recomputed: \(estimated.amount), \(estimated.isRateEstimated)")

        // Check 7: hryvnias ask nothing, from the editor or from the refresh.
        context.delete(estimated)
        context.insert(Expense(amount: 50, category: Store.category(forKey: "food", in: context)))
        try! context.save()
        let idle = fixtureRates()
        assert(wait { await idle.quote(for: hryvniaCurrencyCode, on: now, isIncome: false) } == nil, "UAH got a quote")
        _ = wait { await idle.refreshEstimated(in: context) }
        assert(idle.requestCount == 0, "A hryvnia-only store made \(idle.requestCount) rate requests")
    }

    /// Check 6: a foreign entry survives a CSV round trip; old files import; the currency is part of the key.
    @MainActor
    private func runCurrencyCSVCheck() {
        let kyiv = TimeZone(identifier: "Europe/Kyiv")!
        let date = Date(timeIntervalSince1970: 1_790_155_080)
        let dollars = ExpenseRecord(
            date: date, amount: 4_497.29, categoryKey: "food", categoryName: "Їжа", note: "Кава",
            categorySymbol: "fork.knife", categoryColorName: "orange", originalAmount: 100, currencyCode: "USD",
            rate: 44.9729, isRateEstimated: true)
        let csv = ExpenseCSV.document(for: [dollars], timeZone: kyiv)
        assert(
            csv.contains(",4497.29,UAH,food,") && csv.contains(",100,USD,44.9729,true\r\n"), "Foreign columns: \(csv)")
        let plan = try! ExpenseImport.plan(csv: csv, existing: [])
        assert(plan.toInsert == [dollars], "A foreign entry did not survive the round trip: \(plan.toInsert)")
        assert(try! ExpenseImport.plan(csv: csv, existing: [dollars]).duplicateCount == 1, "A re-import duplicated")

        // Same hryvnias, time and note, but entered in hryvnias: a different entry.
        let hryvnias = ExpenseRecord(
            date: date, amount: 4_497.29, categoryKey: "food", categoryName: "Їжа", note: "Кава",
            categorySymbol: "fork.knife", categoryColorName: "orange")
        assert(
            ExpenseImport.DuplicateKey(hryvnias) != ExpenseImport.DuplicateKey(dollars),
            "The currency is not part of the duplicate key")

        // A nine-column file from before currencies.
        let old =
            "date,amount,currency,category,category_name,note,category_symbol,category_color,kind\r\n"
            + "2026-09-23T12:18:00+03:00,10,UAH,food,Їжа,Хліб,fork.knife,orange,expense\r\n"
        let oldPlan = try! ExpenseImport.plan(csv: old, existing: [])
        assert(oldPlan.toInsert.count == 1 && oldPlan.toInsert[0].currencyCode == nil, "An old file did not import")

        // Bad foreign columns refuse the row; a non-hryvnia `currency` still refuses the file.
        let header = ExpenseCSV.columns.joined(separator: ",") + "\r\n"
        let row = "2026-09-23T12:18:00+03:00,10,UAH,food,Їжа,,fork.knife,orange,expense,"
        for bad in ["1,usd,40,false", "1,USD,0,false", "0,USD,40,false", "1,USD,40,maybe", "1,UAH,40,false"] {
            let file = header + row + "1,USD,40,false\r\n" + row + bad + "\r\n"
            assert((try? ExpenseImport.plan(csv: file, existing: []))?.invalidLines == [3], "Accepted \(bad)")
        }
        let foreignAmount = header + "2026-09-23T12:18:00+03:00,10,USD,food,Їжа,,fork.knife,orange,expense\r\n"
        assert(
            (try? ExpenseImport.plan(csv: foreignAmount, existing: [])) == nil,
            "A row whose amount is not in hryvnias was accepted")
    }
#endif
