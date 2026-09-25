import XCTest

/// End-to-end checks of the Home Screen widget that opens the receipt scanner.
///
/// The widget opens the app through `widgetURL`, and the app registers no URL scheme, so
/// these tests are the only proof the link arrives. The simulator has no scanner, so
/// `-scanPayload` stands in for the camera: a filled amount proves the scan started by itself.
///
/// On a freshly erased simulator the widget gallery lists Kalyta only after the simulator
/// restarts, however long a test waits. Before running these tests on a new or erased
/// simulator: install and launch the app once, then shut the simulator down and boot it.
final class WidgetUITests: KalytaUITestCase {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// Tapping the widget opens the entry sheet with the scanner already up.
    func testWidgetOpensScanner() {
        relaunch(with: ["--demo", "-scanPayload", receiptPayload(amount: "987.65", at: .now)])
        XCUIDevice.shared.press(.home)
        homeScreenWidget().tap()

        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 20), "The widget did not open the entry sheet")
        let filled = expectation(for: NSPredicate(format: "value == %@", "987.65"), evaluatedWith: amount)
        XCTAssertEqual(
            XCTWaiter().wait(for: [filled], timeout: 5), .completed,
            "The sheet opened without scanning: the amount shows \(amount.value ?? "nothing")")
    }

    /// A request while another sheet is open is dropped: it neither scans into that sheet
    /// nor opens the scanner once that sheet closes.
    func testRequestOverOpenSheetIsDropped() {
        relaunch(with: ["--demo", "-scanPayload", receiptPayload(amount: "987.65", at: .now)])
        app.buttons["Add"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "The Add sheet did not open")
        XCUIDevice.shared.press(.home)
        homeScreenWidget().tap()

        XCTAssertTrue(amount.waitForExistence(timeout: 20), "The app did not come back with the Add sheet")
        // A scan fills the amount within a second or two; give it time to show if it happens.
        let scanned = expectation(for: NSPredicate(format: "value == %@", "987.65"), evaluatedWith: amount)
        XCTAssertEqual(
            XCTWaiter().wait(for: [scanned], timeout: 3), .timedOut, "The request scanned into the open sheet")
        app.buttons["cancelButton"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5), "The Add sheet did not close")
        XCTAssertFalse(amount.waitForExistence(timeout: 3), "The dropped request opened the scanner later")
    }

    /// Returns Kalyta's widget on the Home Screen, adding it first if it is not there.
    ///
    /// Springboard lists a widget as an icon named after the app, with the value "Widget".
    private func homeScreenWidget() -> XCUIElement {
        let widget = springboard.icons.matching(NSPredicate(format: "identifier == 'Kalyta' AND value == 'Widget'"))
            .firstMatch
        if !widget.waitForExistence(timeout: 3) { addWidget() }
        XCTAssertTrue(widget.waitForExistence(timeout: 10), "The widget is not on the Home Screen")
        return widget
    }

    /// Adds Kalyta's small widget to the Home Screen through the widget gallery.
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
