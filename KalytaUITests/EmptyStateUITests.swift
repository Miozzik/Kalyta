import XCTest

/// End-to-end checks of the Expenses tab with nothing recorded.
final class EmptyStateUITests: KalytaUITestCase {
    /// The empty state sits below the summary card instead of covering it.
    func testEmptyStateSitsBelowSummaryCard() {
        relaunch(with: ["--empty"])

        let title = app.staticTexts["Nothing recorded yet"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "No empty state on an empty store")
        let total = app.staticTexts["summaryTotal"]
        let today = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'today'")).firstMatch
        XCTAssertTrue(today.exists, "The card has no today line")

        XCTAssertGreaterThan(today.frame.minY, total.frame.maxY, "The today line is not under the total in the card")
        XCTAssertFalse(title.frame.intersects(total.frame), "The empty state covers the total")
        XCTAssertGreaterThan(
            title.frame.minY, today.frame.maxY,
            "The empty state starts at \(title.frame.minY), above the card's last line at \(today.frame.maxY)")
    }
}
