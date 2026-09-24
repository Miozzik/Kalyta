import XCTest

/// End-to-end checks that no editor saves an amount above the shared maximum of 10,000,000 ₴.
///
/// Each amount is typed into a freshly opened, empty editor.
final class AmountLimitUITests: KalytaUITestCase {
    /// The expense editor accepts exactly the maximum and refuses one hryvnia more.
    func testExpenseEditorRefusesAmountAboveMaximum() {
        verifyLimit {
            self.app.buttons["Add"].tap()
            let amount = self.app.textFields["amountField"]
            XCTAssertTrue(amount.waitForExistence(timeout: 3))
            return amount
        }
    }

    /// The subscription editor accepts exactly the maximum and refuses one hryvnia more.
    func testSubscriptionEditorRefusesAmountAboveMaximum() {
        app.tabBars.buttons["Subscriptions"].tap()
        verifyLimit {
            self.app.buttons["Add Subscription"].tap()
            let name = self.app.textFields["subscriptionName"]
            XCTAssertTrue(name.waitForExistence(timeout: 3))
            name.tap()
            name.typeText("Limit")
            let amount = self.app.textFields["subscriptionAmount"]
            amount.tap()
            return amount
        }
    }

    /// Checks that Save is enabled at the maximum and disabled one hryvnia above it.
    ///
    /// Save being enabled at the maximum proves the button reacts to the amount, so a Save
    /// disabled for another reason cannot pass the check.
    ///
    /// - Parameter openEditor: Opens a new editor and returns its focused, empty amount field.
    private func verifyLimit(openEditor: () -> XCUIElement) {
        let save = app.buttons["Save"]
        type("10000000", into: openEditor())
        XCTAssertTrue(save.isEnabled, "Save is disabled for the maximum amount")
        app.buttons["Cancel"].tap()

        let amount = openEditor()
        type("10000001", into: amount)
        XCTAssertEqual(digits(amount.value as? String ?? ""), "10000001", "The field holds another amount")
        XCTAssertFalse(save.isEnabled, "Save is enabled for an amount above the maximum")
    }
}
