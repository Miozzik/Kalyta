import AppIntents
import Foundation
import Observation

/// The action that opens Kalyta with the receipt scanner already up.
///
/// Siri, Spotlight, the Action button and Back Tap reach it through ``KalytaShortcuts``.
struct ScanReceiptIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Receipt"
    static var description = IntentDescription("Opens Kalyta with the camera ready to scan a receipt's QR code.")
    // `supportedModes` replaces this from iOS 26 on, but the app still supports iOS 17.
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ScanRequest.shared.isPending = true
        return .result()
    }
}

/// A request from outside the app to open the entry sheet with the scanner.
@MainActor
@Observable
final class ScanRequest {
    /// The one request the app's scene observes.
    static let shared = ScanRequest()

    /// The link the widget opens the app with to ask for the scanner.
    ///
    /// No app registers the scheme, so no web page or other app can send it; only the widget does.
    nonisolated static let url = URL(string: "kalyta://scan")!

    /// Whether the scanner was asked for and the app has not answered yet.
    var isPending = false
}
