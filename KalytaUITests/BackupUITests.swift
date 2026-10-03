import XCTest

/// End-to-end checks of the full JSON backup: saving it, the Settings subtitle, and restoring it.
final class BackupUITests: KalytaUITestCase {
    /// Only a saved file sets the Settings subtitle.
    func testSavedBackupShowsLastExport() {
        XCTAssertTrue(backupRow(contains: "Not exported yet"), "Unexpected row: \(settingsBackupRow().label)")
        _ = saveBackup(isJSON: true)
        XCTAssertTrue(backupRow(contains: "Last export"), "Unexpected row: \(settingsBackupRow().label)")
    }

    /// Cancelling the save dialog records no export.
    func testCancelledSaveRecordsNoExport() {
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Backup"].tap()
        app.buttons["Export Backup"].tap()
        // Cancel shows only at the dialog's top level; inside a folder, Back leads there.
        let dialog = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 20), "The save dialog did not open")
        let cancel = dialog.buttons["Cancel"]
        if !cancel.waitForExistence(timeout: 3) { dialog.buttons["BackButton"].tap() }
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "The save dialog offers no Cancel")
        cancel.tap()
        XCTAssertTrue(app.buttons["Export Backup"].waitForExistence(timeout: 5), "The save dialog did not close")
        XCTAssertTrue(backupRow(contains: "Not exported yet"), "Unexpected row: \(settingsBackupRow().label)")
    }

    /// Restoring shows one line per type, brings back a deleted entry, and a second restore adds nothing.
    func testRestoreThenReimportAddsNothing() {
        let backup = saveBackup(isJSON: true)
        deleteAndCommit("Метро")

        openImport(of: backup)
        for line in [
            "Entries: 1 new, 9 already here", "Categories: 0 new, 8 kept as on this phone",
            "Subscriptions: 0 new, 0 already here",
        ] {
            XCTAssertTrue(preview().contains(line), "No \"\(line)\" in: \(preview())")
        }
        XCTAssertFalse(preview().contains("built-in"), "The empty-app rule fired with entries here: \(preview())")
        app.alerts.buttons["Import"].tap()
        let done = app.alerts.staticTexts["Restored — entries: 1, categories: 0, subscriptions: 0."]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "No restore result")
        app.alerts.buttons["OK"].tap()

        openImport(of: backup)
        XCTAssertTrue(preview().contains("Entries: 0 new, 10 already here"), "Unexpected preview: \(preview())")
        XCTAssertFalse(app.alerts.buttons["Import"].isEnabled, "Import is offered with nothing to add")
        app.alerts.buttons["Cancel"].tap()

        app.tabBars.buttons["Expenses"].tap()
        XCTAssertEqual(listedCount("Метро"), 1, "The restored entry is missing or doubled")
    }

    /// Returns the Settings → Backup row, going back to Settings first.
    private func settingsBackupRow() -> XCUIElement {
        app.tabBars.buttons["Settings"].tap()
        let back = app.navigationBars["Backup"].buttons["Settings"]
        if back.exists { back.tap() }
        return app.buttons["Backup"]
    }

    /// Returns whether the Settings → Backup row's label contains `text`.
    private func backupRow(contains text: String) -> Bool {
        let row = settingsBackupRow()
        return row.waitForExistence(timeout: 5) && row.label.contains(text)
    }
}
