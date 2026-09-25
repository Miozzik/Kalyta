import AppIntents
import SwiftData
import SwiftUI
import UIKit

/// The app entry point.
///
/// Launch arguments for development:
/// - `--selfcheck` runs ``runSelfCheck()`` and exits.
/// - `--demo` replaces all expenses with sample data for screenshots.
/// - `--measure-import` times planning and inserting 10,000 imported rows, then exits.
/// - `--check-upgrade` verifies that sample data written by an older release survived
///   the upgrade to this one, then exits.
/// - `-scanPayload <text>` (debug builds) makes Scan Receipt read `<text>` instead of the camera;
///   `"A|B"` gives A on the first tap, B on the second, and so on.
@main
struct KalytaApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if CommandLine.arguments.contains("--selfcheck") { MainActor.assumeIsolated { runSelfCheck() } }
        if CommandLine.arguments.contains("--demo") { MainActor.assumeIsolated { seedDemoData() } }
        if CommandLine.arguments.contains("--check-upgrade") { MainActor.assumeIsolated { runUpgradeCheck() } }
        if CommandLine.arguments.contains("--measure-import") { MainActor.assumeIsolated { measureImport() } }
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("Expenses", systemImage: "list.bullet.rectangle") }
                StatisticsView()
                    .tabItem { Label("Statistics", systemImage: "chart.bar") }
                SubscriptionsView()
                    .tabItem { Label("Subscriptions", systemImage: "repeat.circle") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .task { try? Store.ensureCategories(in: Store.container.mainContext) }
            .modifier(ScanRequestSheet())
            // Only the next charge of each subscription is scheduled, so refresh on every return.
            .onChange(of: scenePhase, initial: true) {
                if scenePhase == .active {
                    Task {
                        await SubscriptionReminders.reschedule(from: Store.container.mainContext)
                        // An icon lookup that got no answer (offline) is retried on every return.
                        await SubscriptionIcons.retryUnsettled(in: Store.container.mainContext)
                        MonobankSync.removeOrphanedToken()
                        await MonobankSync.runIfLinked()
                    }
                }
            }
        }
        .modelContainer(Store.container)
        .backgroundTask(.appRefresh(MonobankSync.refreshTaskID)) { await MonobankSync.runIfLinked() }
    }
}

/// Opens the entry sheet with the scanner when a shortcut, widget or control asks for it.
///
/// Shown over whichever tab is open, so the request needs no tab switching. A view, not the
/// scene, observes the request, so the sheet follows it.
private struct ScanRequestSheet: ViewModifier {
    private let request = ScanRequest.shared
    @State private var isScanning = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isScanning) { ExpenseEditor(startsScanning: true) }
            // Only the widget's own link counts; any other URL, or the same one with a query, does nothing.
            .onOpenURL { url in
                if url == ScanRequest.url { request.isPending = true }
            }
            .onChange(of: request.isPending, initial: true) {
                guard request.isPending else { return }
                request.isPending = false
                // A sheet already open may hold unsaved input, so the request is dropped, not queued.
                if !isPresentingSheet { isScanning = true }
            }
    }

    /// Whether any sheet, this one included, is on screen.
    private var isPresentingSheet: Bool {
        UIApplication.shared.connectedScenes.contains {
            ($0 as? UIWindowScene)?.keyWindow?.rootViewController?.presentedViewController != nil
        }
    }
}

/// The App Shortcuts Kalyta offers without any setup in the Shortcuts app.
struct KalytaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanReceiptIntent(), phrases: ["Scan a receipt in \(.applicationName)"],
            shortTitle: "Scan Receipt", systemImageName: "qrcode.viewfinder")
    }
}
