import SwiftUI

/// The signed shortcut that records Wallet payments, and the Shortcuts URL that opens it.
///
/// iOS has no API for an app to create a personal automation, so Kalyta ships a ready shortcut
/// (`Autopay.shortcut`, signed from `scripts/autopay-shortcut.plist`) with one action:
/// Add Expense, Amount = the transaction's Amount, Note = its Merchant. The person imports it
/// and attaches it to a Transaction automation in Shortcuts.
enum AutopayShortcut {
    /// The name the shortcut gets on import; Shortcuts takes it from the file name.
    static var name: String { String(localized: "Kalyta Autopay") }

    /// A copy of the bundled shortcut named after ``name``, or `nil` if it cannot be made.
    static let file: URL? = {
        guard let source = Bundle.main.url(forResource: "Autopay", withExtension: "shortcut") else { return nil }
        let copy = URL.temporaryDirectory.appending(path: "\(name).shortcut")
        try? FileManager.default.removeItem(at: copy)
        return (try? FileManager.default.copyItem(at: source, to: copy)) == nil ? nil : copy
    }()

    /// Opens the imported shortcut in Shortcuts.
    ///
    /// `shortcuts://open-shortcut?name=` is documented in Apple Support, "Open and create
    /// a shortcut using a URL scheme".
    static var openURL: URL {
        var components = URLComponents(string: "shortcuts://open-shortcut")!
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        return components.url!
    }
}

/// Walks the person through recording Apple Pay payments automatically.
struct AutopaySetupView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Text(
                    "Kalyta can record every Apple Pay payment by itself, with its amount and merchant. iOS lets only you switch this on, in Shortcuts. It takes about a minute."
                )
            }
            Section("Step 1") {
                if let file = AutopayShortcut.file {
                    ShareLink(item: file) {
                        Label("Add the Shortcut", systemImage: "square.and.arrow.down")
                    }
                }
                Text("Choose Shortcuts in the list, then tap Add Shortcut.")
            }
            Section("Step 2") {
                Button {
                    openURL(AutopayShortcut.openURL)
                } label: {
                    Label("Open the Shortcut", systemImage: "arrow.up.forward.app")
                }
                Text("Tap Edit, then Automation, then Transaction. Choose your cards and tap Done.")
            }
            Section("Step 3") {
                Text("In the shortcut, tap ⓘ, then Privacy, and turn on Allow Running When Locked.")
            }
        }
        .navigationTitle("Automatic Recording")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Verifies that the bundled shortcut is the signed file and that its name survives the URL.
@MainActor
func runAutopayCheck() {
    let data = AutopayShortcut.file.flatMap { try? Data(contentsOf: $0) }
    // Signed shortcuts are Apple Encrypted Archives; an unsigned plist is refused on import.
    assert(data?.prefix(4) == Data("AEA1".utf8), "The bundled shortcut is missing or not signed")
    assert(AutopayShortcut.file?.lastPathComponent == "\(AutopayShortcut.name).shortcut", "The import name changed")
    let query = URLComponents(url: AutopayShortcut.openURL, resolvingAgainstBaseURL: false)?.queryItems
    assert(query?.first?.value == AutopayShortcut.name, "The shortcut name does not survive the URL")
}
