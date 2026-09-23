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
        XCTAssertTrue(preview().contains("8 already here"), "Unexpected preview: \(preview())")
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

    /// Exports all expenses and saves the file to On My iPhone under a unique name.
    ///
    /// - Returns: The file name without the extension.
    private func saveBackup() -> String {
        let name = "backup-\(UUID().uuidString.prefix(8))"
        _ = app.staticTexts["summaryTitle"].waitForExistence(timeout: 5)
        app.buttons["Export"].tap()
        let saveToFiles = app.cells["Save to Files"].firstMatch
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 5))
        saveToFiles.tap()

        // A unique name: a file with the default name may be left from an earlier run.
        let field = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 5) + name)
        app.buttons["DOCPicker.actionButton"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForNonExistence(timeout: 5), "The file was not saved")
        return name
    }

    /// Deletes an expense and waits until the undo window closes, so the deletion is saved.
    private func deleteAndCommit(_ note: String) {
        row(note).swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Undo"].waitForNonExistence(timeout: 10), "The deletion was never committed")
    }

    /// Opens Settings → Import from CSV and picks the file.
    private func openImport(of name: String) {
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Import from CSV"].tap()
        let file = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10), "The backup is not offered in the file picker")
        file.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10), "No preview after picking the file")
    }

    /// Returns the text of the import preview alert.
    private func preview() -> String {
        app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n")
    }
}
