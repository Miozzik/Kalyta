import Foundation
import UIKit

/// Verifies the limits on untrusted input: CSV rows and files, and downloaded icons.
@MainActor
func runHardeningCheck() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// Returns the lines an import of `records` refuses.
    func refused(_ records: [ExpenseRecord], kinds: [String: Bool] = [:]) -> [Int] {
        let csv = ExpenseCSV.document(for: records)
        return (try? ExpenseImport.plan(csv: csv, existing: [], categoryKinds: kinds, now: now).invalidLines) ?? [-1]
    }
    func row(
        daysFromNow days: Double = 0, key: String = "food", name: String = "Їжа", note: String = "",
        isIncome: Bool = false
    ) -> ExpenseRecord {
        ExpenseRecord(
            date: now + days * 86_400, amount: 1, categoryKey: key, categoryName: name, note: note, isIncome: isIncome)
    }
    let ok = row(daysFromNow: -1)

    // Dates: from 2000-01-01 to a day ahead, for time zones and a slow clock.
    assert(refused([ok, row(daysFromNow: 0.5)]) == [], "A valid date was refused")
    let before2000 = ExpenseRecord(
        date: ExpenseImport.earliestDate - 1, amount: 1, categoryKey: "food", categoryName: "Їжа", note: "")
    assert(refused([ok, before2000]) == [3], "A date before 2000 was accepted")
    assert(refused([ok, row(daysFromNow: 1.1)]) == [3], "A date more than a day ahead was accepted")

    // Text limits: key 64, name 100, note 1000.
    let longKey = String(repeating: "k", count: 64)
    assert(refused([ok, row(key: longKey, name: "x")]) == [], "A 64-character key was refused")
    assert(refused([ok, row(key: longKey + "k", name: "x")]) == [3], "A 65-character key was accepted")
    assert(refused([ok, row(key: "c1", name: String(repeating: "н", count: 101))]) == [3], "A long name was accepted")
    assert(refused([ok, row(note: String(repeating: "н", count: 1_000))]) == [], "A 1000-character note was refused")
    assert(refused([ok, row(note: String(repeating: "н", count: 1_001))]) == [3], "A long note was accepted")

    // Kind must match the category: built-ins, stored custom ones, and new ones named twice.
    assert(refused([ok, row(isIncome: true)]) == [3], "Income was accepted into Food")
    assert(refused([ok, row(key: "income", name: "Дохід")]) == [3], "Spending was accepted into Income")
    assert(refused([ok, row(key: "c2", name: "Кафе")], kinds: ["c2": true]) == [3], "Kind contradicts the store")
    let firstIncome = row(key: "c3", name: "Премія", isIncome: true)
    assert(refused([ok, firstIncome, row(key: "c3", name: "Премія")]) == [4], "One new key took both kinds")

    // Reading: capped by bytes read, not by the reported size; UTF-8 only.
    let file = FileManager.default.temporaryDirectory.appending(path: "selfcheck-read-\(UUID().uuidString).csv")
    defer { try? FileManager.default.removeItem(at: file) }
    func read(_ data: Data) -> Result<String, ImportError> {
        try! data.write(to: file)
        do { return .success(try ExpenseImport.readText(from: file, limit: 10)) } catch {
            return .failure(error as? ImportError ?? .notKalytaExport)
        }
    }
    assert(read(Data("0123456789".utf8)) == .success("0123456789"), "A file at the limit was refused")
    assert(read(Data("0123456789a".utf8)) == .failure(.tooLarge), "A file over the limit was read")
    assert(read(Data([0xFF, 0xFE, 0x00])) == .failure(.notKalytaExport), "Bytes that are not UTF-8 were read")
    // An endless stream reports no size: only a capped read returns. The watchdog turns a hang into a failure.
    let finished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        _ = try? ExpenseImport.readText(from: URL(filePath: "/dev/zero"), limit: 10)
        finished.signal()
    }
    assert(finished.wait(timeout: .now() + 2) == .success, "The import read past its limit")

    // Icons: no redirect off the host, no image larger than 1024 px per side.
    let icons = URL(string: "https://cdn.jsdelivr.net/gh/x/png")!
    assert(
        SameHostRedirects.allows(URL(string: "https://cdn.jsdelivr.net/other.png"), sameHostAs: icons)
            && !SameHostRedirects.allows(URL(string: "https://evil.example/a.png"), sameHostAs: icons)
            && !SameHostRedirects.allows(URL(string: "http://cdn.jsdelivr.net/a.png"), sameHostAs: icons),
        "An icon redirect off the host was allowed")
    func png(_ width: Int, _ height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { _ in }
    }
    let largest = png(1_024, 1_024)
    assert(
        SubscriptionIcons.classify(statusCode: 200, mimeType: "image/png", data: largest) == .found(largest),
        "A 1024 px icon was refused")
    assert(
        SubscriptionIcons.classify(statusCode: 200, mimeType: "image/png", data: png(1_025, 1)) == .missing,
        "An icon wider than 1024 px was accepted")
    assert(
        SubscriptionIcons.classify(statusCode: 200, mimeType: "image/png", data: png(1, 1_025)) == .missing,
        "An icon taller than 1024 px was accepted")
}
