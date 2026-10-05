import AVFoundation
import AppIntents
import SwiftUI

/// Settings → Automation: every way Kalyta records spending by itself or in one tap, with its status.
struct AutomationView: View {
    @State private var inputs = AutomationInputs()

    var body: some View {
        List {
            Section {
                row(.monobank)
                row(.applePay)
            } header: {
                Text("Records by itself")
            } footer: {
                Text("Pay cash or with a card not in Wallet? The ones below record in 2 seconds.")
            }
            Section("One-tap capture") {
                row(.backTap)
                row(.actionButton)
                row(.widgets)
                row(.receipt)
            }
        }
        .navigationTitle("Automation")
        // Runs again on every return from a guide, so a status changed there shows at once.
        .task { inputs = await .current() }
    }

    /// A row: title, benefit and status; it opens the row's screen.
    private func row(_ row: AutomationRow) -> some View {
        let status = inputs.status(of: row)
        return NavigationLink {
            destination(of: row)
        } label: {
            LabeledContent {
                if status == .needsAttention {
                    Label(status.text ?? "", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                } else if let text = status.text {
                    Text(text).foregroundStyle(status.isSetUp ? .green : .secondary)
                }
            } label: {
                Label {
                    Text(row.title)
                    Text(row.benefit)
                } icon: {
                    Image(systemName: row.symbol)
                }
            }
        }
        // The label joins title, benefit and status, so tests find the row by this identifier.
        .accessibilityIdentifier("automation.\(row)")
    }

    @ViewBuilder
    private func destination(of row: AutomationRow) -> some View {
        switch row {
        case .monobank: MonobankView()
        case .applePay: AutopaySetupView()
        case .backTap: BackTapGuide()
        case .actionButton: ActionButtonGuide()
        case .widgets: WidgetsGuide()
        case .receipt: ReceiptGuide(camera: inputs.camera)
        }
    }
}

extension AutomationRow {
    /// The row's name.
    var title: LocalizedStringResource {
        switch self {
        case .monobank: "monobank Sync"
        case .applePay: "Apple Pay Payments"
        case .backTap: "Back Tap"
        case .actionButton: "Action Button & Siri"
        case .widgets: "Widgets & Control Center"
        case .receipt: "Scan a Receipt"
        }
    }

    /// What the row gives, in a few words.
    var benefit: LocalizedStringResource {
        switch self {
        case .monobank: "Your plastic card too"
        case .applePay: "Every payment lands in your history by itself"
        case .backTap: "Tap-tap, then enter the amount"
        case .actionButton: "“Add an expense in Kalyta”"
        case .widgets: "Today’s total and the scanner, one tap away"
        case .receipt: "Amount and date from the receipt’s QR code"
        }
    }

    /// The SF Symbol of the row.
    var symbol: String {
        switch self {
        case .monobank: "building.columns"
        case .applePay: "wave.3.right"
        case .backTap: "hand.tap"
        case .actionButton: "mic"
        case .widgets: "square.text.square"
        case .receipt: "qrcode.viewfinder"
        }
    }
}

/// A setup guide: what it gives, short numbered steps, and how to check it.
///
/// A step that needs a button carries its own right below it, the first one prominent; the app
/// cannot tell when a step is done, so no single button walks through them.
struct GuideScreen<Steps: View>: View {
    let row: AutomationRow
    let check: LocalizedStringKey
    @ViewBuilder var steps: Steps

    var body: some View {
        List {
            Section {
                Text(row.benefit).font(.title3.weight(.semibold))
            }
            Section {
                steps
            }
            Section("Check it") {
                Text(check)
            }
        }
        .navigationTitle(Text(row.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One numbered step of a guide, a single line.
struct GuideStep: View {
    let number: Int
    let text: LocalizedStringKey

    init(_ number: Int, _ text: LocalizedStringKey) {
        self.number = number
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "\(number).circle")
    }
}

/// How to record an expense with a double tap on the back of the iPhone.
private struct BackTapGuide: View {
    var body: some View {
        GuideScreen(row: .backTap, check: "Double-tap the back of your iPhone: Kalyta asks for the amount.") {
            GuideStep(1, "Open Settings → Accessibility → Touch → Back Tap.")
            GuideStep(2, "Tap Double Tap.")
            GuideStep(3, "Pick Add Expense.")
            Text("If it fires by accident in your pocket, choose Triple Tap.")
                .foregroundStyle(.secondary)
        }
    }
}

/// How to record an expense with Siri, Spotlight or the Action button.
private struct ActionButtonGuide: View {
    var body: some View {
        GuideScreen(row: .actionButton, check: "Ask Siri: Kalyta asks for the amount and the category.") {
            SiriTipView(intent: QuickAddExpense())
            GuideStep(1, "Say “Add an expense in Kalyta” to Siri.")
            GuideStep(2, "Or type Add Expense in Search.")
            GuideStep(3, "Action button: Settings → Action Button → Shortcut → Add Expense.")
            ShortcutsLink()
        }
    }
}

/// How to place the today's-total widget and the scan control.
private struct WidgetsGuide: View {
    var body: some View {
        GuideScreen(row: .widgets, check: "Today’s total shows on the widget after your next entry.") {
            GuideStep(1, "Home Screen: touch and hold, tap Edit → Add Widget → Kalyta.")
            GuideStep(2, "Lock Screen: touch and hold, tap Customize → Lock Screen → Kalyta.")
            GuideStep(3, "Control Center: swipe down, tap +, then Add a Control → Kalyta.")
        }
    }
}

/// How to fill an entry from a receipt's QR code, with a way to Settings when the camera is off.
///
/// The guide never asks for camera access; the scanner does when it first opens.
private struct ReceiptGuide: View {
    let camera: AVAuthorizationStatus
    @Environment(\.openURL) private var openURL

    var body: some View {
        GuideScreen(row: .receipt, check: "The amount and the date fill in by themselves.") {
            GuideStep(1, "Tap + in Expenses, then Scan Receipt.")
            GuideStep(2, "Point the camera at the QR code on the receipt.")
            if camera == .denied || camera == .restricted {
                Text("Camera access is off").foregroundStyle(.secondary)
                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            }
        }
    }
}
