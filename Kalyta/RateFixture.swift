#if DEBUG
    import Foundation

    /// Canned rates answers for UI tests, the self-check and design reviews, chosen with `-rateFixture <name>`.
    ///
    /// Names: `friday` (the NBU's list for Friday 25.09.2026 with USD 44.9729, EUR, PLN and gold, and monobank's
    /// pairs: USD and EUR with buy and sell, PLN cross only), `empty` (the NBU's `[]` for a future day),
    /// `offline`, `rateLimited` (429) and `malformed` (a rate given as text).
    /// Debug builds only; nothing here reaches the network.
    struct RateFixture: RateTransport {
        /// The scenario name from the launch argument.
        let name: String

        /// The NBU's USD rate in the `friday` list.
        static let fridayUSD = 44.9729

        func get(_ url: URL) async throws -> (status: Int, body: Data) {
            switch name {
            case "offline": throw URLError(.notConnectedToInternet)
            case "rateLimited": return (429, Data(#"{"errorDescription":"Too many requests"}"#.utf8))
            case "empty": return (200, Data("[\n]".utf8))
            default: break
            }
            if url.host == RatesHTTP.monobankURL.host {
                let pairs = """
                    [{"currencyCodeA":840,"currencyCodeB":980,"date":1790860573,"rateBuy":44.8,"rateSell":45.1998},
                    {"currencyCodeA":978,"currencyCodeB":980,"date":1790860573,"rateBuy":50.55,"rateSell":51.2505},
                    {"currencyCodeA":978,"currencyCodeB":840,"date":1790842573,"rateBuy":1.127,"rateSell":1.137},
                    {"currencyCodeA":985,"currencyCodeB":980,"date":1790878873,"rateCross":11.7898}]
                    """
                return (200, Data(pairs.utf8))
            }
            let usd = name == "malformed" ? #""44.9729""# : "\(Self.fridayUSD)"
            let list = """
                [{"r030":840,"txt":"Долар США","rate":\(usd),"cc":"USD","exchangedate":"25.09.2026","special":null},
                {"r030":978,"txt":"Євро","rate":52.6412,"cc":"EUR","exchangedate":"25.09.2026","special":null},
                {"r030":985,"txt":"Злотий","rate":12.3389,"cc":"PLN","exchangedate":"25.09.2026","special":null},
                {"r030":959,"txt":"Золото","rate":191676.39,"cc":"XAU","exchangedate":"25.09.2026","special":null}]
                """
            return (200, Data(list.utf8))
        }
    }
#endif
