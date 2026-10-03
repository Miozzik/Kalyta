import Foundation
import SwiftData

/// Converting foreign amounts to hryvnias and reading the exchange rates that do it.
enum Currency {
    /// The NBU's time zone: an entry's rate is the one for its calendar date in Kyiv.
    static let kyiv = TimeZone(identifier: "Europe/Kyiv")!
    /// The hryvnias per unit a rate may be; anything else is a typo or a broken answer.
    static let rateBounds = 0.0001...10_000.0
    /// The largest rates answer accepted; the NBU's whole-day list is about 6 KB, monobank's about 10 KB.
    static let maximumBodySize = 64 * 1024

    /// Returns the hryvnias for `original` units at `rate`, rounded half-up to kopiykas.
    ///
    /// Works in `Decimal` from the numbers' shortest decimal form, so 3 × 44.9729 is exactly 134.9187 and
    /// rounds to 134.92; binary doubles would round some halves the wrong way.
    ///
    /// - Parameters:
    ///   - original: The amount in the foreign currency.
    ///   - rate: Hryvnias per unit.
    /// - Returns: The hryvnias, or `nil` if the original is not finite and positive, the rate is out of
    ///   ``rateBounds``, or the result fails ``isValidAmount(_:)``.
    static func hryvnias(_ original: Double, at rate: Double) -> Double? {
        guard original.isFinite, original > 0, rateBounds.contains(rate),
            var product = Decimal(string: "\(original)", locale: Locale(identifier: "en_US_POSIX")).flatMap({ amount in
                Decimal(string: "\(rate)", locale: Locale(identifier: "en_US_POSIX")).map { amount * $0 }
            })
        else { return nil }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &product, 2, .plain)
        // Through the decimal text: `NSDecimalNumber.doubleValue` gives 134.92000000000002 for 134.92.
        guard let value = Double(rounded.description), isValidAmount(value) else { return nil }
        return value
    }

    /// Returns the NBU's name of the Kyiv calendar day that contains `date`, such as "20260927".
    ///
    /// - Parameter date: The moment of an entry.
    /// - Returns: The `date` parameter of an NBU request.
    static func nbuDay(of date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(dateSeparator: .omitted, timeZone: kyiv).year().month().day())
    }

    /// Returns whether `code` looks like an ISO 4217 code: three uppercase ASCII letters.
    ///
    /// - Parameter code: The text to check.
    /// - Returns: `true` for a code such as "USD".
    static func isCurrencyCode(_ code: String) -> Bool {
        code.count == 3 && code.allSatisfy { $0.isASCII && $0.isUppercase }
    }
}

/// One currency in the NBU's list for a day.
struct NBURate: Decodable, Equatable, Sendable {
    /// The ISO 4217 numeric code, such as 840; monobank names currencies by it.
    let r030: Int
    /// The ISO 4217 code, such as "USD".
    let cc: String
    /// Hryvnias per unit.
    let rate: Double
    /// The day the rate is for, as "dd.MM.yyyy".
    let exchangedate: String

    /// Reads the NBU's answer for a day.
    ///
    /// Any malformed field refuses the whole answer. A well-formed rate outside ``Currency/rateBounds``
    /// drops only its own entry: the list carries precious metals (gold is about 190,000 per ounce).
    ///
    /// - Parameter body: The response body.
    /// - Returns: The usable rates, or `nil` if the answer is too large or malformed.
    static func list(from body: Data) -> [NBURate]? {
        guard body.count <= Currency.maximumBodySize, let list = try? JSONDecoder().decode([NBURate].self, from: body),
            list.allSatisfy(\.isWellFormed)
        else { return nil }
        return list.filter { Currency.rateBounds.contains($0.rate) }
    }

    private var isWellFormed: Bool {
        Currency.isCurrencyCode(cc) && (1...999).contains(r030) && rate.isFinite && rate > 0
            && exchangedate.wholeMatch(of: /\d{2}\.\d{2}\.\d{4}/) != nil
    }
}

/// One pair from monobank's `/bank/currency`; exotic currencies carry only ``rateCross``.
struct MonobankPair: Decodable, Equatable, Sendable {
    let currencyCodeA: Int
    let currencyCodeB: Int
    /// What the bank pays for one unit of A.
    let rateBuy: Double?
    /// What the bank asks for one unit of A.
    let rateSell: Double?
    /// The one rate of a pair without buy and sell.
    let rateCross: Double?

    /// Reads monobank's answer; any malformed pair or out-of-bounds rate refuses the whole answer.
    ///
    /// - Parameter body: The response body.
    /// - Returns: The pairs, or `nil` if the answer is too large or malformed.
    static func list(from body: Data) -> [MonobankPair]? {
        guard body.count <= Currency.maximumBodySize,
            let list = try? JSONDecoder().decode([MonobankPair].self, from: body),
            list.allSatisfy({
                [$0.rateBuy, $0.rateSell, $0.rateCross].allSatisfy { $0.map(Currency.rateBounds.contains) ?? true }
            })
        else { return nil }
        return list
    }

