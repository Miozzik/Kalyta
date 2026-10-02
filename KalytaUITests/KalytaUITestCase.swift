import XCTest

/// Shared setup and helpers for Kalyta's UI tests.
///
/// Each test starts from the sample data of `--demo` and runs in English, so labels
/// such as "Delete" and "Undo" are predictable. A relaunch drops `--demo`, so it
/// shows what was actually saved to the store.
class KalytaUITestCase: XCTestCase {
    let languageArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    /// Enough swipes to cross the whole list of sample data in either direction.
    let maxScrolls = 8
    var app: XCUIApplication!
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo"] + languageArguments
        app.launch()
    }

    /// Returns the list row of the expense with this note, scrolling down to it.
    ///
    /// - Parameter note: The note of a sample expense.
    /// - Returns: The row's button; its label holds the note, time, and amount.
    func row(_ note: String) -> XCUIElement {
        scrollDown(until: app.staticTexts[note])
        // The cell itself has no label; the row's button carries "note, time, amount".
        return app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", note + ",")).firstMatch
    }

    /// Returns only the digits of a formatted amount, such as "120" for "UAH 120".
    ///
    /// Currency formatters insert a non-breaking space, so a formatted amount never
    /// equals a string literal typed with a regular space.
    func digits(_ text: String) -> String {
        text.filter(\.isNumber)
    }

    /// Returns the text of the period total, scrolling back up to the summary card.
    func summaryTotal() -> String {
        let total = app.staticTexts["summaryTotal"]
        for _ in 0..<maxScrolls where !(total.exists && total.isHittable) { app.swipeDown() }
        return total.label
    }

    /// Scrolls the list down until `element` is on screen.
    ///
    /// A `List` creates only the rows near the visible area, so an expense below the
    /// chart does not exist in the accessibility tree until it is scrolled to.
    func scrollDown(until element: XCUIElement) {
        _ = app.staticTexts["summaryTitle"].waitForExistence(timeout: 5)
        for _ in 0..<maxScrolls where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "\(element) never came on screen")
    }

    /// Returns how many expenses with this note are listed, scrolling down through the list.
    func listedCount(_ note: String) -> Int {
        _ = app.staticTexts["summaryTitle"].waitForExistence(timeout: 5)
        for _ in 0..<maxScrolls where !app.staticTexts[note].exists { app.swipeUp() }
        return app.staticTexts.matching(identifier: note).count
    }

    /// Returns whether an expense with this note is listed, scrolling down to look for it.
    func isListed(_ note: String) -> Bool {
        listedCount(note) > 0
    }

    /// Restarts the app on the stored data, without reseeding it.
    func relaunchWithoutDemoData() {
        relaunch(with: [])
    }

    /// Restarts the app with extra launch arguments, always in English.
    ///
    /// - Parameter arguments: Arguments added to the language ones, such as `--demo`.
    func relaunch(with arguments: [String]) {
        app.terminate()
        app.launchArguments = arguments + languageArguments
        app.launch()
    }

    /// Types text into a focused field one character at a time, waiting until each one shows.
    ///
    /// Typing a whole amount at once lost or reordered keystrokes on a busy simulator,
    /// such as "43290" for "432.90", so a test could check an amount nobody meant to enter.
    /// A number field may regroup its text while it is being typed ("1,000" for "1000"), a
    /// SwiftUI race under load, so grouping separators are ignored; the decimal point is not.
    /// This assumes the en_US locale the tests launch with (`languageArguments`): in Ukrainian
    /// the comma is the decimal separator and must not be dropped.
    ///
    /// - Parameters:
    ///   - text: The text to type, appended to what the field already holds.
    ///   - field: The focused field.
    func type(_ text: String, into field: XCUIElement) {
        func ungrouped(_ value: String) -> String { value.filter { $0 != "," && !$0.isWhitespace } }
        var expected = field.value as? String ?? ""
        if expected == field.placeholderValue { expected = "" }
        for character in text {
            expected.append(character)
            field.typeText(String(character))
            let target = ungrouped(expected)
            let shown = NSPredicate { _, _ in ungrouped(field.value as? String ?? "") == target }
            XCTAssertEqual(
                XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: nil)], timeout: 10),
                .completed, "The field shows \(field.value ?? "nothing") instead of \(expected)")
        }
    }

    /// Returns the link a fiscal receipt's QR code holds, with the time printed in Kyiv time.
    ///
    /// - Parameters:
    ///   - amount: The receipt total as printed, such as "432.90".
    ///   - date: When the receipt was issued.
    func receiptPayload(amount: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Kyiv")
        formatter.dateFormat = "'date='yyyyMMdd'&time='HHmm"
        return "https://cabinet.tax.gov.ua/cashregs/check?\(formatter.string(from: date))&sm=\(amount)&fn=4000123456"
    }

    /// Returns Kalyta's widget on the Home Screen, adding it first if it is not there.
    func homeScreenWidget() -> XCUIElement {
        let icons = springboard.icons.matching(identifier: "Kalyta")
        // The app's own icon shares the name, and the value "Widget" is localized, so the widget is the wide one.
        func widget() -> XCUIElement? { icons.allElementsBoundByIndex.first { $0.frame.width > 100 } }
        _ = icons.firstMatch.waitForExistence(timeout: 3)
        if widget() == nil { addWidget() }
        for _ in 0..<10 where widget() == nil { sleep(1) }
        let found = widget()
        XCTAssertNotNil(found, "The widget is not on the Home Screen")
        return found ?? icons.firstMatch
    }

    /// Adds Kalyta's small widget to the Home Screen through the widget gallery.
    ///
    /// The gallery's labels are English, so this runs only on a simulator set to English.
    private func addWidget() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).press(forDuration: 2.5)
        let edit = springboard.buttons["Edit"].firstMatch
        let addWidgetItem = springboard.buttons["Add Widget"].firstMatch
        // On a busy simulator the Edit menu sometimes ignores the first tap.
        for _ in 0..<4 where !addWidgetItem.exists {
            if edit.waitForExistence(timeout: 5) { edit.tap() }
            _ = addWidgetItem.waitForExistence(timeout: 5)
        }
        addWidgetItem.tap()
        // A freshly installed app's widgets reach the gallery late; searching lists them sooner.
        let search = springboard.searchFields["Search Widgets"].firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Kalyta")
        }
        let kalyta = springboard.cells["Kalyta"].firstMatch
        XCTAssertTrue(kalyta.waitForExistence(timeout: 30), "The widget gallery does not list Kalyta")
        kalyta.tap()
        // The gallery's button label starts with a symbol, so it only ends with the words.
        let add = springboard.buttons.matching(NSPredicate(format: "label ENDSWITH 'Add Widget'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "The gallery offers no Add Widget button")
        add.tap()
        let done = springboard.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 5) { done.tap() }
    }
}
