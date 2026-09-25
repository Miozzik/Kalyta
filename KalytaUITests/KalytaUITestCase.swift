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
    ///
    /// - Parameters:
    ///   - text: The text to type, appended to what the field already holds.
    ///   - field: The focused field.
    func type(_ text: String, into field: XCUIElement) {
        var expected = field.value as? String ?? ""
        if expected == field.placeholderValue { expected = "" }
        for character in text {
            expected.append(character)
            field.typeText(String(character))
            let shown = NSPredicate(format: "value == %@", expected)
            XCTAssertEqual(
                XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: field)], timeout: 10),
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
}
