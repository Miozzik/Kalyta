import XCTest

/// Phase B of the Shortcuts upgrade check: a shortcut saved by an older build, with the
/// Category parameter set to Food, must still record into Food after the upgrade.
///
/// Changing the parameter from `AppEnum` to `AppEntity` is not covered by Apple's
/// documentation, so this is checked end to end. It needs state prepared by the old
/// build (phase A in `scripts/check-shortcut-upgrade.sh`), so it is skipped unless
/// `KALYTA_SHORTCUT_UPGRADE=1` reaches the test runner.
final class ShortcutUpgradeUITests: XCTestCase {
    private let languageArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    func testShortcutSavedBeforeUpgradeKeepsCategory() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KALYTA_SHORTCUT_UPGRADE"] == "1",
            "Needs a shortcut created by the previous build; see scripts/check-shortcut-upgrade.sh")

        // Opening the new build once runs the migration, as on a real phone.
        let kalyta = XCUIApplication()
        kalyta.launchArguments = languageArguments
        kalyta.launch()
        XCTAssertTrue(kalyta.staticTexts["summaryTitle"].waitForExistence(timeout: 10))
        kalyta.terminate()

        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcuts.launch()
        let run = shortcuts.buttons["Play, Add Expense"]
        XCTAssertTrue(run.waitForExistence(timeout: 10), "The shortcut from the old build is gone")
        run.tap()
        // The tile opens the shortcut; switch to the classic editor to see the saved parameter.
        if shortcuts.buttons["Editor"].waitForExistence(timeout: 5) { shortcuts.buttons["Editor"].tap() }
        let savedCategory = shortcuts.buttons.matching(
            NSPredicate(format: "label IN %@", ["Food", "Category", "Other"])
        ).firstMatch
        XCTAssertTrue(savedCategory.waitForExistence(timeout: 5), "The Add Expense action is gone from the shortcut")
        print("PROBE saved category after upgrade: \(savedCategory.label)")
        XCTAssertEqual(savedCategory.label, "Food", "The shortcut lost its saved category in the upgrade")

        let play = shortcuts.buttons["play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()

        let amount = shortcuts.textFields.firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 10), "The shortcut did not ask for the amount")
        amount.typeText("11")
        shortcuts.buttons["Done"].firstMatch.tap()
        sleep(3)

        kalyta.launch()
        let recorded = kalyta.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UAH 11")).firstMatch
        XCTAssertTrue(recorded.waitForExistence(timeout: 10), "The shortcut did not record the expense")
        XCTAssertTrue(recorded.label.hasPrefix("Food,"), "The saved category was lost: \(recorded.label)")
    }
}
