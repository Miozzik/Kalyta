import BackgroundTasks
import Foundation
import SwiftData
import UIKit

/// Records monobank card payments as expenses, once the person has connected a token.
///
/// Runs when the app becomes active and in an opportunistic background refresh, at most
/// once per ``throttle``. Each run fetches one statement page: the whole allowed window
/// the first time, then from shortly before the last complete sync, so a pending payment
/// (a hold) is fetched again and updated when it settles.
enum MonobankSync {
    /// The shortest time between two requests; the API allows one per 60 s.
    static let throttle: TimeInterval = 60
    /// How far back each sync re-fetches, so pending payments are updated when they settle.
    static let holdWindow: TimeInterval = 3 * 86_400
    /// The `UserDefaults` key of the "connected" flag, which the Keychain item outlives.
    static let linkedKey = "monobankLinked"
    /// The `UserDefaults` key of the encoded ``State``.
    static let stateKey = "monobankSync"
    /// The background refresh task identifier, also listed in `Info.plist`.
    static var refreshTaskID: String { (Bundle.main.bundleIdentifier ?? "Kalyta") + ".monobank" }

    /// Where the sync stands between launches.
    struct State: Codable, Equatable {
        /// When the last request was sent, successful or not; the throttle counts from it.
        var lastAttempt: Date?
        /// The end of the last period fetched completely, in Unix seconds.
        var syncedUntil: Int?
        /// The end of the next, older page when the last page came back full.
        var pageCursor: Int?
        /// The end of the first page of the paging run in progress.
        var pagingStart: Int?
        /// When the last sync succeeded.
        var lastSuccess: Date?
        /// The outcome of the last attempt, for the status line.
        var problem: Problem?
        /// The opaque id of the synced hryvnia account, from the last readable `client-info`;
        /// kept so a sync can go on when `client-info` is rate-limited. Not an IBAN or card number.
        var account: String?
    }

    /// Why the last attempt did not update the entries.
    enum Problem: String, Codable {
        /// HTTP 429: monobank asked to wait.
        case rateLimited
        /// No answer from the server.
        case offline
        /// HTTP 401 or 403: the token is no longer accepted.
        case rejected
        /// The person has no hryvnia account, so nothing can be recorded.
        case notHryvnia
        /// Anything else, including a response that failed validation.
        case failed
    }

    /// Returns the period to fetch next, or `nil` while the throttle holds.
    ///
    /// - Parameters:
    ///   - state: The stored state.
    ///   - now: The current time.
    /// - Returns: The start and end in Unix seconds, both inclusive.
    static func period(for state: State, now: Date) -> ClosedRange<Int>? {
        if let last = state.lastAttempt, now.timeIntervalSince(last) < throttle { return nil }
        let end = Int(now.timeIntervalSince1970)
        let earliest = end - Int(Monobank.window)
        let start = max(earliest, state.syncedUntil.map { $0 - Int(holdWindow) } ?? earliest)
        let to = state.pageCursor ?? end
        return start <= to ? start...to : nil
    }

    /// Returns the state after a page for `period` arrived.
    ///
    /// A full page may have been cut short, so the next sync fetches the older part up to
    /// its oldest item; the sync counts as complete once a page comes back shorter.
    ///
    /// - Parameters:
    ///   - state: The state before the page.
    ///   - period: The period requested.
    ///   - items: The page.
    ///   - now: The current time.
    /// - Returns: The new state.
    static func state(after state: State, period: ClosedRange<Int>, items: [StatementItem], now: Date) -> State {
        var next = state
        next.lastSuccess = now
        next.problem = nil
        if items.count == Monobank.pageLimit, let oldest = items.map(\.time).min(), oldest > period.lowerBound,
            oldest < period.upperBound
        {
            next.pagingStart = state.pagingStart ?? period.upperBound
            next.pageCursor = oldest
        } else {
            next.syncedUntil = state.pagingStart ?? period.upperBound
            next.pageCursor = nil
            next.pagingStart = nil
        }
        return next
    }

