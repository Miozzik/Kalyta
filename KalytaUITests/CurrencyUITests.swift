import XCTest

/// End-to-end checks of an entry in a foreign currency, with rates from ``RateFixture`` (`friday`: USD 44.9729).
final class CurrencyUITests: KalytaUITestCase {
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo", "-rateFixture", "friday"] + languageArguments
        app.launch()
    }

    /// 100 USD shows its hryvnias in the editor, saves, and the row shows the dollars with "≈ 4,497 ₴" under them.
    func testDollarEntryShowsHryvnias() {
        app.buttons["Add"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        type("100", into: amount)

        let menu = app.buttons["currencyMenu"]
        XCTAssertTrue(menu.exists, "No currency menu next to the amount")
        menu.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "USD")).firstMatch.tap()

        let preview = app.staticTexts["hryvniaPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "The hryvnia block did not appear")
        let converted = NSPredicate(format: "label CONTAINS %@", "4,497.29")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: converted, object: preview)], timeout: 10),
            .completed, "The editor shows \(preview.label) for 100 USD")
        XCTAssertTrue(app.buttons["rateLine"].label.contains("44.97"), "The NBU rate is not shown")

        let note = app.textFields["Note"]
        note.tap()
        note.typeText("Кава в Кракові")
        app.buttons["saveButton"].tap()

        let label = row("Кава в Кракові").label
        XCTAssertTrue(label.contains("$100"), "The row does not lead with the dollars: \(label)")
        let hryvnias = label.components(separatedBy: "≈").last ?? ""
        XCTAssertEqual(digits(hryvnias), "4497", "The row's hryvnias are wrong: \(label)")
    }
}
