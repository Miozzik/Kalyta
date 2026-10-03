import XCTest

/// End-to-end checks of restoring a backup: export to Files, change the data, import.
final class ImportUITests: KalytaUITestCase {
    /// A sample expense recorded today.
    private let sampleNote = "Метро"

    /// Restoring a backup brings back an expense deleted after the backup was made.
    func testRestoreBringsBackDeletedExpense() {
        let backup = saveBackup()
        deleteAndCommit(sampleNote)

        openImport(of: backup)
        XCTAssertTrue(preview().contains("1 new expense will be added"), "Unexpected preview: \(preview())")
        XCTAssertTrue(preview().contains("9 already here"), "Unexpected preview: \(preview())")
        app.alerts.buttons["Import"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Imported 1 expense."].waitForExistence(timeout: 10), "No import result")
        app.alerts.buttons["OK"].tap()

        app.tabBars.buttons["Expenses"].tap()
        XCTAssertTrue(isListed(sampleNote), "The restored expense is not listed")
    }

    /// Cancelling the preview writes nothing.
    func testCancelledImportWritesNothing() {
        let backup = saveBackup()
        deleteAndCommit(sampleNote)

        openImport(of: backup)
        app.alerts.buttons["Cancel"].tap()

        app.tabBars.buttons["Expenses"].tap()
        XCTAssertFalse(isListed(sampleNote), "A cancelled import still added the expense")
    }

    /// Importing a backup of data that is already here adds nothing and offers nothing to import.
    func testReimportAddsNothing() {
        let backup = saveBackup()
        openImport(of: backup)
        XCTAssertTrue(preview().contains("0 new expenses will be added"), "Unexpected preview: \(preview())")
        XCTAssertFalse(app.alerts.buttons["Import"].isEnabled, "Import is offered with nothing to add")
        app.alerts.buttons["Cancel"].tap()
    }
}
