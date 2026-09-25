import XCTest

/// End-to-end checks of scanning a fiscal receipt in the entry sheet.
///
/// The simulator has no scanner, so debug builds take the code's payload from
/// `-scanPayload` and feed it to the same code path as the camera.
final class ReceiptUITests: KalytaUITestCase {
    /// A receipt for an amount already recorded shortly before opens that expense
    /// instead of adding a second one, so the Wallet automation and the scan never double count.
    func testReceiptUpdatesMatchingExpense() {
        let note = "Receipt \(UUID().uuidString.prefix(8))"
        app.buttons["Add"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        type("432.90", into: amount)
        app.buttons["Transport"].tap()
        let noteField = app.textFields["Note"]
        noteField.tap()
        noteField.typeText(note)
        app.buttons["Save"].tap()
        let labelBefore = row(note).label

        relaunch(with: ["-scanPayload", receiptPayload(amount: "432.90", at: .now.addingTimeInterval(-20 * 60))])
        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["Scan Receipt"].waitForExistence(timeout: 3))
        app.buttons["Scan Receipt"].tap()
        let match = app.staticTexts["receiptMatch"]
        XCTAssertTrue(match.waitForExistence(timeout: 3), "The receipt did not match the recorded expense")
        app.buttons["Food"].tap()
        app.buttons["Save"].tap()

        XCTAssertEqual(listedCount(note), 1, "The receipt added a second expense instead of updating the first")
        XCTAssertNotEqual(row(note).label, labelBefore, "The expense did not take the receipt's time")
    }

    /// A receipt for an amount nothing was recorded with fills a new entry and offers no match.
    func testReceiptWithoutMatchFillsNewEntry() {
        relaunch(with: ["--demo", "-scanPayload", receiptPayload(amount: "987.65", at: .now)])
        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["Scan Receipt"].waitForExistence(timeout: 3))
        app.buttons["Scan Receipt"].tap()

        let amount = app.textFields["amountField"]
        let filled = expectation(for: NSPredicate(format: "value == %@", "987.65"), evaluatedWith: amount)
        XCTAssertEqual(
            XCTWaiter().wait(for: [filled], timeout: 3), .completed,
            "The amount field shows \(amount.value ?? "nothing"), not the receipt amount")
        XCTAssertFalse(app.staticTexts["receiptMatch"].exists, "A receipt matched although no expense has its amount")
    }

    /// "Save as New" drops the match and puts back the note and category typed before the scan.
    func testSaveAsNewRestoresFieldsBeforeMatch() {
        let receiptTime = Date.now.addingTimeInterval(-5 * 60)
        startEntryMatchingSeededExpense(payload: receiptPayload(amount: "432.90", at: receiptTime))

        app.buttons["Save as New"].tap()
        verifyFieldsBeforeMatch()
    }

    /// Scanning a receipt that matches nothing after one that matched puts back the fields from before the match.
    func testRescanWithoutMatchRestoresFieldsBeforeMatch() {
        let receiptTime = Date.now.addingTimeInterval(-5 * 60)
        let matching = receiptPayload(amount: "432.90", at: receiptTime)
        let unmatched = receiptPayload(amount: "1.00", at: receiptTime)
        startEntryMatchingSeededExpense(payload: matching + "|" + unmatched)

        app.buttons["Scan Receipt"].tap()
        verifyFieldsBeforeMatch()
    }

    /// Records 432.90 ₴ "АТБ" in Food, then starts a new entry "Кава" in Entertainment
    /// and scans a receipt that matches the recorded one.
    ///
    /// - Parameter payload: The `-scanPayload` value; its first part must match the recorded expense.
    private func startEntryMatchingSeededExpense(payload: String) {
        app.buttons["Add"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        type("432.90", into: amount)
        app.buttons["Food"].tap()
        let seededNote = app.textFields["Note"]
        seededNote.tap()
        type("АТБ", into: seededNote)
        app.buttons["Save"].tap()

        relaunch(with: ["-scanPayload", payload])
        app.buttons["Add"].tap()
        let note = app.textFields["Note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        type("Кава", into: note)
        app.buttons["Entertainment"].tap()
        app.buttons["Scan Receipt"].tap()

        XCTAssertTrue(app.staticTexts["receiptMatch"].waitForExistence(timeout: 3), "The receipt did not match АТБ")
        XCTAssertEqual(note.value as? String, "АТБ", "The match did not bring the recorded note")
        XCTAssertTrue(app.buttons["Food"].isSelected, "The match did not bring the recorded category")
    }

    /// Checks that the entry is back to "Кава" in Entertainment, with no match shown.
    private func verifyFieldsBeforeMatch() {
        XCTAssertTrue(
            app.staticTexts["receiptMatch"].waitForNonExistence(timeout: 3), "The match is still shown")
        XCTAssertEqual(app.textFields["Note"].value as? String, "Кава", "The note typed before the scan was lost")
        XCTAssertTrue(app.buttons["Entertainment"].isSelected, "The category picked before the scan was lost")
        XCTAssertFalse(app.buttons["Food"].isSelected, "The matched category is still selected")
    }

    /// Returns the link a fiscal receipt's QR code holds, with the time printed in Kyiv time.
    ///
    /// - Parameters:
    ///   - amount: The receipt total as printed, such as "432.90".
    ///   - date: When the receipt was issued.
    private func receiptPayload(amount: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Kyiv")
        formatter.dateFormat = "'date='yyyyMMdd'&time='HHmm"
        return "https://cabinet.tax.gov.ua/cashregs/check?\(formatter.string(from: date))&sm=\(amount)&fn=4000123456"
    }
}
