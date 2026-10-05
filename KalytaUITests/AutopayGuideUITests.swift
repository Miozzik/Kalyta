import XCTest

/// Captures the Shortcuts screens that Settings → Automation → Apple Pay Payments shows, cropped for the guide.
///
/// Shortcuts and the share sheet follow the system language, not the app's launch arguments,
/// so `scripts/autopay-screenshots.sh` sets the simulator's language, runs this test once per
/// language and copies the images into the asset catalog. Skipped unless
/// `KALYTA_GUIDE_LANGUAGE` reaches the test runner.
///
/// The Transaction trigger of step 2 is not captured: the simulator's Shortcuts has no
/// Automation in the shortcut editor, so that screen exists only on an iPhone.
final class AutopayGuideUITests: XCTestCase {
    /// Labels without an accessibility identifier, per system language.
    private static let labels: [String: [String: String]] = [
        "en": [
            "addTheShortcut": "Add the Shortcut",
            "continue": "Continue", "addShortcut": "Add Shortcut", "info": "info", "privacy": "Privacy",
        ],
        "uk": [
            "addTheShortcut": "Додати команду",
            "continue": "Далі", "addShortcut": "Додати команду", "info": "інформація", "privacy": "Приватність",
        ],
    ]
    /// The width of a saved image in pixels: sharp at the guide's width on a 3x screen.
    private let imageWidth: CGFloat = 900

    func testCaptureGuideScreens() throws {
        let language = ProcessInfo.processInfo.environment["KALYTA_GUIDE_LANGUAGE"] ?? ""
        guard let label = Self.labels[language] else { throw XCTSkip("Run scripts/autopay-screenshots.sh") }
        continueAfterFailure = false

        let kalyta = XCUIApplication()
        kalyta.launch()
        let settings = kalyta.buttons["gearshape"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        kalyta.buttons["Automation"].tap()
        kalyta.buttons["automation.applePay"].tap()
        kalyta.buttons[label["addTheShortcut"]!].tap()

        // Step 1: the share sheet. A tap while the sheet still animates is lost, so retry
        // until Shortcuts comes up.
        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        var captured = false
        for _ in 0..<5 where shortcuts.state != .runningForeground {
            // On a clean simulator Shortcuts is the only app the sheet suggests.
            let app = kalyta.cells.matching(identifier: "shareCell").firstMatch
            guard app.waitForExistence(timeout: 10) else {
                kalyta.buttons[label["addTheShortcut"]!].tap()
                continue
            }
            sleep(2)
            if !captured {
                save("share", from: app.frame.minY - 112, to: .greatestFiniteMagnitude)
                captured = true
            }
            if app.isHittable { app.tap() }
            _ = shortcuts.wait(for: .runningForeground, timeout: 20)
        }

        // Step 1: the import screen. The first launch of Shortcuts on a clean simulator is slow
        // and opens with What's New.
        let add = shortcuts.buttons[label["addShortcut"]!].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 60), "Shortcuts did not open the shortcut")
        let whatsNew = shortcuts.buttons[label["continue"]!]
        if whatsNew.exists { whatsNew.tap() }
        sleep(2)
        save("import", from: add.frame.minY - 100, to: add.frame.maxY + 24)
        add.tap()

        // Step 3: ⓘ → Privacy → Allow Running When Locked. Shortcuts opens the new shortcut
        // in the editor right after the import.
        let info = shortcuts.buttons[label["info"]!]
        XCTAssertTrue(info.waitForExistence(timeout: 15), shortcuts.debugDescription)
        sleep(3)
        if !info.isHittable {
            // The editor sometimes opens in Describe a Shortcut, which pushes ⓘ off screen; the
            // last button of the navigation bar switches to the classic editor.
            shortcuts.navigationBars.firstMatch.buttons.allElementsBoundByIndex.last?.tap()
            sleep(2)
        }
        info.tap()
        let privacy = shortcuts.buttons[label["privacy"]!]
        XCTAssertTrue(privacy.waitForExistence(timeout: 5), shortcuts.debugDescription)
        privacy.tap()
        let locked = shortcuts.switches.firstMatch
        XCTAssertTrue(locked.waitForExistence(timeout: 5))
        sleep(1)
        save("locked", from: locked.frame.minY - 130, to: locked.frame.maxY + 24)
    }

    /// Attaches a full-width band of the screen as a JPEG named `autopay-<name>.jpg`.
    ///
    /// - Parameters:
    ///   - name: The guide image it becomes.
    ///   - top: The band's top edge in points.
    ///   - bottom: The band's bottom edge in points.
    private func save(_ name: String, from top: CGFloat, to bottom: CGFloat) {
        let screen = XCUIScreen.main.screenshot().image
        let band = CGRect(
            x: 0, y: max(0, top), width: screen.size.width, height: min(bottom, screen.size.height) - max(0, top))
        let pixels = band.applying(CGAffineTransform(scaleX: screen.scale, y: screen.scale))
        guard let cropped = screen.cgImage?.cropping(to: pixels.integral) else { return XCTFail("Cannot crop \(name)") }
        let size = CGSize(width: imageWidth, height: imageWidth * band.height / band.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: size))
        }
        let attachment = XCTAttachment(
            data: image.jpegData(compressionQuality: 0.6)!, uniformTypeIdentifier: "public.jpeg")
        attachment.name = "autopay-\(name).jpg"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
