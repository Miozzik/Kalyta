import Foundation
import Security

/// The monobank personal API: https://api.monobank.ua/docs/ (spec v250818).
///
/// Only two read-only calls are used: `client-info` once to verify a token, and the
/// statement of the default account. Nothing from the responses is logged.
enum Monobank {
    /// The only host the app talks to; redirects elsewhere are refused.
    static let baseURL = URL(string: "https://api.monobank.ua")!
    /// The longest statement period the API serves: 31 days + 1 hour.
    static let window: TimeInterval = 2_682_000
    /// The item count at which a statement page may be cut short and the next one is fetched.
    static let pageLimit = 500
    /// The largest response body accepted, in bytes.
    static let maximumBodySize = 1_000_000
    /// The ISO 4217 numeric code of the hryvnia; the synced account must be in it.
    static let hryvniaNumericCode = 980
    /// The merchant category code of money transfers, recorded under "Transfers".
    static let transferMCC = 4829
    /// The most jars a `client-info` answer may list.
    static let maximumJarCount = 100
    /// The longest jar title kept.
    static let maximumJarTitleLength = 100
    /// The longest merchant description kept.
    static let maximumDescriptionLength = 200

    /// Returns whether a string has the shape of a personal token, before any request is made.
    ///
    /// - Parameter token: The text the person pasted or typed.
    /// - Returns: `true` if it is 20–128 letters, digits, `_` or `-`.
    static func isTokenShaped(_ token: String) -> Bool {
        token.wholeMatch(of: /[A-Za-z0-9_-]{20,128}/) != nil
    }

    /// The statement path for the default account, from `from` to `to` in Unix seconds.
    ///
    /// - Parameters:
    ///   - from: The start, inclusive.
    ///   - to: The end, inclusive.
    /// - Returns: A path relative to ``baseURL``.
    static func statementPath(from: Int, to: Int) -> String {
        // "0" is the default account, so no account id ever has to be read or kept.
        "/personal/statement/0/\(from)/\(to)"
    }

    /// The path that verifies a token.
    static let clientInfoPath = "/personal/client-info"

    /// Returns whether a redirect may be followed: only to the API host over HTTPS.
    ///
    /// - Parameter url: Where the redirect leads.
    /// - Returns: `true` if the redirect stays on ``baseURL``'s host.
    static func allowsRedirect(to url: URL?) -> Bool {
        SameHostRedirects.allows(url, sameHostAs: baseURL)
    }

    /// Decodes and checks one statement page, refusing the whole page if any item is off.
    ///
    /// - Parameters:
    ///   - data: The response body.
    ///   - from: The start of the requested period, in Unix seconds.
    ///   - to: The end of the requested period, in Unix seconds.
    ///   - now: The current time, in Unix seconds.
    /// - Returns: The items, with descriptions cleaned.
    /// - Throws: ``MonobankError/notHryvnia`` for an account in another currency, or
    ///   ``MonobankError/invalidResponse`` if the page is malformed or out of bounds.
    static func statementItems(from data: Data, from: Int, to: Int, now: Int) throws -> [StatementItem] {
        guard data.count <= maximumBodySize,
            let items = try? JSONDecoder().decode([StatementItem].self, from: data),
            items.count <= pageLimit
        else { throw MonobankError.invalidResponse }
        // The account's currency, not a bad item: it has its own message, since no retry helps.
        guard items.allSatisfy({ $0.currencyCode == hryvniaNumericCode }) else { throw MonobankError.notHryvnia }
        return try items.map { item in
            // Positive amounts are income and zero ones are not spending; both are skipped later.
            guard (-1_000_000_000...1_000_000_000).contains(item.amount),
                (1...64).contains(item.id.count), item.id.allSatisfy(\.isStatementIDCharacter),
                (from...to).contains(item.time), item.time <= now + 300,
                (0...9_999).contains(item.mcc)
            else { throw MonobankError.invalidResponse }
            var cleaned = item
            cleaned.description = visibleText(item.description, maximumLength: maximumDescriptionLength)
            return cleaned
        }
    }

    /// Decodes the titles of the person's jars from `client-info`, and nothing else.
    ///
    /// Used only to tell a top-up of the person's own jar from a transfer to someone else;
    /// the titles live in memory for one sync and are never stored or logged.
    ///
    /// - Parameter data: The response body.
    /// - Returns: The jar titles, cleaned and cut to ``maximumJarTitleLength``; empty if the
    ///   person has no jars. Titles that are empty after cleaning are left out.
    /// - Throws: ``MonobankError/invalidResponse`` if the body is malformed, too large or lists
    ///   too many jars; the caller then treats it as having no jars.
    static func jarTitles(from data: Data) throws -> [String] {
        struct ClientInfo: Decodable {
            struct Jar: Decodable { let title: String }
            let jars: [Jar]?
        }
        guard data.count <= maximumBodySize, let info = try? JSONDecoder().decode(ClientInfo.self, from: data),
            (info.jars ?? []).count <= maximumJarCount
        else { throw MonobankError.invalidResponse }
        return (info.jars ?? []).map { visibleText($0.title, maximumLength: maximumJarTitleLength) }.filter {
            !$0.isEmpty
        }
    }

    /// Returns text without control and invisible formatting characters, cut to a length.
    ///
    /// Formatting characters include the bidirectional overrides that could disguise a merchant name.
    private static func visibleText(_ text: String, maximumLength: Int) -> String {
        let visible = text.unicodeScalars.filter { ![.control, .format].contains($0.properties.generalCategory) }
        return String(String(String.UnicodeScalarView(visible)).prefix(maximumLength))
    }
}

