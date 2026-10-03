import SwiftUI

/// The pages Settings links to, from `PRIVACY_POLICY_URL` and `SUPPORT_URL` in `Config/Kalyta.xcconfig`.
enum AppLinks {
    /// The privacy policy, or `nil` if the build has none configured.
    static var privacyPolicy: URL? { url(forInfoDictionaryKey: "KalytaPrivacyPolicyURL") }
    /// The support page, or `nil` if the build has none configured.
    static var support: URL? { url(forInfoDictionaryKey: "KalytaSupportURL") }

    private static func url(forInfoDictionaryKey key: String) -> URL? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap(URL.init(string:))
    }
}

/// The About section of Settings: the privacy policy, support and acknowledgements.
struct AboutSection: View {
    var body: some View {
        Section("About") {
            if let url = AppLinks.privacyPolicy {
                Link(destination: url) { Label("Privacy Policy", systemImage: "hand.raised") }
            }
            if let url = AppLinks.support {
                Link(destination: url) { Label("Support", systemImage: "questionmark.circle") }
            }
            NavigationLink {
                AcknowledgementsView()
            } label: {
                Label("Acknowledgements", systemImage: "doc.text")
            }
        }
    }
}

/// The licences of what Kalyta uses, and its own.
private struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section("Icons") {
                Text("Service icons come from homarr-labs/dashboard-icons under the Apache License 2.0.")
                Text("Logos are trademarks of their respective owners.")
            }
            Section("License") {
                Text("Kalyta is open source under the MIT License.")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
