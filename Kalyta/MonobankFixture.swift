#if DEBUG
    import Foundation

    /// Canned monobank answers for UI tests and design reviews, chosen with `-monobankFixture <name>`.
    ///
    /// Names: `ok` (a jar, a grocery payment, a pending taxi ride, a transfer to a person, a jar
    /// top-up and a salary), `rejected` (401), `rateLimited` (429), `offline`, and `notHryvnia`.
    /// Any token of the right shape connects. Debug builds only; nothing here reaches the network.
    struct MonobankFixture: MonobankTransport {
        /// The scenario name from the launch argument.
        let name: String
        /// How long `client-info` takes, so "Checking…" stays on screen long enough to see.
        var clientInfoDelay: Duration = .seconds(2)

        func get(_ path: String, token: String) async throws -> (status: Int, body: Data) {
            if path == Monobank.clientInfoPath { try? await Task.sleep(for: clientInfoDelay) }
            switch name {
            case "rejected": return (401, Data(#"{"errorDescription":"Unknown 'X-Token'"}"#.utf8))
            case "rateLimited": return (429, Data(#"{"errorDescription":"Too many requests"}"#.utf8))
            case "offline": throw MonobankError.offline
            default: break
            }
            guard path.hasPrefix("/personal/statement/") else {
                return (200, Data(#"{"clientId":"fixture","name":"Fixture","jars":[{"title":"На відпустку"}]}"#.utf8))
            }
            // The items sit just before the end of the requested period, so they always fall inside it.
            let end = Int(path.split(separator: "/").last!)!
            let currency = name == "notHryvnia" ? 840 : Monobank.hryvniaNumericCode
            let items: [[String: Any]] = [
                ["id": "fx-silpo", "time": end - 3_600, "description": "Сільпо", "mcc": 5411, "amount": -24_890],
                [
                    "id": "fx-uklon", "time": end - 1_800, "description": "Uklon", "mcc": 4121, "amount": -12_000,
                    "hold": true,
                ],
                ["id": "fx-olena", "time": end - 7_200, "description": "Олена К.", "mcc": 4829, "amount": -30_000],
                [
                    "id": "fx-jar", "time": end - 5_400, "description": "На банку «На відпустку»", "mcc": 4829,
                    "amount": -50_000,
                ],
                ["id": "fx-salary", "time": end - 9_000, "description": "Зарплата", "mcc": 4829, "amount": 1_000_000],
            ]
            let page = items.map { $0.merging(["currencyCode": currency]) { current, _ in current } }
            return (200, try JSONSerialization.data(withJSONObject: page))
        }
    }
#endif
