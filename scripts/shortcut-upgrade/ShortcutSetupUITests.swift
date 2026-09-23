import XCTest

/// Phase A of the Shortcuts upgrade check, run with the OLD build: creates a shortcut
/// "Add Expense" with Category = Food in the Shortcuts app.
final class ShortcutSetupUITests: XCTestCase {
    func testCreateFoodShortcut() {
        let kalyta = XCUIApplication()
        kalyta.launchArguments = ["--demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        kalyta.launch()
        sleep(2)
        let s = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        s.launch()
        if s.buttons["Continue"].waitForExistence(timeout: 5) { s.buttons["Continue"].tap() }
        s.buttons["main.button.newshortcut"].tap()
        if s.buttons["Editor"].waitForExistence(timeout: 5) { s.buttons["Editor"].tap() }
        let search = s.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        if !search.isHittable { search.swipeUp() }
        search.tap(); search.typeText("Add Expense")
        // Right after installation Shortcuts may not have indexed the app's actions yet.
        XCTAssertTrue(s.cells["Add Expense"].firstMatch.waitForExistence(timeout: 30)); s.cells["Add Expense"].firstMatch.tap()
        XCTAssertTrue(s.buttons["Category"].waitForExistence(timeout: 5)); s.buttons["Category"].tap()
        XCTAssertTrue(s.buttons["Food"].waitForExistence(timeout: 5)); s.buttons["Food"].tap()
        sleep(1)
        print("PROBE action after pick: \(s.buttons.matching(NSPredicate(format: "label == 'Food' OR label == 'Category'")).allElementsBoundByIndex.map { $0.label })")
        s.buttons["BackButton"].tap()
        sleep(2)
        for line in s.debugDescription.split(separator: "\n") where line.contains("Add Expense") { print("PROBE library \(line.trimmingCharacters(in: .whitespaces).prefix(160))") }
    }
}
