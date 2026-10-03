import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Backup: the full JSON backup, the CSV export for spreadsheets, and restoring either.
struct BackupView: View {
    /// The `UserDefaults` key of the last saved backup's time; ``resetData()`` removes it.
    static let lastExportKey = "lastBackupExport"

    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var entries: [Expense]
    /// When a backup was last saved, as seconds since 1970; 0 means never.
    @AppStorage(lastExportKey) private var lastExport: Double = 0
    /// The backup being saved, taken when the person tapped Export Backup.
    @State private var backup: Backup?
    @State private var isExporting = false
    @State private var isPickingFile = false
    /// The CSV import waiting for the person's confirmation, or `nil` when none is.
    @State private var pendingImport: ImportPlan?
    /// The backup restore waiting for the person's confirmation, or `nil` when none is.
    @State private var pendingRestore: BackupPlan?
    /// The message of the last finished or refused import, or `nil` when none is shown.
    @State private var importMessage: String?
    @State private var isImporting = false

    var body: some View {
        List {
            Section {
                Button {
                    do {
                        backup = try Backup.snapshot(of: context)
                        isExporting = true
                    } catch {
                        importMessage = error.localizedDescription
                    }
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("A plain, unencrypted file. Store it somewhere you trust.")
            }
            Section {
                // One snapshot feeds both the file and the title, so the count shown is what is exported.
                let export = ExpenseExport(records: entries.map(ExpenseRecord.init), createdAt: .now)
                ShareLink(item: export, preview: SharePreview(String(localized: "\(export.records.count) entries"))) {
                    Label("Export for Spreadsheets (CSV)", systemImage: "tablecells")
                }
            } footer: {
                Text("For Excel/Numbers, not for restoring")
            }
            Section {
                Button {
                    isPickingFile = true
                } label: {
                    Label("Import Backup", systemImage: "square.and.arrow.down")
                }
                .disabled(isImporting)
            } footer: {
                Text(
                    "Restores a Kalyta export. Expenses already here are skipped, so importing the same file twice adds nothing."
                )
            }
        }
        .navigationTitle("Backup")
        .fileExporter(
            isPresented: $isExporting, item: backup, contentTypes: [.json],
            defaultFilename: Backup.fileName(for: backup?.exportedAt ?? .now)
        ) { result in
            // Only a file actually saved counts; Cancel calls `onCancellation` instead.
            switch result {
            case .success: lastExport = (backup?.exportedAt ?? .now).timeIntervalSince1970
            case .failure(let error): importMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.json, .commaSeparatedText]) { result in
            if case .success(let url) = result { Task { await prepareImport(from: url) } }
        }
        .alert(
            "Import Backup",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { plan in
            Button("Import") { Task { await runRestore(plan) } }
                .disabled(plan.isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { plan in
            Text(summary(of: plan))
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
            "Backup",
            isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } }),
            presenting: importMessage
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    /// Reads the picked file and plans the import, without writing anything.
    ///
    /// A `.json` file is a full backup; anything else goes the CSV way.
    ///
    /// - Parameter url: The security-scoped URL the file importer returned.
    private func prepareImport(from url: URL) async {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try ExpenseImport.readText(from: url)
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .json) == true {
                let local = try BackupLocal(context)
                // Decoding and planning are pure and can take a while on a large file.
                pendingRestore = try await Task.detached {
                    try BackupRestore.plan(Backup.decode(text), local: local)
                }.value
                return
            }
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

    /// Writes the confirmed restore on a background context, then reschedules the reminders.
    ///
    /// - Parameter plan: The plan shown in the preview.
    private func runRestore(_ plan: BackupPlan) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let added = try await BackupWriter(modelContainer: Store.container).apply(plan)
            await SubscriptionReminders.reschedule(from: context)
            importMessage = String(
                localized:
                    "Restored — entries: \(added.expenses), categories: \(added.categories), subscriptions: \(added.subscriptions)."
            )
        } catch {
            importMessage = error.localizedDescription
        }
    }

    /// Returns the restore preview: one line per type, then what cannot be read or will change.
    ///
    /// - Parameter plan: The planned restore.
    private func summary(of plan: BackupPlan) -> String {
        var lines = [
            String(localized: "Entries: \(plan.entries.count) new, \(plan.knownEntries) already here"),
            String(
                localized: "Categories: \(plan.categories.count) new, \(plan.knownCategories) kept as on this phone"),
            String(
                localized: "Subscriptions: \(plan.subscriptions.count) new, \(plan.knownSubscriptions) already here"),
        ]
        if plan.invalidCount > 0 { lines.append(String(localized: "\(plan.invalidCount) items could not be read")) }
        if !plan.builtInUpdates.isEmpty {
            lines.append(
                String(
                    localized: "\(plan.builtInUpdates.count) built-in categories will take the backup's names and order"
                ))
        }
        return lines.joined(separator: "\n")
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