    /// The rate shown next to an entry: the bank's buy rate for income (it buys the currency you
    /// received), its sell rate for spending, or the cross rate when the pair has no other.
    ///
    /// - Parameter isIncome: Whether the entry is income.
    /// - Returns: The rate and which one it is, or `nil` if the pair has none.
    func quote(isIncome: Bool) -> MonobankQuote? {
        if isIncome, let rateBuy { return .buys(rateBuy) }
        if !isIncome, let rateSell { return .sells(rateSell) }
        return rateCross.map(MonobankQuote.cross)
    }
}

/// monobank's rate for today, labelled by what it means.
enum MonobankQuote: Equatable, Sendable {
    case buys(Double)
    case sells(Double)
    case cross(Double)
}

/// The rates shown for a foreign entry.
struct RateQuote: Equatable, Sendable {
    /// The NBU rate for the entry's date.
    var nbuOnDate: Double?
    /// The NBU rate for today.
    var nbuToday: Double?
    /// monobank's rate for today.
    var monobank: MonobankQuote?
    /// Whether the NBU's list for the entry's date arrived; if so, a missing rate means the NBU has none.
    var nbuAnswered = false
}

/// Sends one GET request for rates, without any token.
///
/// A protocol so the self-check and UI tests answer with canned JSON instead of the network.
protocol RateTransport: Sendable {
    /// Requests `url`.
    ///
    /// - Parameter url: An NBU or monobank rates URL.
    /// - Returns: The status code and the body.
    /// - Throws: An error if no complete answer arrived.
    func get(_ url: URL) async throws -> (status: Int, body: Data)
}

/// The real transport for rates: ephemeral sessions, so nothing is cached on disk, and no token.
///
/// Never ``MonobankHTTP``, which sends the personal token with every request.
struct RatesHTTP: RateTransport {
    /// The NBU's daily list; the `date` and `json` query items are added per request.
    static let nbuURL = URL(string: "https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange")!
    /// monobank's public rates; no token, cached by monobank for at least 5 minutes.
    static let monobankURL = Monobank.baseURL.appending(path: "/bank/currency")

    /// One session per host, so a redirect can never lead off it.
    private static let sessions = Dictionary(
        uniqueKeysWithValues: [nbuURL, Monobank.baseURL].map { base in
            (
                base.host!,
                URLSession(configuration: .ephemeral, delegate: SameHostRedirects(to: base), delegateQueue: nil)
            )
        })

    /// Returns the request for `url`: a User-Agent that names no device, OS or version, and no other header.
    ///
    /// - Parameter url: The rates URL.
    /// - Returns: The request.
    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Kalyta", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        return request
    }

    func get(_ url: URL) async throws -> (status: Int, body: Data) {
        guard let session = url.host.flatMap({ Self.sessions[$0] }) else { throw URLError(.unsupportedURL) }
        let (bytes, response) = try await session.bytes(for: Self.request(for: url))
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            guard body.count <= Currency.maximumBodySize else { throw URLError(.dataLengthExceedsMaximum) }
        }
        return (http.statusCode, body)
    }
}

/// The rates the app has read in this launch; nothing is written to disk.
@MainActor
final class CurrencyRates {
    /// The instance the interface uses.
    static let shared = CurrencyRates(transport: defaultTransport)

    /// How long monobank's rates are reused; monobank itself caches them for at least 5 minutes.
    static let monobankLifetime: TimeInterval = 5 * 60
    /// How long to wait after monobank answers 429 Too Many Requests.
    static let monobankBackoff: TimeInterval = 60

    private let transport: RateTransport
    private let now: () -> Date
    /// How many requests went to the transport; the self-check reads it.
    private(set) var requestCount = 0
    /// The NBU lists by ``Currency/nbuDay(of:)``, kept as tasks so two callers share one request.
    private var nbuLists: [String: Task<[NBURate]?, Never>] = [:]
    /// The latest NBU rate read in this launch, by currency code: the offline stand-in.
    private var lastKnown: [String: Double] = [:]
    private var monobank: (fetched: Date, pairs: [MonobankPair])?
    private var monobankPausedUntil = Date.distantPast

    /// Creates a cache in front of `transport`.
    ///
    /// - Parameters:
    ///   - transport: Where requests go.
    ///   - now: The clock, so the self-check can fix "today".
    init(transport: RateTransport, now: @escaping () -> Date = { .now }) {
        self.transport = transport
        self.now = now
    }

    /// The transport for real use; debug builds answer from a canned scenario with
    /// `-rateFixture <name>`, see ``RateFixture``.
    static var defaultTransport: RateTransport {
        #if DEBUG
            if let name = UserDefaults.standard.string(forKey: "rateFixture") { return RateFixture(name: name) }
        #endif
        return RatesHTTP()
    }

