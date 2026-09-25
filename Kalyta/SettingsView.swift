import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The Settings tab: categories and restoring a backup.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var isPickingFile = false
    /// The import waiting for the person's confirmation, or `nil` when none is.
    @State private var pendingImport: ImportPlan?
    /// The message of the last finished or refused import, or `nil` when none is shown.
    @State private var importMessage: String?
    @State private var isImporting = false

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
                }
                Section {
                    Button {
                        isPickingFile = true
                    } label: {
                        Label("Import from CSV", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isImporting)
                } footer: {
                    Text(
                        "Restores a Kalyta export. Expenses already here are skipped, so importing the same file twice adds nothing."
                    )
                }
                AboutSection()
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.commaSeparatedText]) { result in
                if case .success(let url) = result { Task { await prepareImport(from: url) } }
            }
            .alert(
                "Import from CSV",
                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                presenting: pendingImport
            ) { plan in
                Button("Import") { Task { await runImport(plan) } }
                    .disabled(plan.toInsert.isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                Text(summary(of: plan))
            }
            .alert(
                "Import from CSV",
                isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } }),
                presenting: importMessage
            ) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
        }
    }

    /// Reads the picked file and plans the import, without writing anything.
    ///
    /// - Parameter url: The security-scoped URL the file importer returned.
    private func prepareImport(from url: URL) async {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try ExpenseImport.readText(from: url)
            let existing = try context.fetch(FetchDescriptor<Expense>()).map(ExpenseRecord.init)
            let kinds = Dictionary(
                try context.fetch(FetchDescriptor<ExpenseCategory>()).map { ($0.key, $0.isIncome) },
                uniquingKeysWith: { first, _ in first })
            // Parsing is pure and can take a while on a large file, so it runs off the main actor.
            pendingImport = try await Task.detached {
                try ExpenseImport.plan(csv: text, existing: existing, categoryKinds: kinds)
            }.value
        } catch {
            importMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Writes the confirmed plan on a background context and reports the result.
    ///
    /// - Parameter plan: The plan shown in the preview.
    private func runImport(_ plan: ImportPlan) async {
        isImporting = true
        defer { isImporting = false }
        do {
            try await ImportWriter(modelContainer: Store.container).apply(plan)
            importMessage = String(localized: "Imported \(plan.toInsert.count) expenses.")
        } catch {
            importMessage = error.localizedDescription
        }
    }

    /// Returns the preview text: what will be added, what is skipped, and why.
    ///
    /// - Parameter plan: The planned import.
    /// - Returns: One line per figure, with the first few broken lines listed.
    private func summary(of plan: ImportPlan) -> String {
        var lines = [
            String(localized: "\(plan.toInsert.count) new expenses will be added."),
            String(localized: "\(plan.duplicateCount) already here, skipped."),
        ]
        if !plan.invalidLines.isEmpty {
            let shown = plan.invalidLines.prefix(5).map(String.init).joined(separator: ", ")
            let more = plan.invalidLines.count > 5 ? "…" : ""
            lines.append(
                String(localized: "\(plan.invalidLines.count) rows could not be read (lines \(shown)\(more))."))
        }
        return lines.joined(separator: "\n")
    }
}
