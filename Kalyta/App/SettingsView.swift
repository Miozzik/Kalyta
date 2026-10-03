import SwiftUI

/// The Settings tab: categories, the bank, and the backup.
struct SettingsView: View {

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
                    Label("Backup", systemImage: "externaldrive")
                }
                AboutSection()
            }
            .navigationTitle("Settings")
        }
    }
}
