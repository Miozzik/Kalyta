import Foundation

/// Formats an amount as hryvnias, for example "42,50 ₴" or "100 ₴".
///
/// Kopiykas are shown either in full or not at all: a `0...2` precision range
/// renders 42.5 as "42,5 ₴", which reads like a typo.
///
/// - Parameter amount: The amount in hryvnias.
/// - Returns: The amount formatted in the current locale.
func formattedHryvnias(_ amount: Double) -> String {
    let fractionDigits = amount == amount.rounded() ? 0 : 2
    return amount.formatted(.currency(code: hryvniaCurrencyCode).precision(.fractionLength(fractionDigits)))
}

/// The ISO 4217 code of the hryvnia, the currency every amount in the app is in.
let hryvniaCurrencyCode = "UAH"
