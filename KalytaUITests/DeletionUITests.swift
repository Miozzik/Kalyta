import XCTest

/// End-to-end checks of deleting an expense, undoing it, and picking a period.
///
/// Each test starts from the sample data of `--demo` and runs in English, so labels
/// such as "Delete" and "Undo" are predictable. A relaunch drops `--demo`, so it
/// shows what was actually saved to the store.
final class DeletionUITests: XCTestCase {
    /// A sample expense from `--demo` recorded today, so it is in the current period.
    private let sampleNote = "Метро"
    /// Another sample expense recorded today.
    private let otherSampleNote = "АТБ"
    private let languageArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    /// Enough swipes to cross the whole list of sample data in either direction.
    private let maxScrolls = 8
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo"] + languageArguments
        app.launch()
    }

    /// Undo brings the expense back, restores the totals, and survives a relaunch.
    func testUndoRestoresExpenseAndTotals() {
        let totalBefore = summaryTotal()
        deleteSampleExpense()

        XCTAssertTrue(
            app.staticTexts[sampleNote].waitForNonExistence(timeout: 2), "The deleted expense is still listed")
        app.buttons["Undo"].tap()
        XCTAssertTrue(isListed(sampleNote), "Undo did not bring the expense back")
        XCTAssertEqual(summaryTotal(), totalBefore, "Undo did not restore the total")

        relaunchWithoutDemoData()
        XCTAssertTrue(isListed(sampleNote), "The undone deletion reached the store")
    }

    /// The total drops the moment an expense is deleted, before the deletion is saved.
    func testDeletionUpdatesTotalImmediately() {
        let totalBefore = summaryTotal()
        deleteSampleExpense()
        XCTAssertNotEqual(summaryTotal(), totalBefore, "The total still includes the deleted expense")
    }

    /// Once the undo banner expires, the deletion is saved.
    func testExpiredDeletionIsCommitted() {
        deleteSampleExpense()
        XCTAssertTrue(app.buttons["Undo"].waitForNonExistence(timeout: 10), "The undo banner never expired")

        relaunchWithoutDemoData()
        XCTAssertFalse(isListed(sampleNote), "The expired deletion was not saved")
    }

    /// If the app is killed while the deletion can still be undone, the expense survives.
    func testKilledDuringUndoWindowKeepsExpense() {
        deleteSampleExpense()
        app.terminate()

        relaunchWithoutDemoData()
        XCTAssertTrue(isListed(sampleNote), "A deletion was saved before the undo window closed")
    }

    /// A second deletion commits the first; Undo then restores only the second.
    func testSecondDeletionCommitsFirst() {
        deleteExpense(sampleNote)
        deleteExpense(otherSampleNote)
        app.buttons["Undo"].tap()

        XCTAssertTrue(isListed(otherSampleNote), "Undo did not restore the second expense")
        XCTAssertFalse(isListed(sampleNote), "The first deletion was not committed")

        relaunchWithoutDemoData()
        XCTAssertTrue(isListed(otherSampleNote), "The undone second deletion reached the store")
        XCTAssertFalse(isListed(sampleNote), "The committed first deletion was not saved")
    }

    /// Leaving the app commits a pending deletion, even though the undo window was still open.
    func testGoingToBackgroundCommitsDeletion() {
        deleteSampleExpense()
        XCUIDevice.shared.press(.home)
        app.terminate()

        relaunchWithoutDemoData()
        XCTAssertFalse(isListed(sampleNote), "A deletion pending when the app left the foreground was not saved")
    }

    /// Tapping one bar selects that period, not every bar in the row.
    func testTappingBarSelectsThatPeriod() {
        let bars = app.buttons.matching(identifier: "periodBar")
        XCTAssertEqual(bars.count, 6)

        // Accessibility order is not screen order, so pick the oldest bar by position.
        let oldestBar = bars.allElementsBoundByIndex.min { $0.frame.minX < $1.frame.minX }
        oldestBar?.tap()
        let title = app.staticTexts["summaryTitle"]
        let selectsPastPeriod = NSPredicate(format: "label BEGINSWITH %@", "Spent in")
        let selected = expectation(for: selectsPastPeriod, evaluatedWith: title)
        XCTAssertEqual(
            XCTWaiter().wait(for: [selected], timeout: 3), .completed,
            "Tapping the oldest bar did not select it: \(title.label)")
    }

    /// Deletes the main sample expense.
    private func deleteSampleExpense() {
        deleteExpense(sampleNote)
    }

    /// Scrolls to the expense with this note, swipes it to the left, and taps Delete.
    ///
    /// - Parameter note: The note of the expense to delete.
    private func deleteExpense(_ note: String) {
        scrollDown(until: app.staticTexts[note])
        // Swipe the whole row: a swipe across the short note alone is too short to open the actions.
        app.cells.containing(.staticText, identifier: note).firstMatch.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2), "No undo banner after deleting")
    }

    /// Returns the text of the period total, scrolling back up to the summary card.
    private func summaryTotal() -> String {
        let total = app.staticTexts["summaryTotal"]
        for _ in 0..<maxScrolls where !(total.exists && total.isHittable) { app.swipeDown() }
        return total.label
    }

    /// Scrolls the list down until `element` is on screen.
    ///
    /// A `List` creates only the rows near the visible area, so an expense below the
    /// chart does not exist in the accessibility tree until it is scrolled to.
    private func scrollDown(until element: XCUIElement) {
        _ = app.staticTexts["summaryTitle"].waitForExistence(timeout: 5)
        for _ in 0..<maxScrolls where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "\(element) never came on screen")
    }

    /// Returns whether an expense with this note is listed, scrolling down to look for it.
    private func isListed(_ note: String) -> Bool {
        let row = app.staticTexts[note]
        _ = app.staticTexts["summaryTitle"].waitForExistence(timeout: 5)
        for _ in 0..<maxScrolls where !row.exists { app.swipeUp() }
        return row.exists
    }

    /// Restarts the app on the stored data, without reseeding it.
    private func relaunchWithoutDemoData() {
        app.terminate()
        app.launchArguments = languageArguments
        app.launch()
    }
}
