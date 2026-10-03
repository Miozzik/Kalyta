import SwiftUI

/// The Settings tab: categories, the bank, and the backup.
struct SettingsView: View {
    /// When a backup was last saved, as seconds since 1970; 0 means never.
    @AppStorage(BackupView.lastExportKey) private var lastExport: Double = 0

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Categories", systemImage: "square.grid.2x2")
                }
                Section("Bank") {
                    MonobankSettingsRow()
                    NavigationLink {
                        AutopaySetupView()
                    } label: {
                        Label("Set Up Automatic Recording", systemImage: "wave.3.right")
                    }
                }
                NavigationLink {
                    BackupView()
                } label: {
                    Label {
                        Text("Backup")
                        if lastExport > 0 {
                            let date = Date(timeIntervalSince1970: lastExport)
                            Text("Last export: \(date.formatted(date: .abbreviated, time: .shortened))")
                        } else {
                            Text("Not exported yet")
                        }
                    } icon: {
                        Image(systemName: "externaldrive")
                    }
                }
                // The subtitle joins the row's label, so tests find the row by this identifier.
                .accessibilityIdentifier("Backup")
                AboutSection()
            }
            .navigationTitle("Settings")
        }
    }
}
