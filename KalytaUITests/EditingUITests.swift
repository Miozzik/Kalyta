import XCTest

/// End-to-end checks of the expense editor: editing, cancelling, saving, and deleting.
final class EditingUITests: KalytaUITestCase {
    /// A sample expense of 120 ₴ in "Entertainment", recorded today.
    private let sampleNote = "Кава з Оксаною"

    /// Moving an expense into the previous month updates both months, keeps its
    /// amount and note, and does not duplicate it.
    func testEditingMovesExpenseAcrossMonth() {
        verifyMoveToPreviousMonth()
    }

    /// The same move when the previous month already has expenses, as on the first
    /// days of a month, when sample data from the last week falls into it.
    func testEditingMovesExpenseIntoNonEmptyPreviousMonth() {
        // Shift the samples so the newest lands on the 1st of this month: the rest of the
        // week falls into the previous month, whatever today's date is.
        let offset = Calendar.current.component(.day, from: .now) - 1
        relaunch(with: ["--demo", "-demoOffsetDays", String(offset)])
        verifyMoveToPreviousMonth()
    }

    /// Moves the 120 ₴ sample to the last day of the previous month and checks the result.
    ///
    /// The target day and period are computed from the calendar, so the test passes
    /// on any date, not only in the month it was written.
    private func verifyMoveToPreviousMonth() {
        let lastDay = lastDayOfPreviousMonth()
        let currentBefore = amount(in: summaryTotal())
        let previousBefore = amount(in: previousPeriodBar().label)

        row(sampleNote).tap()
        XCTAssertTrue(app.navigationBars["Edit Expense"].waitForExistence(timeout: 3))
        pickDayInPreviousMonth(lastDay.formatted(Date.FormatStyle(locale: testLocale).month(.wide).day()))
        // Picked after the date, so no tap that closes the calendar can land on the grid and change it.
        app.buttons["Food"].tap()
        XCTAssertTrue(app.buttons["Food"].isSelected, "Food is not selected before Save")
        app.buttons["Save"].tap()

        XCTAssertEqual(
            amount(in: summaryTotal()), currentBefore - 120, "The current month still counts the moved expense")
        XCTAssertFalse(isListed(sampleNote), "The moved expense is still in the current month")

        selectPreviousPeriod()
        XCTAssertEqual(
            amount(in: summaryTotal()), previousBefore + 120, "The previous month does not count the moved expense")
        XCTAssertTrue(app.staticTexts["Food"].exists, "The chart does not show the new category")
        XCTAssertEqual(listedCount(sampleNote), 1, "The moved expense is missing or duplicated")
        XCTAssertEqual(amount(in: row(sampleNote).label), 120, "The amount changed: \(row(sampleNote).label)")

        relaunchWithoutDemoData()
        selectPreviousPeriod()
        XCTAssertEqual(listedCount(sampleNote), 1, "The edit was not saved")
    }

    /// Cancel discards changes, even though the main context autosaves.
    ///
    /// Checked twice: in memory right after Cancel, and in the store after the app
    /// went to the background (which forces a save) and was relaunched.
    func testCancelDiscardsEdits() {
        row(sampleNote).tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "999")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(digits(row(sampleNote).label).hasSuffix("120"), "Cancel kept the edit: \(row(sampleNote).label)")

        XCUIDevice.shared.press(.home)
        relaunchWithoutDemoData()
        XCTAssertTrue(
            digits(row(sampleNote).label).hasSuffix("120"),
            "Cancel kept the edit in the store: \(row(sampleNote).label)")
    }

    /// A new expense is saved at once, so killing the app right after Save keeps it.
    func testNewExpenseSurvivesImmediateKill() {
        app.buttons["Add"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.typeText("77")
        let note = app.textFields["Note"]
        note.tap()
        note.typeText("Probe")
        app.buttons["Save"].tap()
        app.terminate()

        relaunchWithoutDemoData()
        XCTAssertTrue(isListed("Probe"), "A new expense was lost when the app was killed right after Save")
    }

    /// Deleting from the editor shows the same undo banner as a swipe.
    func testDeleteFromEditorOffersUndo() {
        row(sampleNote).tap()
        app.buttons["Delete Expense"].tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 3), "No undo banner after deleting in the editor")
        XCTAssertTrue(
            app.staticTexts[sampleNote].waitForNonExistence(timeout: 2), "The deleted expense is still listed")

        app.buttons["Undo"].tap()
        XCTAssertTrue(isListed(sampleNote), "Undo did not bring the expense back")
    }

    /// Opens the date picker in the editor and picks a day of the previous month.
    ///
    /// - Parameter day: The month and day as VoiceOver reads them, such as "August 31".
    private func pickDayInPreviousMonth(_ day: String) {
        app.datePickers.firstMatch.buttons.element(boundBy: 1).tap()
        let previousMonth = app.buttons["Previous Month"]
        XCTAssertTrue(previousMonth.waitForExistence(timeout: 3))
        previousMonth.tap()
        let dayButton = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", day)).firstMatch
        XCTAssertTrue(dayButton.waitForExistence(timeout: 3), "No button for \(day)")
        dayButton.tap()
        // The title does nothing when tapped; a tap on "PopoverDismissRegion" could reach a category below.
        app.navigationBars["Edit Expense"].staticTexts["Edit Expense"].tap()
        XCTAssertTrue(previousMonth.waitForNonExistence(timeout: 3), "The calendar did not close")
    }

    /// The locale the tests run the app in, so formatted dates and amounts are predictable.
    private let testLocale = Locale(identifier: "en_US")

    /// Returns the last day of the month before the current one.
    private func lastDayOfPreviousMonth() -> Date {
        let calendar = Calendar.current
        let startOfMonth = calendar.dateInterval(of: .month, for: .now)!.start
        return calendar.date(byAdding: .day, value: -1, to: startOfMonth)!
    }

    /// Returns the bar of the period before the current one: the second bar from the right.
    ///
    /// Accessibility order is not screen order, so the bars are sorted by position.
    private func previousPeriodBar() -> XCUIElement {
        _ = summaryTotal()
        let bars = app.buttons.matching(identifier: "periodBar").allElementsBoundByIndex
            .sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertGreaterThanOrEqual(bars.count, 2)
        return bars[bars.count - 2]
    }

    /// Taps the previous-period bar and waits until the summary shows that period.
    ///
    /// The selection changes inside an animation, so reading the total right after
    /// the tap can still return the current period.
    private func selectPreviousPeriod() {
        previousPeriodBar().tap()
        let showsPastPeriod = NSPredicate(format: "label BEGINSWITH %@", "Spent in")
        let selected = expectation(for: showsPastPeriod, evaluatedWith: app.staticTexts["summaryTitle"])
        XCTAssertEqual(
            XCTWaiter().wait(for: [selected], timeout: 3), .completed, "The previous period was not selected")
    }

    /// Returns the amount in a label formatted for `en_US`, such as 1234.5 for "Aug, UAH 1,234.50".
    private func amount(in label: String) -> Decimal {
        let number = label.split(separator: "UAH").last.map(String.init) ?? ""
        return Decimal(string: number.filter { "0123456789.".contains($0) }) ?? 0
    }
}
