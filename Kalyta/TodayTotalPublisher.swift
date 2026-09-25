import Foundation
import SwiftData
import WidgetKit

/// The app's side of today's total: adding it up for the summary card and publishing it for the widget.
///
/// The app writes the total and the start of its day to the App Group's defaults after
/// every save of the shared store, however it happened (entry sheet, Shortcuts action,
/// bank sync, CSV import), and whenever it becomes active.
extension TodayTotal {
    /// Returns the spending of the day that contains `now`.
    ///
    /// - Parameters:
    ///   - entries: Entries of any days; income is left out.
    ///   - now: A moment of the day to add up.
    ///   - calendar: The calendar that defines the day.
    /// - Returns: The sum of the day's spending.
    /// - Complexity: O(*n*), where *n* is the number of entries.
    static func spending(of entries: [Expense], now: Date = .now, calendar: Calendar = .current) -> Double {
        let day = calendar.dateInterval(of: .day, for: now)!
        return entries.filter { !$0.isIncome && day.containsExcludingEnd($0.date) }.reduce(0) { $0 + $1.amount }
    }

    /// Writes today's spending from a context to `defaults` and asks the widget to reload.
    ///
    /// - Parameters:
    ///   - context: The context to read.
    ///   - defaults: Where the widget reads the total.
    ///   - now: The current time.
    ///   - calendar: The calendar that defines the day.
    static func publish(
        from context: ModelContext, to defaults: UserDefaults, now: Date = .now, calendar: Calendar = .current
    ) {
        let day = calendar.dateInterval(of: .day, for: now)!
        let start = day.start
        let end = day.end
        let entries =
            (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= start && $0.date < end })))
            ?? []
        defaults.set(spending(of: entries, now: now, calendar: calendar), forKey: totalKey)
        defaults.set(start, forKey: dayStartKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Publishes after every save of any context of `container`, including background ones such as the import.
    ///
    /// Registered when the shared container is created, so it also runs when a Shortcuts
    /// action launches the app in the background without any interface.
    ///
    /// - Parameter container: The shared container.
    /// - Returns: The observer token; the notification center keeps the observer without it.
    @discardableResult
    static func observeSaves(of container: ModelContainer) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { note in
            // Only skips needless work: publish always reads the shared store, so a save to another
            // container (the self-check's temporary stores) could not change the total anyway.
            guard (note.object as? ModelContext)?.container === container, let defaults = sharedDefaults else { return }
            MainActor.assumeIsolated { publish(from: container.mainContext, to: defaults) }
        }
    }
}
