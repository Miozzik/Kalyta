import AVFoundation
import SwiftUI
import WidgetKit

/// One way Kalyta records spending with little or no typing, as listed in Settings → Automation.
///
/// The order of the cases is the order of the rows; it never changes, only the statuses do.
enum AutomationRow: CaseIterable {
    case monobank, applePay, backTap, actionButton, widgets, receipt

    /// Whether the app can see that the row is in use; Siri and the Action button are always
    /// available, so counting them would show progress the person never made.
    var isDetectable: Bool { self != .actionButton }

    /// The rows that count towards "N of M set up".
    static var detectable: [AutomationRow] { allCases.filter(\.isDetectable) }
}

/// What Settings → Automation shows next to a row.
enum AutomationStatus: Equatable {
    /// Nothing shows it is in use yet.
    case notSetUp
    /// monobank is linked.
    case connected
    /// The Transaction automation has recorded a payment.
    case works
    /// Add Expense ran without a merchant, as Back Tap and Siri run it.
    case quickAddUsed
    /// Works without any setup.
    case ready
    /// The widget or the control is placed in at least one of these places.
    case placed(homeScreen: Bool, lockScreen: Bool, controlCenter: Bool)
    /// Camera access is off, so the scanner cannot open.
    case cameraDenied
    /// monobank is linked, but the last sync hit a problem the person has to fix.
    case needsAttention

    /// Whether the status shows the row in use.
    var isSetUp: Bool { ![.notSetUp, .cameraDenied, .needsAttention].contains(self) }

    /// The trailing text of the row, or `nil` to show none.
    var text: String? {
        switch self {
        case .notSetUp: return nil
        case .connected: return String(localized: "Connected ✓")
        case .works: return String(localized: "Works ✓")
        case .quickAddUsed: return String(localized: "Quick add used ✓")
        case .ready: return String(localized: "Ready ✓")
        case .cameraDenied: return String(localized: "Camera off")
        case .needsAttention: return String(localized: "Needs attention")
        case .placed(let home, let lock, let control):
            let places = [
                (home, String(localized: "Home Screen")), (lock, String(localized: "Lock Screen")),
                (control, String(localized: "Control Center")),
            ]
            return "\(places.filter(\.0).map(\.1).formatted(.list(type: .and))) ✓"
        }
    }
}

/// Everything the statuses depend on, read from the system in one place.
struct AutomationInputs {
    /// Whether monobank is linked.
    var isMonobankLinked = false
    /// Whether the last monobank sync ended with a problem the person has to fix.
    var monobankProblem = false
    /// When Add Expense last ran with a merchant, as seconds since 1970; 0 means never.
    var lastRunWithMerchant: Double = 0
    /// When Add Expense last ran without a merchant, as seconds since 1970; 0 means never.
    var lastRunWithoutMerchant: Double = 0
    /// The kind and family of every placed widget of the app.
    var widgets: [(kind: String, family: WidgetFamily)] = []
    /// The kind of every placed control of the app.
    var controls: [String] = []
    /// Camera access for video.
    var camera: AVAuthorizationStatus = .notDetermined

    /// The kind of the receipt control in Control Center, on the Lock Screen or the Action button.
    static let controlKind = "ScanReceiptControl"

    /// Reads the current inputs; the widget and control lists come from WidgetKit asynchronously.
    @MainActor
    static func current() async -> AutomationInputs {
        let defaults = UserDefaults.standard
        var inputs = AutomationInputs(
            isMonobankLinked: defaults.bool(forKey: MonobankSync.linkedKey),
            lastRunWithMerchant: defaults.double(forKey: QuickAddExpense.lastRunWithMerchantKey),
            lastRunWithoutMerchant: defaults.double(forKey: QuickAddExpense.lastRunWithoutMerchantKey),
            camera: AVCaptureDevice.authorizationStatus(for: .video))
        let state = defaults.data(forKey: MonobankSync.stateKey).flatMap {
            try? JSONDecoder().decode(MonobankSync.State.self, from: $0)
        }
        inputs.monobankProblem = state?.problem != nil
        let infos = await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { continuation.resume(returning: (try? $0.get()) ?? []) }
        }
        inputs.widgets = infos.map { ($0.kind, $0.family) }
        if #available(iOS 18, *) {
            inputs.controls = ((try? await ControlCenter.shared.currentControls()) ?? []).map(\.kind)
        }
        return inputs
    }

    /// How many detectable rows are in use, for "N of M set up".
    var setUpCount: Int { AutomationRow.detectable.filter { status(of: $0).isSetUp }.count }

    /// Returns the status of a row.
    ///
    /// - Parameter row: The row to describe.
    /// - Returns: What the row shows.
    func status(of row: AutomationRow) -> AutomationStatus {
        switch row {
        case .monobank:
            guard isMonobankLinked else { return .notSetUp }
            return monobankProblem ? .needsAttention : .connected
        case .applePay: return lastRunWithMerchant > 0 ? .works : .notSetUp
        case .backTap: return lastRunWithoutMerchant > 0 ? .quickAddUsed : .notSetUp
        // App Shortcuts are registered on install, so Siri and the Action button find Add Expense at once.
        case .actionButton: return .ready
        case .widgets:
            let families = widgets.filter { $0.kind == TodayTotal.widgetKind }.map(\.family)
            let home = families.contains {
                [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge].contains($0)
            }
            let lock = families.contains { [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains($0) }
            let control = controls.contains(Self.controlKind)
            return home || lock || control
                ? .placed(homeScreen: home, lockScreen: lock, controlCenter: control) : .notSetUp
        case .receipt:
            switch camera {
            case .authorized: return .ready
            case .denied, .restricted: return .cameraDenied
            default: return .notSetUp
            }
        }
    }
}