/// One transaction of a monobank statement, with only the fields the app uses.
struct StatementItem: Decodable, Equatable {
    /// The transaction id, stable across a pending and a settled hold.
    let id: String
    /// When the transaction happened, in Unix seconds.
    let time: Int
    /// The merchant or transfer description; empty when the API leaves it out.
    var description: String
    /// The merchant category code (ISO 18245).
    let mcc: Int
    /// Whether the amount is still pending; `false` when the API leaves it out.
    let hold: Bool
    /// The amount in the account currency, in kopiykas; negative for spending.
    let amount: Int
    /// The account currency (ISO 4217 numeric).
    let currencyCode: Int

    private enum CodingKeys: String, CodingKey {
        case id, time, description, mcc, hold, amount, currencyCode
    }

    init(from decoder: Decoder) throws {
        // The spec marks no field required; only the ones the sync cannot work without are.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        time = try container.decode(Int.self, forKey: .time)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        mcc = try container.decode(Int.self, forKey: .mcc)
        hold = try container.decodeIfPresent(Bool.self, forKey: .hold) ?? false
        amount = try container.decode(Int.self, forKey: .amount)
        currencyCode = try container.decode(Int.self, forKey: .currencyCode)
    }

    /// Returns whether the item is spending to record.
    ///
    /// Income and zero amounts are skipped, and so is a transfer whose description names one
    /// of the person's own jars: that money is still theirs. Other transfers are spending.
    ///
    /// - Parameter jarTitles: The titles of the person's jars, from `client-info`.
    /// - Returns: `true` if the item should become an expense.
    func isRecordable(jarTitles: [String]) -> Bool {
        guard amount < 0 else { return false }
        guard mcc == Monobank.transferMCC else { return true }
        let place = Statistics.placeKey(description)
        // Known side effect: a jar titled like a person ("Олена") also hides transfers to that person.
        return !jarTitles.map(Statistics.placeKey).contains { !$0.isEmpty && place.contains($0) }
    }
}

/// Why talking to monobank failed; carries no token, id or URL.
enum MonobankError: Error, Equatable {
    /// The response was malformed, too large or out of bounds.
    case invalidResponse
    /// The default account is not in hryvnias.
    case notHryvnia
    /// The server answered with another status code.
    case status(Int)
    /// No answer: offline, timed out or refused.
    case offline
}

extension Character {
    /// Whether the character may appear in a statement id (Base64 and URL-safe Base64).
    fileprivate var isStatementIDCharacter: Bool {
        isASCII && (isLetter || isNumber || "+/=_-".contains(self))
    }
}

/// Sends one authenticated GET request to the monobank API.
///
/// A protocol so the self-check can answer with canned JSON instead of the network.
protocol MonobankTransport: Sendable {
    /// Requests `path` with the token.
    ///
    /// - Parameters:
    ///   - path: A path relative to ``Monobank/baseURL``.
    ///   - token: The personal token, sent only in the `X-Token` header.
    /// - Returns: The status code and the body.
    /// - Throws: ``MonobankError`` if no complete answer arrived.
    func get(_ path: String, token: String) async throws -> (status: Int, body: Data)
}

/// The real transport: an ephemeral session, so no statement is ever cached on disk.
struct MonobankHTTP: MonobankTransport {
    private static let session = URLSession(
        configuration: .ephemeral, delegate: SameHostRedirects(to: Monobank.baseURL), delegateQueue: nil)

    func get(_ path: String, token: String) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: Monobank.baseURL.appending(path: path))
        request.setValue(token, forHTTPHeaderField: "X-Token")
        request.timeoutInterval = 20
        do {
            let (bytes, response) = try await Self.session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw MonobankError.invalidResponse }
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                guard body.count <= Monobank.maximumBodySize else { throw MonobankError.invalidResponse }
            }
            return (http.statusCode, body)
        } catch let error as MonobankError {
            throw error
        } catch {
            // The URLError would carry the request URL; only the fact of failure is passed on.
            throw MonobankError.offline
        }
    }

}

/// Refuses redirects that leave one host or HTTPS; shared by the app's network sessions.
final class SameHostRedirects: NSObject, URLSessionTaskDelegate {
    private let base: URL

    /// Creates a guard for the host of `base`.
    ///
    /// - Parameter base: A URL on the only host redirects may lead to.
    init(to base: URL) { self.base = base }

    /// Returns whether a redirect stays on `base`'s host over HTTPS.
    ///
    /// - Parameters:
    ///   - url: Where the redirect leads.
    ///   - base: A URL on the allowed host.
    /// - Returns: `true` if the redirect may be followed.
    static func allows(_ url: URL?, sameHostAs base: URL) -> Bool {
        url?.scheme == "https" && url?.host != nil && url?.host == base.host
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        Self.allows(request.url, sameHostAs: base) ? request : nil
    }
}

/// The personal token in the Keychain: this device only, never synced or backed up elsewhere.
enum MonobankToken {
    /// The Keychain service, derived from the bundle id.
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "Kalyta") + ".monobank",
            kSecAttrAccount as String: "token",
            kSecAttrSynchronizable as String: false,
        ]
    }

    /// Stores the token, replacing any earlier one.
    ///
    /// - Parameter token: The verified token.
    /// - Returns: `true` if the Keychain accepted it.
    @discardableResult
    static func save(_ token: String) -> Bool {
        delete()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        // Readable by a background refresh after the first unlock; never moves to another device.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Reads the stored token.
    ///
    /// - Returns: The token, or `nil` if none is stored or the device has not been unlocked yet.
    static func read() -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess, let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the stored token, if any.
    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
