import XCTest

/// Captures the README screenshots into `docs/images/screens/<language>/` at full size.
///
/// Skipped unless `KALYTA_SCREENSHOTS=1` reaches the test runner; run it through
/// `scripts/readme-screenshots.sh`, which also sets the language, cleans the status bar and shrinks the images.
/// The language is the simulator's, since the Home Screen widget follows it rather than the app's
/// launch arguments; a debug build answers rates from `-rateFixture friday` and scans from `-scanPayload`.
final class ScreenshotUITests: KalytaUITestCase {
    let isUkrainian = Locale.preferredLanguages.first?.hasPrefix("uk") == true

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testCaptureReadmeScreens() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KALYTA_SCREENSHOTS"] == "1", "Set KALYTA_SCREENSHOTS=1")
        // The receipt is for the sample "АТБ" recorded at launch, so the scan matches it.
        app.launchArguments = [
            "--demo", "-rateFixture", "friday", "-scanPayload", receiptPayload(amount: "248.90", at: .now),
            "-AppleLanguages", isUkrainian ? "(uk)" : "(en)", "-AppleLocale", isUkrainian ? "uk_UA" : "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["summaryTitle"].waitForExistence(timeout: 5))
        capture("01-expenses")

        app.buttons[localized("Add", "Додати")].tap()
        app.segmentedControls.buttons.element(boundBy: 1).tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        type("100", into: amount)
        app.buttons["currencyMenu"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'USD'")).firstMatch.tap()
        let note = app.textFields[localized("Note", "Нотатка")]
        note.tap()
        // Return puts the keyboard away.
        note.typeText(localized("Freelance", "Фріланс") + "\n")
        sleep(1)
        capture("03-currency")
        app.buttons["saveButton"].tap()

        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["summaryTitle"].waitForExistence(timeout: 5))
        capture("02-income")

        // The first report, Months, has a chart; the tab itself is only a list of reports.
        app.tabBars.buttons.element(boundBy: 2).tap()
        app.cells.element(boundBy: 1).tap()
        sleep(1)
        capture("04-statistics")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons.element(boundBy: 0).tap()
        app.buttons[localized("Add", "Додати")].tap()
        app.buttons[localized("Scan Receipt", "Сканувати чек")].tap()
        XCTAssertTrue(app.staticTexts["receiptMatch"].waitForExistence(timeout: 5), "The receipt did not match АТБ")
        capture("05-receipt")
        app.buttons["cancelButton"].tap()

        XCUIDevice.shared.press(.home)
        _ = homeScreenWidget()
        // The widget's timeline reloads after the app goes to the background.
        sleep(2)
        capture("06-widget")
    }

    /// Returns the English or the Ukrainian text, whichever the simulator speaks.
    private func localized(_ english: String, _ ukrainian: String) -> String {
        isUkrainian ? ukrainian : english
    }

    /// Writes a screenshot of the screen to `docs/images/screens/<language>/<name>.png` in the repository.
    private func capture(_ name: String) {
        let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/images/screens/\(isUkrainian ? "uk" : "en")")
        XCTAssertNoThrow(try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true))
        XCTAssertNoThrow(
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appending(path: "\(name).png")))
    }
}
