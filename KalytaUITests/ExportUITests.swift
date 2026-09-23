import XCTest

/// End-to-end checks of the CSV export through the share sheet.
final class ExportUITests: KalytaUITestCase {
    /// Save to Files proposes a file named after today's date, not a generic "Data".
    func testExportNamesFileByDate() {
        openExport()
        let saveToFiles = app.cells["Save to Files"].firstMatch
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 5))
        saveToFiles.tap()

        let fileName = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(fileName.waitForExistence(timeout: 5))
        let today = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        XCTAssertEqual(fileName.value as? String, "Kalyta-\(today)")
    }

    /// An expense waiting in the undo window is left out of the export.
    func testExportExcludesPendingDeletion() {
        openExport()
        let countBefore = exportedCount()
        closeExport()

        scrollDown(until: app.staticTexts["Метро"])
        row("Метро").swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2))

        openExport()
        XCTAssertEqual(exportedCount(), countBefore - 1, "The export still includes the expense pending deletion")
    }

    /// Taps the Export button in the toolbar and waits for the share sheet.
    private func openExport() {
        let export = app.buttons["Export"]
        for _ in 0..<maxScrolls where !export.isHittable { app.swipeDown() }
        export.tap()
        XCTAssertTrue(shareSheetTitle().waitForExistence(timeout: 5), "The share sheet did not open")
    }

    /// Closes the share sheet.
    private func closeExport() {
        let close = app.buttons["Close"].firstMatch
        if close.exists { close.tap() } else { shareSheetTitle().swipeDown(velocity: .fast) }
        XCTAssertTrue(shareSheetTitle().waitForNonExistence(timeout: 5), "The share sheet did not close")
    }

    /// Returns the share sheet's navigation bar, titled with the number of exported expenses.
    private func shareSheetTitle() -> XCUIElement {
        app.navigationBars.matching(NSPredicate(format: "identifier ENDSWITH %@", "expenses")).firstMatch
    }

    /// Returns the number of expenses the share sheet says it exports, such as 9 for "9 expenses".
    private func exportedCount() -> Int {
        Int(digits(shareSheetTitle().identifier)) ?? -1
    }
}
