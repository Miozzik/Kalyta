import SwiftData
import SwiftUI

/// The currency of the entry being edited and the rate that turns it into hryvnias.
struct Conversion: Equatable {
    /// The ISO 4217 code of the amount field.
    var code = hryvniaCurrencyCode
    /// Hryvnias per unit, or `nil` while none is known.
    var rate: Double?
    /// Whether ``rate`` is a stand-in that the NBU rate for the entry's date should replace.
    var isEstimated = false
    /// Whether the person typed ``rate``; a new date or currency drops it.
    var isManual = false
    /// Whether ``rate`` is the edited entry's stored one, kept until its date or currency changes.
    var keepsStoredRate = false
    /// The rates shown under the amount, once read.
    var quote: RateQuote?
    /// Whether the rates are being read.
    var isLoading = false

    /// Starts in hryvnias.
    init() {}

    /// Starts from an entry's stored currency and rate.
    ///
    /// - Parameter expense: The entry being edited, or `nil` for a new one.
    init(_ expense: Expense?) {
        guard let expense, let code = expense.currencyCode else { return }
        self.code = code
        rate = expense.rate
        isEstimated = expense.isRateEstimated
        keepsStoredRate = true
    }

    /// Whether the amount field is in a currency other than hryvnias.
    var isForeign: Bool { code != hryvniaCurrencyCode }

    /// Returns the hryvnias to store for `amount` in ``code``.
    ///
    /// - Parameter amount: The amount field's value.
    /// - Returns: The hryvnias, or `nil` if the amount or the rate is missing or invalid.
    func hryvnias(for amount: Double?) -> Double? {
        guard let amount else { return nil }
        guard isForeign else { return isValidAmount(amount) ? amount : nil }
        return rate.flatMap { Currency.hryvnias(amount, at: $0) }
    }

    /// Drops a typed or stored rate, so the next read sets the rate for the new date or currency.
    mutating func dropRate() {
        isManual = false
        keepsStoredRate = false
    }

    /// Takes the rates read for the entry: the NBU rate for its date, else `fallback` as an estimate.
    ///
    /// A typed or stored rate stays; only the lines under it change.
    ///
    /// - Parameters:
    ///   - quote: The rates read, or `nil` for hryvnias.
    ///   - fallback: This launch's or the last stored rate of the currency, for use offline.
    mutating func apply(_ quote: RateQuote?, fallback: Double?) {
        self.quote = quote
        isLoading = false
        guard isForeign, !keepsStoredRate, !isManual else { return }
        if let nbu = quote?.nbuOnDate {
            rate = nbu
            isEstimated = false
        } else {
            rate = fallback
            isEstimated = fallback != nil
        }
    }
}

/// The currencies the menu offers.
enum CurrencyChoices {
    /// Offered until the person has used three currencies: hryvnias, then the dollar and the euro,
    /// the two foreign currencies Ukrainian banks and the NBU quote first.
    static let defaults = ["UAH", "USD", "EUR"]
    /// The `UserDefaults` key of the recent currencies, newest first, comma-separated.
    static let recentKey = "recentCurrencies"
    /// How many recent currencies replace ``defaults``.
    static let recentLimit = 3

    /// Returns the menu's currencies for the stored recent list.
    ///
    /// - Parameter recent: The stored value of ``recentKey``.
    /// - Returns: The recent currencies once there are ``recentLimit``, else ``defaults``.
    static func menu(recent: String) -> [String] {
        let codes = parse(recent)
        return codes.count >= recentLimit ? codes : defaults
    }

    /// Returns the recent list with `code` moved to the front.
    ///
    /// - Parameters:
    ///   - code: The currency just saved.
    ///   - recent: The stored value of ``recentKey``.
    /// - Returns: The new stored value.
    static func remembering(_ code: String, in recent: String) -> String {
        ([code] + parse(recent).filter { $0 != code }).prefix(recentLimit).joined(separator: ",")
    }

