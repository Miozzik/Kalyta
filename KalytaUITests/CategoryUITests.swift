import XCTest

/// End-to-end checks of creating, editing, hiding and deleting categories.
final class CategoryUITests: KalytaUITestCase {
    /// A category created from the expense sheet is selected there and used on Save.
    func testNewCategoryFromEditorIsSelected() {
        app.buttons["Add"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.typeText("50")
        app.buttons["New Category"].tap()
        createCategory(named: "Кафе")

        XCTAssertTrue(app.buttons["Кафе"].isSelected, "The new category was not selected in the sheet")
        app.buttons["saveButton"].tap()
        XCTAssertTrue(isListed("Кафе"), "The expense was not saved in the new category")
    }

    /// "Other" catches Back Tap entries without a category, so it can never be hidden.
    func testOtherCannotBeHidden() {
        openCategory("Other")
        scrollFormToBottom()
        XCTAssertFalse(app.switches["Hide"].exists, "Other offers a Hide switch")
        XCTAssertFalse(app.buttons["Delete Category"].exists, "Other offers Delete")
    }

    /// A category with expenses can only be hidden: it leaves the sheet but keeps its history.
    func testUsedCategoryCanOnlyBeHidden() {
        openCategory("Food")
        scrollFormToBottom()
        XCTAssertFalse(app.buttons["Delete Category"].exists, "A used category offers Delete")
        // Tapping the centre of a Form toggle row hits its label; tap the switch at the trailing edge.
        let hide = app.switches["Hide"]
        hide.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(hide.value as? String, "1", "The Hide switch did not turn on")
        app.buttons["saveButton"].tap()

        app.tabBars.buttons["Expenses"].tap()
        XCTAssertTrue(row("АТБ").label.contains("АТБ"), "An expense in the hidden category disappeared")
        app.buttons["Add"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Food"].exists, "A hidden category is still offered for new expenses")
    }

    /// Renaming a built-in shows the new name in the chart legend.
    func testRenamedBuiltInShowsNewName() {
        openCategory("Food")
        let name = app.textFields["categoryName"]
        name.tap()
        name.typeText("Продукти")
        app.buttons["saveButton"].tap()

        app.tabBars.buttons["Expenses"].tap()
        XCTAssertTrue(app.staticTexts["Продукти"].waitForExistence(timeout: 3), "The chart still shows the old name")
    }

    /// An unused custom category can be deleted for good.
    func testUnusedCustomCategoryCanBeDeleted() {
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Categories"].tap()
        app.buttons["New Category"].tap()
        createCategory(named: "Тимчасова")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Тимчасова")).firstMatch.tap()
        tapBelowForm("Delete Category")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Тимчасова")).firstMatch
                .waitForNonExistence(timeout: 3), "The deleted category is still listed")
    }

    /// Scrolls the category form to its end, where Hide and Delete live.
    ///
    /// A `Form` creates only rows near the visible area, like a `List`.
    private func scrollFormToBottom() {
        for _ in 0..<maxScrolls { app.swipeUp() }
    }

    /// Scrolls the category form down and taps the button with this label.
    ///
    /// - Parameter label: The button's label.
    private func tapBelowForm(_ label: String) {
        let button = app.buttons[label]
        for _ in 0..<maxScrolls where !(button.exists && button.isHittable) { app.swipeUp() }
        XCTAssertTrue(button.isHittable, "No \(label) button")
        button.tap()
    }

    /// Fills in the new-category sheet with a name and saves it.
    ///
    /// - Parameter name: The category name to type.
    private func createCategory(named name: String) {
        let field = app.textFields["categoryName"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(name)
        // Scope to this sheet's bar: the expense sheet underneath has its own Save.
        app.navigationBars["New Category"].buttons["saveButton"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3), "The category sheet did not close")
    }

    /// Opens a category from Settings → Categories.
    ///
    /// - Parameter title: The category's name as listed.
    private func openCategory(_ title: String) {
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Categories"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "No category \(title)")
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit Category"].waitForExistence(timeout: 3))
    }
}
