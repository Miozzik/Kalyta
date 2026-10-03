import Foundation

/// Formats an amount as hryvnias, for example "42,50 ₴" or "100 ₴".
///
/// Kopiykas are shown either in full or not at all: a `0...2` precision range
/// renders 42.5 as "42,5 ₴", which reads like a typo.
///
/// - Parameters:
///   - amount: The amount in hryvnias.
///   - showsPlus: Whether to mark the amount as money received with a plus sign, placed
///     where the locale puts signs.
/// - Returns: The amount formatted in the current locale.
func formattedHryvnias(_ amount: Double, showsPlus: Bool = false) -> String {
    formattedAmount(amount, currencyCode: hryvniaCurrencyCode, showsPlus: showsPlus)
}

/// Formats an amount in any currency with the same kopiyka rule as ``formattedHryvnias(_:showsPlus:)``.
///
/// - Parameters:
///   - amount: The amount in `currencyCode`.
///   - currencyCode: An ISO 4217 code, such as "USD".
///   - showsPlus: Whether to mark the amount as money received with a plus sign.
/// - Returns: The amount formatted in the current locale, such as "+100 $".
func formattedAmount(_ amount: Double, currencyCode: String, showsPlus: Bool = false) -> String {
    let fractionDigits = amount == amount.rounded() ? 0 : 2
    let style = FloatingPointFormatStyle<Double>.Currency(code: currencyCode)
        .precision(.fractionLength(fractionDigits))
    return amount.formatted(showsPlus ? style.sign(strategy: .always()) : style)
}

/// Formats an exchange rate: two decimals from one hryvnia up, four significant digits below it,
/// so 44.9729 reads "44,97" and the yen's 0.289 keeps its digits.
///
/// - Parameter rate: Hryvnias per unit.
/// - Returns: The rate in the current locale.
func formattedRate(_ rate: Double) -> String {
    rate >= 1
        ? rate.formatted(.number.precision(.fractionLength(2)))
        : rate.formatted(.number.precision(.significantDigits(1...4)))
}

/// The ISO 4217 code of the hryvnia, the currency every amount in the app is in.
let hryvniaCurrencyCode = "UAH"
