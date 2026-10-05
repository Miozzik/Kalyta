import XCTest

/// Settings → Automation: one row in Settings, six rows inside in a fixed order.
final class AutomationUITests: KalytaUITestCase {
    /// The rows, top to bottom, by accessibility identifier.
    private let rows = ["monobank", "applePay", "backTap", "actionButton", "widgets", "receipt"]

    func testAutomationListsSixRowsInOrder() {
        app.tabBars.buttons["Settings"].tap()
        let automation = app.buttons["Automation"]
        XCTAssertTrue(automation.waitForExistence(timeout: 5))
        // The count is read asynchronously, so the subtitle may come a moment after the row.
        wait(
            for: [expectation(for: NSPredicate(format: "label CONTAINS 'of 5 set up'"), evaluatedWith: automation)],
            timeout: 5)
        XCTAssertFalse(app.staticTexts["Bank"].exists, "The Bank section is still in Settings")

        automation.tap()
        let buttons = rows.map { app.buttons["automation.\($0)"] }
        XCTAssertTrue(buttons[0].waitForExistence(timeout: 5))
        for (row, button) in zip(rows, buttons) { XCTAssertTrue(button.exists, "No \(row) row") }
        for (upper, lower) in zip(buttons, buttons.dropFirst()) {
            XCTAssertLessThan(upper.frame.minY, lower.frame.minY, "\(lower.identifier) is above \(upper.identifier)")
        }
        // App Shortcuts exist from install, so Siri and the Action button are always ready.
        XCTAssertTrue(buttons[3].label.contains("Ready ✓"), buttons[3].label)
    }
}
