import XCTest

/// Captures the main screens as test attachments, for design review and the README.
///
/// Skipped unless `KALYTA_SCREENSHOTS=1` reaches the test runner; the images are in the
/// result bundle (`xcrun xcresulttool export attachments`).
final class ScreenshotUITests: KalytaUITestCase {
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo", "-demoOffsetDays", "0", "-AppleLanguages", "(uk)", "-AppleLocale", "uk_UA"]
        app.launch()
    }

    func testCaptureStatistics() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KALYTA_SCREENSHOTS"] == "1", "Set KALYTA_SCREENSHOTS=1")
        app.tabBars.buttons.element(boundBy: 2).tap()
        capture("statistics")
        for (index, name) in ["months", "categories", "places", "biggest"].enumerated() {
            app.cells.element(boundBy: index + 1).tap()
            sleep(1)
            capture(name)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    /// Adds a screenshot of the current screen to the result bundle.
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
