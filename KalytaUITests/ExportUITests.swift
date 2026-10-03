import XCTest

/// End-to-end checks of the CSV export from Settings → Backup through the share sheet.
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

    /// Settings → Backup holds both export and import.
    func testBackupShowsExportAndImport() {
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Backup"].tap()
        XCTAssertTrue(app.buttons["Export Backup"].waitForExistence(timeout: 5), "No export section")
        XCTAssertTrue(app.buttons["Import from CSV"].exists, "No import section")
    }

    /// An expense waiting in the undo window is left out of the export.
    func testExportExcludesPendingDeletion() {
        openExport()
        let countBefore = exportedCount()
        closeExport()

        app.tabBars.buttons["Expenses"].tap()
        scrollDown(until: app.staticTexts["Метро"])
        row("Метро").swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2))

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Export Backup"].tap()
        XCTAssertTrue(shareSheetTitle().waitForExistence(timeout: 5), "The share sheet did not open")
        XCTAssertEqual(exportedCount(), countBefore - 1, "The export still includes the expense pending deletion")
    }

    /// Opens Settings → Backup, taps Export Backup and waits for the share sheet.
    private func openExport() {
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Backup"].tap()
        app.buttons["Export Backup"].tap()
        XCTAssertTrue(shareSheetTitle().waitForExistence(timeout: 5), "The share sheet did not open")
    }

    /// Closes the share sheet by tapping the dimmed area above it.
    private func closeExport() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(shareSheetTitle().waitForNonExistence(timeout: 5), "The share sheet did not close")
    }

    /// Returns the share sheet's navigation bar, titled with the number of exported entries.
    private func shareSheetTitle() -> XCUIElement {
        app.navigationBars.matching(NSPredicate(format: "identifier ENDSWITH %@", "entries")).firstMatch
    }

    /// Returns the number of entries the share sheet says it exports, such as 10 for "10 entries".
    private func exportedCount() -> Int {
        Int(digits(shareSheetTitle().identifier)) ?? -1
    }
}