    /// Records the spending of a page: updates entries it already has, merges with an
    /// entry the Wallet automation recorded, and adds the rest.
    ///
    /// - Parameters:
    ///   - items: A validated page.
    ///   - jarTitles: The titles of the person's jars, so top-ups of them are skipped.
    ///   - context: The context to write; the built-ins must exist in it.
    /// - Returns: How many entries were added.
    /// - Throws: An error if saving fails.
    @discardableResult
    static func record(_ items: [StatementItem], jarTitles: [String], in context: ModelContext) throws -> Int {
        let linked = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.bankID != nil }))
        var byID = Dictionary(linked.map { ($0.bankID!, $0) }, uniquingKeysWith: { first, _ in first })
        var memory: MerchantMemory?
        var added = 0
        for item in items where item.isRecordable(jarTitles: jarTitles) {
            let amount = Double(-item.amount) / 100
            let date = Date(timeIntervalSince1970: TimeInterval(item.time))
            if let existing = byID[item.id] {
                // A pending payment settles with its final amount under the same id.
                existing.amount = amount
                existing.date = date
            } else if let match = Store.matchingExpense(amount: amount, date: date, unlinkedOnly: true, in: context) {
                match.bankID = item.id
                byID[item.id] = match
            } else {
                memory = memory ?? MerchantMemory(context: context)
                let category = Store.category(forMerchant: item.description, mcc: item.mcc, memory: memory, in: context)
                let expense = Expense(
                    amount: amount, category: category, note: item.description, date: date, bankID: item.id)
                context.insert(expense)
                byID[item.id] = expense
                added += 1
            }
        }
        try context.save()
        return added
    }

    /// Runs one sync if the throttle allows, and stores the outcome.
    ///
    /// - Parameters:
    ///   - token: The personal token.
    ///   - transport: How requests are sent.
    ///   - context: The context to write.
    ///   - defaults: Where ``State`` is kept.
    ///   - knownClientInfo: A `client-info` body already fetched, so the run does not call it
    ///     again; `nil` to fetch it now.
    ///   - now: The current time.
    @MainActor
    static func run(
        token: String, transport: MonobankTransport, context: ModelContext, defaults: UserDefaults,
        knownClientInfo: Data? = nil, now: Date = .now
    ) async {
        var state = loadState(from: defaults)
        guard let period = period(for: state, now: now) else { return }
        // Stored before the request, so a second trigger meanwhile sees the throttle.
        state.lastAttempt = now
        save(state, to: defaults)
        do {
            // client-info names the hryvnia account and the jars, whose titles tell own top-ups from
            // transfers to others; the titles live only in this local. Without it (429, offline, a
            // malformed answer) every transfer is imported and the stored account is synced; only a
            // rejected token stops the run, since the statement would fail the same way.
            var info = knownClientInfo
            var infoError = MonobankError.invalidResponse
            if info == nil {
                do {
                    let answer = try await transport.get(Monobank.clientInfoPath, token: token)
                    if answer.status == 200 { info = answer.body } else { infoError = .status(answer.status) }
                } catch let error as MonobankError {
                    infoError = error
                }
                if infoError == .status(401) || infoError == .status(403) { throw infoError }
            }
            let jarTitles = info.flatMap { try? Monobank.jarTitles(from: $0) } ?? []
            if let info, case .success(let found) = Result(catching: { try Monobank.hryvniaAccount(from: info) }) {
                state.account = found
                guard found != nil else { throw MonobankError.notHryvnia }
            }
            // An account closed since it was stored fails this statement; the next readable
            // client-info replaces it.
            guard let account = state.account else { throw infoError }
            let (status, body) = try await transport.get(
                Monobank.statementPath(account: account, from: period.lowerBound, to: period.upperBound), token: token)
            guard status == 200 else { throw MonobankError.status(status) }
            let items = try Monobank.statementItems(
                from: body, from: period.lowerBound, to: period.upperBound, now: Int(now.timeIntervalSince1970))
            try Store.ensureCategories(in: context)
            try record(items, jarTitles: jarTitles, in: context)
            state = self.state(after: state, period: period, items: items, now: now)
        } catch {
            state.problem = problem(for: error)
        }
        save(state, to: defaults)
    }

    /// Returns the status line's case for an error.
    ///
    /// - Parameter error: What ``run(token:transport:context:defaults:now:)`` caught.
    /// - Returns: The problem to show.
    static func problem(for error: Error) -> Problem {
        switch error as? MonobankError {
        case .status(429): .rateLimited
        case .status(401), .status(403): .rejected
        case .offline: .offline
        case .notHryvnia: .notHryvnia
        default: .failed
        }
    }

    /// Syncs with the stored token, if monobank is connected, and schedules the next background refresh.
    @MainActor
    static func runIfLinked() async {
        guard UserDefaults.standard.bool(forKey: linkedKey), let token = MonobankToken.read() else { return }
        await run(token: token, transport: transport, context: Store.container.mainContext, defaults: .standard)
        scheduleRefresh()
    }

    /// Asks for the next opportunistic background refresh, about an hour from now.
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(3_600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Verifies a token with one `client-info` call and, if accepted, stores it and runs the first sync.
    ///
    /// The first sync reuses this call's account and jar titles. `client-info` allows one call per 60 s, so
    /// asking again would get 429, and a month of jar top-ups would be imported as transfers
    /// for good, since later syncs go back only 3 days.
    ///
    /// - Parameters:
    ///   - token: A token of the right shape.
    ///   - transport: How requests are sent.
    ///   - context: The context to write.
    ///   - defaults: Where the linked flag and ``State`` are kept.
    ///   - saveToken: Stores the accepted token; the Keychain by default.
    ///   - now: The current time.
    /// - Returns: The status of `client-info`; 200 means connected and synced once.
    /// - Throws: ``MonobankError`` if no answer arrived, or `.status(200)` if the token could not be stored.
    @MainActor
    static func connect(
        token: String, transport: MonobankTransport, context: ModelContext, defaults: UserDefaults,
        saveToken: (String) -> Bool = MonobankToken.save, now: Date = .now
    ) async throws -> Int {
        let (status, body) = try await transport.get(Monobank.clientInfoPath, token: token)
        guard status == 200 else { return status }
        guard saveToken(token) else { throw MonobankError.status(status) }
        defaults.set(true, forKey: linkedKey)
        // The body lives only in this call and the run it starts.
        await run(
            token: token, transport: transport, context: context, defaults: defaults, knownClientInfo: body, now: now)
        return status
    }

    /// The transport for real use; debug builds answer from a canned scenario with
    /// `-monobankFixture <name>`, see ``MonobankFixture``.
    static var transport: MonobankTransport {
        #if DEBUG
            if let name = UserDefaults.standard.string(forKey: "monobankFixture") { return MonobankFixture(name: name) }
        #endif
        return MonobankHTTP()
    }

    /// Forgets the token and the sync state; recorded entries stay.
    static func disconnect() {
        MonobankToken.delete()
        UserDefaults.standard.removeObject(forKey: linkedKey)
        UserDefaults.standard.removeObject(forKey: stateKey)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
    }

    /// Deletes a token left in the Keychain by an earlier install.
    ///
    /// The Keychain outlives deleting the app, but `UserDefaults` does not: a token without
    /// the flag belongs to an install the person already removed. Before the first unlock the
    /// flag reads as missing, so nothing is deleted until protected data is available.
    @MainActor
    static func removeOrphanedToken() {
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        if !UserDefaults.standard.bool(forKey: linkedKey) { MonobankToken.delete() }
    }

    /// Reads the stored state.
    ///
    /// - Parameter defaults: Where the state is kept.
    /// - Returns: The state, or an empty one.
    static func loadState(from defaults: UserDefaults) -> State {
        defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    private static func save(_ state: State, to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(state), forKey: stateKey)
    }
}