    /// Returns the rates to show for an entry in `code`; asks nothing for hryvnias.
    ///
    /// - Parameters:
    ///   - code: The entry's currency.
    ///   - date: When the entry happened.
    ///   - isIncome: Whether it is income, which picks monobank's buy or sell rate.
    /// - Returns: The rates that could be read, or `nil` for hryvnias.
    func quote(for code: String, on date: Date, isIncome: Bool) async -> RateQuote? {
        guard code != hryvniaCurrencyCode else { return nil }
        let onDate = await nbuList(on: date)
        let today = Currency.nbuDay(of: date) == Currency.nbuDay(of: now()) ? onDate : await nbuList(on: now())
        var quote = RateQuote(
            nbuOnDate: onDate?.first { $0.cc == code }?.rate, nbuToday: today?.first { $0.cc == code }?.rate,
            nbuAnswered: onDate != nil)
        // monobank names currencies by number; the NBU's list gives it, so no table is kept here.
        if let numeric = (today ?? onDate)?.first(where: { $0.cc == code })?.r030 {
            let pair = await monobankPairs()?.first {
                $0.currencyCodeA == numeric && $0.currencyCodeB == Monobank.hryvniaNumericCode
            }
            quote.monobank = pair?.quote(isIncome: isIncome)
        }
        return quote
    }

    /// Returns the NBU rate of `code` for the Kyiv day of `date`.
    ///
    /// - Parameters:
    ///   - code: An ISO 4217 code.
    ///   - date: The entry's moment.
    /// - Returns: The rate, or `nil` offline, for a future day (the NBU answers `[]`) or an unknown currency.
    func nbuRate(_ code: String, on date: Date) async -> Double? {
        await nbuList(on: date)?.first { $0.cc == code }?.rate
    }

    /// Returns the latest NBU rate of `code` read in this launch, for use while offline.
    ///
    /// - Parameter code: An ISO 4217 code.
    /// - Returns: The rate, or `nil` if none was read.
    func lastKnownRate(_ code: String) -> Double? { lastKnown[code] }

    /// Gives entries saved with a stand-in rate the NBU rate for their date and recomputes their hryvnias.
    ///
    /// Asks nothing when no entry is estimated, so a hryvnia-only store makes no request.
    ///
    /// - Parameter context: The context to update and save.
    /// - Returns: How many entries were updated.
    @discardableResult
    func refreshEstimated(in context: ModelContext) async -> Int {
        let estimated =
            (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.isRateEstimated }))) ?? []
        var updated = 0
        for entry in estimated {
            guard let code = entry.currencyCode, let original = entry.originalAmount,
                let rate = await nbuRate(code, on: entry.date), !entry.isDeleted,
                let hryvnias = Currency.hryvnias(original, at: rate)
            else { continue }
            entry.rate = rate
            entry.amount = hryvnias
            entry.isRateEstimated = false
            updated += 1
        }
        if updated > 0 { try? context.save() }
        return updated
    }

    /// Returns the NBU's whole-day list for the Kyiv day of `date`, reading it at most once per day.
    ///
    /// Only the date leaves the phone. An empty or failed answer is not kept, so it is asked again later.
    private func nbuList(on date: Date) async -> [NBURate]? {
        let day = Currency.nbuDay(of: date)
        let task: Task<[NBURate]?, Never>
        if let pending = nbuLists[day] {
            task = pending
        } else {
            requestCount += 1
            var components = URLComponents(url: RatesHTTP.nbuURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "date", value: day), URLQueryItem(name: "json", value: nil)]
            let url = components.url!
            let transport = transport
            task = Task {
                guard let (status, body) = try? await transport.get(url), status == 200 else { return nil }
                return NBURate.list(from: body)
            }
            nbuLists[day] = task
        }
        let list = await task.value
        guard let list, !list.isEmpty else {
            if nbuLists[day] == task { nbuLists[day] = nil }
            return nil
        }
        for rate in list { lastKnown[rate.cc] = rate.rate }
        return list
    }

    /// Returns monobank's pairs, read at most once per ``monobankLifetime`` and never during a 429 pause.
    private func monobankPairs() async -> [MonobankPair]? {
        let start = now()
        if let monobank, start.timeIntervalSince(monobank.fetched) < Self.monobankLifetime { return monobank.pairs }
        guard start >= monobankPausedUntil else { return monobank?.pairs }
        requestCount += 1
        // Set before the request, so a second caller meanwhile does not ask too.
        monobankPausedUntil = start.addingTimeInterval(Self.monobankLifetime)
        guard let (status, body) = try? await transport.get(RatesHTTP.monobankURL) else {
            monobankPausedUntil = .distantPast
            return monobank?.pairs
        }
        if status == 429 {
            monobankPausedUntil = start.addingTimeInterval(Self.monobankBackoff)
            return monobank?.pairs
        }
        guard status == 200, let pairs = MonobankPair.list(from: body) else {
            monobankPausedUntil = .distantPast
            return monobank?.pairs
        }
        monobank = (start, pairs)
        return pairs
    }
}

extension Store {
    /// Returns the rate of the latest entry stored in `code`: the stand-in when nothing was read this launch.
    ///
    /// - Parameters:
    ///   - code: An ISO 4217 code.
    ///   - context: The context to search.
    /// - Returns: The rate, or `nil` if no entry in that currency has one.
    static func lastStoredRate(_ code: String, in context: ModelContext) -> Double? {
        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.currencyCode == code && $0.rate != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.rate
    }
}
