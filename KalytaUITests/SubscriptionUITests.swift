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

    /// Adds a subscription through the editor, accepting the notification prompt if it appears.
    private func addSubscription(name: String, amount: String, yearly: Bool = false) {
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
        app.buttons["Save"].tap()

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
