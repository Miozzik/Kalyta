import SwiftUI

/// Connects and disconnects the monobank sync (spec: `docs/specs/monobank-ui.md`).
///
/// The token is verified once with `client-info` as soon as it has the right shape, then
/// stored in the Keychain and never shown again.
struct MonobankView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(MonobankSync.linkedKey) private var isLinked = false
    @AppStorage(MonobankSync.stateKey) private var stateData: Data?
    @State private var token = ""
    @State private var isChecking = false
    /// Why the last check failed, shown under the field; `nil` when there is nothing to say.
    @State private var checkMessage: LocalizedStringKey?
    /// The pasteboard's change count when the token was pasted, so only that paste is cleared.
    @State private var pastedChangeCount: Int?
    @State private var isConfirmingDisconnect = false

    var body: some View {
        List {
            if isLinked { connected } else { notConnected }
        }
        .navigationTitle(Text(verbatim: "monobank"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var notConnected: some View {
        Group {
            Section {
                Text("Records your monobank card payments by itself. The token only reads; it can't move money.")
                Button("Open api.monobank.ua") { openURL(Monobank.baseURL) }
                    .buttonStyle(.bordered)
            } footer: {
                Text("Tap the QR code, confirm in monobank, copy the token and come back.")
            }
            Section {
                HStack {
                    SecureField("Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isChecking)
                        .accessibilityIdentifier("monobankToken")
                    PasteButton(payloadType: String.self) { strings in
                        pastedChangeCount = UIPasteboard.general.changeCount
                        token = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    }
                }
            } footer: {
                if isChecking {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Checking…")
                    }
                } else if let checkMessage {
                    Text(checkMessage)
                } else if !token.isEmpty && !Monobank.isTokenShaped(token) {
                    Text("This doesn't look like a monobank token.")
                }
            }
        }
        .onChange(of: token) { if Monobank.isTokenShaped(token) { Task { await verify(token) } } }
    }

    private var connected: some View {
        Group {
            Section {
                Text("Connected")
            } footer: {
                statusLine
            }
            Section {
                Button("Disconnect", role: .destructive) { isConfirmingDisconnect = true }
                Link("Manage tokens at api.monobank.ua", destination: Monobank.baseURL)
            }
            .confirmationDialog("Disconnect monobank?", isPresented: $isConfirmingDisconnect, titleVisibility: .visible)
            {
                Button("Disconnect", role: .destructive) {
                    MonobankSync.disconnect()
                    isLinked = false
                }
            } message: {
                Text("Recorded expenses stay. To revoke the token itself, open api.monobank.ua.")
            }
        }
    }

    /// The outcome of the last sync.
    @ViewBuilder private var statusLine: some View {
        let state = stateData.flatMap { try? JSONDecoder().decode(MonobankSync.State.self, from: $0) }
        switch state?.problem {
        case .rateLimited: Text("monobank asked to wait. Retrying in a minute.")
        case .offline: Text("No connection. Will update when online.")
        case .rejected:
            Text("monobank no longer accepts the token. Disconnect and connect again.").foregroundStyle(.orange)
        case .notHryvnia: Text("Your main monobank account isn't in hryvnias, so Kalyta can't record from it.")
        case .failed: Text("Couldn't update. Will try again later.")
        case nil:
            if let date = state?.lastSuccess { Text("Updated \(date, format: .relative(presentation: .named))") }
        }
    }

    /// Checks the token once with `client-info`; on success stores it and runs the first sync.
    ///
    /// - Parameter candidate: A token of the right shape.
    private func verify(_ candidate: String) async {
        isChecking = true
        checkMessage = nil
        defer { isChecking = false }
        do {
            let status = try await MonobankSync.connect(
                token: candidate, transport: MonobankSync.transport, context: Store.container.mainContext,
                defaults: .standard)
            switch status {
            case 200:
                // Only the paste this screen made is cleared, and only if nothing was copied since.
                if pastedChangeCount == UIPasteboard.general.changeCount { UIPasteboard.general.items = [] }
                token = ""
                isLinked = true
                MonobankSync.scheduleRefresh()
            case 401, 403:
                checkMessage = "monobank didn't accept this token. Copy it again."
            case 429:
                checkMessage = "monobank asked to wait. Retrying in a minute."
                isChecking = false
                try? await Task.sleep(for: .seconds(MonobankSync.throttle))
                if token == candidate { await verify(candidate) }
            default:
                throw MonobankError.status(status)
            }
        } catch MonobankError.offline {
            checkMessage = "No connection. Will update when online."
        } catch {
            checkMessage = "Couldn't update. Will try again later."
        }
    }
}

/// The Settings row that opens ``MonobankView``, with the connection state on the right.
struct MonobankSettingsRow: View {
    @AppStorage(MonobankSync.linkedKey) private var isLinked = false
    @AppStorage(MonobankSync.stateKey) private var stateData: Data?

    var body: some View {
        NavigationLink {
            MonobankView()
        } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    let state = stateData.flatMap { try? JSONDecoder().decode(MonobankSync.State.self, from: $0) }
                    if isLinked && state?.problem != nil {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                            .accessibilityLabel("Needs attention")
                    }
                    if isLinked { Text("Connected") } else { Text("Off") }
                }
            } label: {
                Label {
                    Text(verbatim: "monobank")
                } icon: {
                    Image(systemName: "building.columns")
                }
            }
        }
    }
}