    /// Returns the currency's name in the person's language, such as "US Dollar".
    ///
    /// - Parameter code: An ISO 4217 code.
    /// - Returns: The name, or the code if the system has none.
    static func name(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    /// Returns the sign shown next to the amount field: "₴" for hryvnias, else the locale's symbol.
    ///
    /// - Parameter code: An ISO 4217 code.
    /// - Returns: A symbol such as "$", or the code itself.
    static func symbol(_ code: String) -> String {
        guard code != hryvniaCurrencyCode else { return "₴" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol
    }

    private static func parse(_ recent: String) -> [String] {
        recent.split(separator: ",").map(String.init).filter(Currency.isCurrencyCode)
    }
}

/// The currency sign next to the amount: a menu of recent currencies and «Інша…» for the full list.
struct CurrencyMenu: View {
    @Binding var code: String
    @AppStorage(CurrencyChoices.recentKey) private var recent = ""
    @State private var isPickingOther = false

    var body: some View {
        Menu {
            Picker("Currency", selection: $code) {
                ForEach(CurrencyChoices.menu(recent: recent), id: \.self) { code in
                    Text(verbatim: "\(code) — \(CurrencyChoices.name(code))").tag(code)
                }
            }
            Button("Other…") { isPickingOther = true }
        } label: {
            Text(verbatim: CurrencyChoices.symbol(code)).foregroundStyle(.secondary)
        }
        .accessibilityLabel("Currency")
        .accessibilityValue(CurrencyChoices.name(code))
        .accessibilityIdentifier("currencyMenu")
        .sheet(isPresented: $isPickingOther) { CurrencyList(code: $code) }
    }
}

/// Every common currency, searchable by code or name.
private struct CurrencyList: View {
    @Binding var code: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var codes: [String] {
        Locale.commonISOCurrencyCodes.filter {
            search.isEmpty || $0.localizedCaseInsensitiveContains(search)
                || CurrencyChoices.name($0).localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(codes, id: \.self) { item in
                Button {
                    code = item
                    dismiss()
                } label: {
                    HStack {
                        Text(CurrencyChoices.name(item)).foregroundStyle(.primary)
                        Spacer()
                        Text(verbatim: item).foregroundStyle(.secondary)
                    }
                }
                .accessibilityAddTraits(item == code ? .isSelected : [])
            }
            .searchable(text: $search)
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// «У гривнях» under the amount: what will be recorded at which rate, and today's NBU and monobank rates.
///
/// Every line keeps its place while the rates load, so the layout does not jump.
struct HryvniaPreview: View {
    @Binding var conversion: Conversion
    /// The amount field's value, in ``Conversion/code``.
    let amount: Double?
    /// The entry's date, named next to the rate.
    let date: Date
    @State private var isEditingRate = false
    @FocusState private var isRateFocused: Bool

    /// The rate field writes a typed rate, which no read replaces until the date or currency changes.
    private var typedRate: Binding<Double?> {
        Binding {
            conversion.rate
        } set: {
            conversion.rate = $0
            conversion.isManual = true
            conversion.isEstimated = false
            conversion.keepsStoredRate = false
        }
    }

    /// Whether no rate is known at all, so the person has to type one.
    private var needsRate: Bool { conversion.rate == nil && !conversion.isLoading }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In hryvnias")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Group {
                if let hryvnias = conversion.hryvnias(for: amount) {
                    Text(verbatim: "≈ " + formattedHryvnias(hryvnias))
                } else {
                    Text(verbatim: "≈ —")
                }
            }
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .accessibilityIdentifier("hryvniaPreview")
            rateLine
            if isEditingRate || needsRate {
                TextField("Rate", value: typedRate, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($isRateFocused)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("rateField")
            }
            todayLines
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .onChange(of: conversion.code) { isEditingRate = false }
    }

    @ViewBuilder private var rateLine: some View {
        let day = date.formatted(.dateTime.day().month())
        if let rate = conversion.rate {
            Button {
                isEditingRate = true
                isRateFocused = true
            } label: {
                let shown = formattedRate(rate)
                if conversion.isEstimated {
                    Text("Estimated rate \(shown) · check")
                } else if conversion.isManual {
                    Text("Your rate \(shown) · change")
                } else if conversion.keepsStoredRate {
                    Text("Rate \(shown) on \(day) · change")
                } else {
                    Text("NBU \(shown) on \(day) · change")
                }
            }
            .accessibilityIdentifier("rateLine")
        } else if conversion.isLoading {
            Text(verbatim: "NBU 00,00 · 00.00").redacted(reason: .placeholder)
        } else if conversion.quote?.nbuAnswered == true {
            Text("The NBU has no rate for this currency — enter it").foregroundStyle(.orange)
        } else {
            Text("No rate without a network — enter it").foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var todayLines: some View {
        Group {
            if let today = conversion.quote?.nbuToday {
                Text("NBU today: \(formattedRate(today))")
            } else {
                Text(verbatim: "NBU 00,00").redacted(reason: conversion.isLoading ? .placeholder : [])
                    .opacity(conversion.isLoading ? 1 : 0)
            }
            switch conversion.quote?.monobank {
            case .buys(let rate): Text("monobank today buys at \(formattedRate(rate))")
            case .sells(let rate): Text("monobank today sells at \(formattedRate(rate))")
            case .cross(let rate): Text("monobank today: \(formattedRate(rate))")
            case nil:
                Text(verbatim: "monobank 00,00").redacted(reason: conversion.isLoading ? .placeholder : [])
                    .opacity(conversion.isLoading ? 1 : 0)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// What reads an entry's rates: the currency, the Kyiv day and the kind.
struct RateRequest: Hashable {
    let code: String
    let day: String
    let isIncome: Bool
}
