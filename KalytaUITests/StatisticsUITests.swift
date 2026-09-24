import XCTest

/// End-to-end checks of the Statistics tab.
final class StatisticsUITests: KalytaUITestCase {
    /// Every submenu opens from the Statistics list.
    func testEverySubmenuOpens() {
        app.tabBars.buttons["Statistics"].tap()
        for title in ["Months", "Categories by Month", "Places", "Biggest Expenses"] {
            app.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3), "\(title) did not open")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    /// An expense deleted on the Expenses tab is gone from Statistics, even inside the undo window.
    ///
    /// Statistics reads the store directly; this holds only because leaving the Expenses tab
    /// commits a pending deletion.
    func testPendingDeletionIsNotInStatistics() {
        row("Комуналка").swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2))

        app.tabBars.buttons["Statistics"].tap()
        app.buttons["Biggest Expenses"].tap()
        XCTAssertTrue(app.navigationBars["Biggest Expenses"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Сільпо"].waitForExistence(timeout: 3), "The list did not load")
        XCTAssertFalse(app.staticTexts["Комуналка"].exists, "A deleted expense is still in Statistics")
        XCTAssertFalse(app.staticTexts["Зарплата"].exists, "Income is listed among the biggest expenses")
    }
}
