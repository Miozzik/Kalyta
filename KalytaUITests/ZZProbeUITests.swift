import XCTest

final class ZZProbeUITests: XCTestCase {
    let out = "/private/tmp/claude-501/-Users-miozz-claude-projects/6b966f09-a6bd-4447-bbae-f72807d5699e/scratchpad/probe"
    func dump(_ name: String, _ app: XCUIApplication) {
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        try? app.debugDescription.write(toFile: "\(out)/\(name).txt", atomically: true, encoding: .utf8)
    }
    func testProbe() {
        XCUIApplication(bundleIdentifier: "com.apple.shortcuts").terminate()
        let k = XCUIApplication()
        k.launchArguments = ["--demo"]
        k.launch()
        sleep(3); dump("00-start", k)
        k.tabBars.buttons["Settings"].tap()
        k.buttons["Set Up Automatic Recording"].tap()
        sleep(1); dump("01-guide", k)
        k.buttons["Add the Shortcut"].tap()
        sleep(3)
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        dump("02-share", k); _ = sb
        k.cells["Shortcuts"].tap()
        let sc = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        sleep(4)
        if sc.buttons["Continue"].exists { sc.buttons["Continue"].tap() }
        sleep(2); dump("03-import", sc)
        sc.buttons["Add Shortcut"].firstMatch.tap()
        sleep(3); dump("04-added", sc)
        k.activate()
        k.buttons["Open the Shortcut"].tap()
        sleep(4); dump("05-open", sc)
        sc.buttons["Editor"].tap()
        sleep(2); dump("06-editor", sc)
        sc.buttons["Kalyta Autopay, Actions Menu"].tap()
        sleep(2); dump("07-menu", sc)
        sc.tap()
        sleep(1)
        sc.buttons["info"].tap()
        sleep(2); dump("08-info", sc)
    }
    }
