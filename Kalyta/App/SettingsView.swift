import SwiftUI

/// The Settings tab: categories, automation, and the backup.
struct SettingsView: View {
    /// When a backup was last saved, as seconds since 1970; 0 means never.
    @AppStorage(BackupView.lastExportKey) private var lastExport: Double = 0
    /// How many of the automation rows are set up; `nil` until read.
    @State private var automationCount: Int?

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Categories", systemImage: "square.grid.2x2")
                }
                NavigationLink {
                    AutomationView()
                } label: {
                    Label {
                        Text("Automation")
                        if let automationCount {
                            Text("\(automationCount) of \(AutomationRow.detectable.count) set up")
                        }
                    } icon: {
                        Image(systemName: "bolt")
                    }
                }
                // The subtitle joins the row's label, so tests find the row by this identifier.
                .accessibilityIdentifier("Automation")
                // Runs again on every return to Settings, so a change made inside shows at once.
                .task {
                    automationCount = await AutomationInputs.current().setUpCount
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
