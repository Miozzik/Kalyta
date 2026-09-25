import XCTest

/// End-to-end checks of the ways to open the receipt scanner from outside the app.
final class ScanEntryUITests: KalytaUITestCase {
    /// Running the Scan Receipt shortcut from Spotlight opens the entry sheet with the scanner
    /// already up, over whichever tab was open.
    ///
    /// Spotlight lists the App Shortcut and runs the intent the same way Siri, the Action button
    /// and Back Tap do. The simulator has no scanner, so `-scanPayload` stands in for the camera:
    /// a filled amount proves the scan started by itself.
    func testSpotlightShortcutOpensScanner() {
        relaunch(with: ["--demo", "-scanPayload", receiptPayload(amount: "987.65", at: .now)])
        app.tabBars.buttons["Statistics"].tap()
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.otherElements["spotlight-pill"].firstMatch.tap()
        let spotlight = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
        let field = spotlight.textFields["SpotlightSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "Spotlight did not open")
        field.typeText("Scan a receipt")
        // As the top hit the cell's label also names the symbol: "Scan Qr Code, Scan Receipt".
        let isShortcut = NSPredicate(
            format: "identifier BEGINSWITH 'Identifier:AppViewResultCell' AND label ENDSWITH 'Scan Receipt'")
        let shortcut = spotlight.cells.matching(isShortcut).firstMatch
        XCTAssertTrue(shortcut.waitForExistence(timeout: 30), "Spotlight does not offer the Scan Receipt shortcut")
        shortcut.tap()

        let amount = app.textFields["amountField"]
        // Spotlight brings the app forward at once; the shortcut runner may start the intent much later.
        XCTAssertTrue(amount.waitForExistence(timeout: 90), "The shortcut did not open the entry sheet")
        let filled = expectation(for: NSPredicate(format: "value == %@", "987.65"), evaluatedWith: amount)
        XCTAssertEqual(
            XCTWaiter().wait(for: [filled], timeout: 5), .completed,
            "The sheet opened without scanning: the amount shows \(amount.value ?? "nothing")")
    }
}
