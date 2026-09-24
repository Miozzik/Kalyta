import SwiftData
import SwiftUI

/// The app entry point.
///
/// Two launch arguments exist for development:
/// - `--selfcheck` runs ``runSelfCheck()`` and exits.
/// - `--demo` replaces all expenses with sample data for screenshots.
/// - `--measure-import` times planning and inserting 10,000 imported rows, then exits.
/// - `--check-upgrade` verifies that sample data written by an older release survived
///   the upgrade to this one, then exits.
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
            // Only the next charge of each subscription is scheduled, so refresh on every return.
            .onChange(of: scenePhase, initial: true) {
                if scenePhase == .active {
                    Task {
                        await SubscriptionReminders.reschedule(from: Store.container.mainContext)
                        // An icon lookup that got no answer (offline) is retried on every return.
                        await SubscriptionIcons.retryUnsettled(in: Store.container.mainContext)
                    }
                }
            }
        }
        .modelContainer(Store.container)
    }
}
