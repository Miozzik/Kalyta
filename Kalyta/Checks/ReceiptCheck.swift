import Foundation
import SwiftData

/// Verifies fiscal receipt parsing and the match with an already recorded expense.
///
/// Parses sample links, including ones that must be refused, and checks the Kyiv time
/// of a summer and a winter receipt against epochs computed independently. Matching runs
/// on a temporary store, so the person's data is never touched.
@MainActor
func runReceiptCheck() {
    let later = Date(timeIntervalSince1970: 2_000_000_000)
    func receipt(_ query: String, now: Date = later) -> FiscalReceipt? {
        FiscalReceipt(payload: "https://cabinet.tax.gov.ua/cashregs/check?" + query, now: now)
    }
    // 2026-07-15 12:18 in Kyiv is 09:18 UTC in summer (UTC+3).
    let summer = Date(timeIntervalSince1970: 1_784_107_080)
    let full = "mac=4F2A&date=20260715&time=1218&id=1911&sm=432.90&fn=4000123456"

    let parsed = receipt(full)
    assert(parsed?.amount == 432.9, "Receipt amount not read: \(String(describing: parsed))")
    assert(parsed?.date == summer, "Summer receipt not in Kyiv time: \(String(describing: parsed?.date))")
    assert(receipt("date=20260715&time=121830&id=1911&sm=432.90")?.date == summer + 30, "HHmmss time refused")
    assert(receipt("id=1911&date=20260715&time=1218&sm=432.90&fn=1")?.date == summer, "A receipt without mac refused")
    assert(receipt("sm=432.90&fn=1&time=1218&mac=4F2A&date=20260715") == parsed, "Reordered parameters refused")
    assert(receipt("date=20260715&time=1218&sm=780")?.amount == 780, "A whole amount refused")
    assert(
        receipt("date=20260115&time=1218&sm=1")?.date == Date(timeIntervalSince1970: 1_768_472_280),
        "Winter receipt not in Kyiv time (UTC+2)")
    assert(receipt(full, now: summer - 60)?.date == summer - 60, "A future receipt was not clamped to now")

    assert(FiscalReceipt(payload: "WIFI:S:Home;T:WPA;P:secret;;") == nil, "A Wi-Fi code was taken for a receipt")
    assert(
        FiscalReceipt(payload: "https://cabinet.tax.gov.ua.evil.com/cashregs/check?" + full) == nil,
        "A look-alike host was accepted")
    assert(
        FiscalReceipt(payload: "ftp://cabinet.tax.gov.ua/cashregs/check?" + full) == nil,
        "A non-https link was accepted")
    assert(receipt("date=20260715&time=1218&sm=10000000")?.amount == 10_000_000, "The largest amount was refused")
    for broken in [
        "date=20260715&time=1218", "time=1218&sm=432.90", "date=20261341&time=1218&sm=1",
        "date=20260715&time=1218&sm=0", "date=20260715&time=1218&sm=-5", "date=20260715&time=1218&sm=abc",
        "date=20260715&time=1218&sm=nan", "date=20260715&time=1218&sm=inf",
        "date=20260715&time=1218&sm=1e308", "date=20260715&time=1218&sm=0x10",
        "date=20260715&time=1218&sm=10000000.01", "date=00010101&time=1218&sm=1", "date=20180715&time=1218&sm=1",
        "date=20990101&time=1218&sm=1",
    ] {
        assert(receipt(broken) == nil, "A broken receipt was accepted: \(broken)")
    }

    let url = FileManager.default.temporaryDirectory.appending(path: "selfcheck-receipt-\(UUID().uuidString).store")
    defer { removeStore(at: url) }
    let context = ModelContext(try! Store.makeContainer(url: url))
    try! Store.ensureCategories(in: context)
    let food = Store.category(withKey: Category.food.rawValue, in: context)!
    let salary = Store.category(withKey: Category.income.rawValue, in: context)!
    /// Inserts an entry at a Kyiv time on a July 2026 day.
    func record(_ amount: Double, day: Int, time: String, note: String, isIncome: Bool = false) {
        let date = receipt("date=202607\(day)&time=\(time)&sm=1")!.date
        context.insert(
            Expense(
                amount: amount, category: isIncome ? salary : food, note: note, date: date, isIncome: isIncome))
    }
    record(432.90, day: 15, time: "1218", note: "window")
    record(432.904, day: 16, time: "1218", note: "kopiyka")
    record(250, day: 17, time: "1218", note: "income", isIncome: true)
    // The nearest is inserted between two farther ones, so taking the first or last fetched one fails.
    record(77, day: 18, time: "1200", note: "far")
    record(77, day: 18, time: "1210", note: "near")
    record(77, day: 18, time: "1240", note: "far")
    try! context.save()
    func match(_ query: String) -> String? { receipt(query)!.matchingExpense(in: context)?.note }

    assert(match("date=20260715&time=1248&sm=432.90") == "window", "A receipt exactly 30 min later did not match")
    assert(match("date=20260715&time=1148&sm=432.90") == "window", "A receipt exactly 30 min earlier did not match")
    assert(match("date=20260715&time=1249&sm=432.90") == nil, "A receipt 31 min later matched")
    assert(match("date=20260716&time=1218&sm=432.90") == "kopiyka", "Amounts within half a kopiyka did not match")
    assert(match("date=20260716&time=1218&sm=432.91") == nil, "Amounts a kopiyka apart matched")
    assert(match("date=20260717&time=1218&sm=250") == nil, "A receipt matched income")
    assert(match("date=20260718&time=1218&sm=77") == "near", "The nearest of three candidates did not win")
}
