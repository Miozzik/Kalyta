import XCTest

/// End-to-end checks of recording income next to spending.
final class IncomeUITests: KalytaUITestCase {
    /// Income shows in the list with a plus and in the "earned · left" line, never in spending.
    func testIncomeIsNotSpending() {
        let spentBefore = summaryTotal()
        let earnedBefore = earned()
        app.buttons["Add"].tap()
        // The tab bar has an "Income" button too.
        app.segmentedControls.buttons["Income"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("1000")
        let note = app.textFields["Note"]
        note.tap()
        note.typeText("Премія")
        app.buttons["saveButton"].tap()

        XCTAssertEqual(summaryTotal(), spentBefore, "Income was added to spending")
        let incomeLine = app.staticTexts["summaryIncome"]
        XCTAssertTrue(incomeLine.waitForExistence(timeout: 3), "No earned line after recording income")
        XCTAssertEqual(earned(), earnedBefore + 1000, "The earned line is wrong: \(incomeLine.label)")
        XCTAssertTrue(row("Премія").label.contains("+"), "Income is not marked as money in")

        app.tabBars.buttons["Statistics"].tap()
        app.buttons["Biggest Expenses"].tap()
        XCTAssertTrue(app.navigationBars["Biggest Expenses"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Премія"].exists, "Income is listed among the biggest expenses")
    }

    /// The Income tab lists the 5,000 ₴ sample salary, totals it, and leaves out spending of the same day.
    func testIncomeTabShowsIncomeOnly() {
        app.tabBars.buttons["Income"].tap()
        XCTAssertTrue(app.navigationBars["Income"].waitForExistence(timeout: 3))
        // The salary is a day old: on the 1st it belongs to the previous month's bar.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        if !Calendar.current.isDate(yesterday, equalTo: .now, toGranularity: .month) {
            // Accessibility order is not screen order, so pick the bar by position.
            let bars = app.buttons.matching(identifier: "periodBar").allElementsBoundByIndex
            bars.sorted { $0.frame.minX < $1.frame.minX }.dropLast().last?.tap()
        }

        let total = summaryTotal()
        XCTAssertEqual(Decimal(string: total.filter { "0123456789.".contains($0) }), 5000, "Income total is \(total)")
        XCTAssertTrue(row("Зарплата").label.contains("+"), "The salary is not listed as money in")
        XCTAssertFalse(isListed("Комуналка"), "Spending is listed on the Income tab")
    }

    /// Returns the income of the period from the summary card, or 0 when the card shows none.
    ///
    /// Reads the first amount of "earned UAH 6,000 · left UAH 2,867.60" (the en_US format).
    private func earned() -> Decimal {
        _ = summaryTotal()
        let line = app.staticTexts["summaryIncome"]
        guard line.exists else { return 0 }
        let first = line.label.components(separatedBy: "·").first ?? ""
        return Decimal(string: first.filter { "0123456789.".contains($0) }) ?? -1
    }
}
