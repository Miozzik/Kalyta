import XCTest

/// End-to-end checks of the Subscriptions tab.
final class SubscriptionUITests: KalytaUITestCase {
    /// A subscription shows in the list with its monthly cost and, for a known service,
    /// the icon downloaded from the icon repository.
    ///
    /// Needs network access to cdn.jsdelivr.net: offline this test fails by design, which is
    /// not a defect in the app (the lookup is retried when the app becomes active again).
    func testAddedSubscriptionShowsCostAndIcon() {
        addSubscription(name: "Netflix", amount: "199")
        XCTAssertEqual(digits(app.staticTexts["subscriptionsMonthlyCost"].label), "199")
        let withIcon = app.buttons.matching(identifier: "subscriptionRowWithIcon").firstMatch
        XCTAssertTrue(withIcon.waitForExistence(timeout: 20), "The Netflix icon was not downloaded")
    }

    /// A yearly plan counts as a twelfth per month; a Cyrillic name gets a letter avatar, no request.
    func testYearlyPlanCountsAsTwelfth() {
        addSubscription(name: "Спортзал", amount: "2400", yearly: true)
        XCTAssertEqual(digits(app.staticTexts["subscriptionsMonthlyCost"].label), "200")
        XCTAssertTrue(app.buttons.matching(identifier: "subscriptionRow").firstMatch.exists, "No letter avatar")
    }

    /// Recording a charge adds it to Expenses with the subscription's name.
    func testRecordingChargeAddsExpense() {
        addSubscription(name: "Spotify", amount: "149")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Spotify")).firstMatch.swipeRight()
        app.buttons["Record"].tap()
        XCTAssertTrue(app.alerts["Recorded"].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()

        app.tabBars.buttons["Expenses"].tap()
        XCTAssertTrue(isListed("Spotify"), "The recorded charge is not in Expenses")
    }

    /// Recording the same charge twice adds it once and says it is already there.
    func testRecordingTwiceAddsOnce() {
        addSubscription(name: "Spotify", amount: "149")
        for _ in 0..<2 {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Spotify")).firstMatch.swipeRight()
            app.buttons["Record"].tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
            app.alerts.buttons["OK"].tap()
        }
        app.tabBars.buttons["Expenses"].tap()
        XCTAssertEqual(listedCount("Spotify"), 1, "Recording twice counted the charge twice")
    }

    /// "Record Charge" in the editor records the latest charge as an expense, once.
    func testRecordChargeInEditorAddsExpense() {
        addSubscription(name: "Megogo", amount: "99")
        openSubscription("Megogo")
        app.buttons["Record Charge"].tap()
        XCTAssertTrue(app.alerts["Recorded"].waitForExistence(timeout: 3), "Record Charge showed no Recorded alert")
        app.alerts.buttons["OK"].tap()

        app.tabBars.buttons["Expenses"].tap()
        XCTAssertEqual(listedCount("Megogo"), 1, "Record Charge did not add exactly one expense")
    }

    /// Before the first charge there is nothing to record, so the editor offers no "Record Charge".
    func testRecordChargeHiddenBeforeFirstCharge() {
        addSubscription(name: "Megogo", amount: "99", startsNextMonth: true)
        openSubscription("Megogo")
        XCTAssertTrue(app.buttons["Delete Subscription"].exists, "The editor did not open on the subscription")
        XCTAssertFalse(app.buttons["Record Charge"].exists, "Record Charge is offered before the first charge")
    }

    /// Opens the editor of a listed subscription.
    private func openSubscription(_ name: String) {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit Subscription"].waitForExistence(timeout: 3))
    }

    /// Sets the editor's first charge to the 15th of next month.
    ///
    /// The 15th is picked because "October 15" is contained in no other day's label, unlike "October 1".
    private func pickFirstChargeInNextMonth() {
        let calendar = Calendar.current
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: .now)!
        var parts = calendar.dateComponents([.year, .month], from: nextMonth)
        parts.day = 15
        let day = calendar.date(from: parts)!.formatted(
            Date.FormatStyle(locale: Locale(identifier: "en_US")).month(.wide).day())
        app.datePickers.firstMatch.buttons.firstMatch.tap()
        let next = app.buttons["Next Month"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()
        let dayButton = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", day)).firstMatch
        XCTAssertTrue(dayButton.waitForExistence(timeout: 3), "No button for \(day)")
        dayButton.tap()
        // The title does nothing when tapped, so closing the calendar cannot change another field.
        app.navigationBars["New Subscription"].staticTexts["New Subscription"].tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 3), "The calendar did not close")
    }

    /// Adds a subscription through the editor, accepting the notification prompt if it appears.
    private func addSubscription(name: String, amount: String, yearly: Bool = false, startsNextMonth: Bool = false) {
        app.tabBars.buttons["Subscriptions"].tap()
        app.buttons["Add Subscription"].tap()
        let nameField = app.textFields["subscriptionName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(name)
        let amountField = app.textFields["subscriptionAmount"]
        amountField.tap()
        amountField.typeText(amount)
        if yearly { app.buttons["Yearly"].tap() }
        if startsNextMonth { pickFirstChargeInNextMonth() }
        app.buttons["saveButton"].tap()

        // The first subscription asks for notifications; the prompt belongs to SpringBoard.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.waitForExistence(
                timeout: 5),
            "\(name) is not listed")
    }
}
