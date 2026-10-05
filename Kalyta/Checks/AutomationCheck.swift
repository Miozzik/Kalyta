import AVFoundation
import Foundation
import SwiftData
import WidgetKit

/// Verifies Settings → Automation: every branch of the status function, the markers Add Expense
/// leaves, and that Add Expense is an App Shortcut.
///
/// The markers are checked by running the action on the shared store, which must hold the Food
/// probe with the note "selfcheck" that ``runSelfCheck()`` inserts; the markers the person had are restored.
@MainActor
func runAutomationCheck() {
    // The rows never move.
    assert(
        AutomationRow.allCases == [.monobank, .applePay, .backTap, .actionButton, .widgets, .receipt],
        "The automation rows changed order")

    var inputs = AutomationInputs()
    assert(
        AutomationRow.allCases.map { inputs.status(of: $0) } == [
            .notSetUp, .notSetUp, .notSetUp, .ready, .notSetUp, .notSetUp,
        ],
        "Nothing set up does not read as not set up")
    // Siri is always ready, so it is not counted: nothing set up is 0 of 5.
    assert(AutomationRow.detectable.count == 5 && inputs.setUpCount == 0, "Siri counts as set up")
    inputs.isMonobankLinked = true
    assert(inputs.status(of: .monobank) == .connected, "A linked monobank is not Connected")
    inputs.lastRunWithMerchant = 1
    assert(inputs.status(of: .applePay) == .works, "A run with a merchant did not mark Apple Pay")
    assert(inputs.status(of: .backTap) == .notSetUp, "A run with a merchant marked Back Tap")
    inputs.lastRunWithoutMerchant = 1
    assert(inputs.status(of: .backTap) == .quickAddUsed, "A run without a merchant did not mark Back Tap")

    // Widgets: only the app's own kinds count; the family tells the Home Screen from the Lock Screen.
    inputs.widgets = [("OtherWidget", .systemSmall)]
    inputs.controls = ["OtherControl"]
    assert(inputs.status(of: .widgets) == .notSetUp, "Another kind of widget or control counted")
    inputs.widgets = [(TodayTotal.widgetKind, .systemSmall)]
    assert(inputs.status(of: .widgets) == .placed(homeScreen: true, lockScreen: false, controlCenter: false), "Home")
    inputs.widgets = [(TodayTotal.widgetKind, .accessoryRectangular), (TodayTotal.widgetKind, .accessoryCircular)]
    assert(inputs.status(of: .widgets) == .placed(homeScreen: false, lockScreen: true, controlCenter: false), "Lock")
    inputs.widgets = []
    inputs.controls = [AutomationInputs.controlKind]
    assert(inputs.status(of: .widgets) == .placed(homeScreen: false, lockScreen: false, controlCenter: true), "Control")

    let camera: [(AVAuthorizationStatus, AutomationStatus)] = [
        (.authorized, .ready), (.denied, .cameraDenied), (.restricted, .cameraDenied), (.notDetermined, .notSetUp),
    ]
    for (authorization, expected) in camera {
        inputs.camera = authorization
        assert(inputs.status(of: .receipt) == expected, "Camera \(authorization.rawValue) gave the wrong status")
    }
    assert(!AutomationStatus.cameraDenied.isSetUp && !AutomationStatus.notSetUp.isSetUp, "Off counted as set up")
    inputs.camera = .authorized
    assert(AutomationRow.allCases.allSatisfy { inputs.status(of: $0).isSetUp }, "A set-up row did not show")
    assert(inputs.setUpCount == 5, "Every detectable row is set up, but the count is \(inputs.setUpCount)")
    assert(AutomationStatus.placed(homeScreen: true, lockScreen: false, controlCenter: true).text != nil, "No text")

    // The wiring: the action itself must leave the right marker.
    let defaults = UserDefaults.standard
    let keys = [QuickAddExpense.lastRunWithMerchantKey, QuickAddExpense.lastRunWithoutMerchantKey]
    keepingRunMarkers {
        for key in keys { defaults.removeObject(forKey: key) }
        runQuickAdd(note: " SELFCHECK")
        assert(defaults.double(forKey: keys[0]) > 0, "A run with a merchant left no with-merchant marker")
        assert(defaults.double(forKey: keys[1]) == 0, "A run with a merchant left the without-merchant marker")
        runQuickAdd(note: "")
        assert(defaults.double(forKey: keys[1]) > 0, "A run without a merchant left no without-merchant marker")
    }

    // Add Expense is an App Shortcut: the build writes the provider into the bundle's metadata, which iOS reads.
    let metadata = Bundle.main.url(
        forResource: "extract", withExtension: "actionsdata", subdirectory: "Metadata.appintents")
    let json = metadata.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONSerialization.jsonObject(with: $0) }
    let shortcuts = ((json as? [String: Any])?["autoShortcuts"] as? [[String: Any]]) ?? []
    assert(
        shortcuts.contains { $0["actionIdentifier"] as? String == "QuickAddExpense" },
        "Add Expense is not an App Shortcut")
}

/// Runs checks that run Add Expense, then puts back the markers the person had.
///
/// - Parameter body: The checks.
@MainActor
func keepingRunMarkers(_ body: () -> Void) {
    let keys = [QuickAddExpense.lastRunWithMerchantKey, QuickAddExpense.lastRunWithoutMerchantKey]
    let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
    body()
    for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
}

/// Runs Add Expense with the Food category and removes the entry it adds.
@MainActor
private func runQuickAdd(note: String) {
    let context = Store.container.mainContext
    let before = Set(try! context.fetch(FetchDescriptor<Expense>()).map(\.persistentModelID))
    let intent = QuickAddExpense()
    intent.amount = 1
    intent.note = note
    // A category is set, so the run without a merchant does not ask for one.
    intent.category = CategoryEntity(Store.category(withKey: "food", in: context)!)
    let succeeded = wait { (try? await intent.perform()) != nil }
    assert(succeeded, "Add Expense failed")
    for expense in try! context.fetch(FetchDescriptor<Expense>()) where !before.contains(expense.persistentModelID) {
        context.delete(expense)
    }
    try! context.save()
}
