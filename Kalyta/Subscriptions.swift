import Foundation
import ImageIO
import SwiftData
import UIKit
import UserNotifications

/// How often a subscription is charged.
enum BillingPeriod: String, Codable, CaseIterable, Identifiable {
    case monthly, yearly

    var id: Self { self }

    /// The localized name shown in the editor.
    var title: String {
        switch self {
        case .monthly: String(localized: "Monthly")
        case .yearly: String(localized: "Yearly")
        }
    }

    /// The number of months between charges.
    var months: Int { self == .monthly ? 1 : 12 }
}

/// Date arithmetic and naming rules for subscriptions, as pure functions.
enum SubscriptionMath {
    /// Returns the date of the charge at `index`, counted from the first charge.
    ///
    /// Always computed from the first charge: adding a month to the previous charge
    /// drifts (31 Jan → 28 Feb → 28 Mar), while adding n months to 31 Jan gives
    /// 28 Feb, then 31 Mar.
    ///
    /// - Parameters:
    ///   - firstCharge: The first charge.
    ///   - period: How often it is charged.
    ///   - index: 0 for the first charge, 1 for the next, and so on.
    ///   - calendar: The calendar that defines months.
    /// - Returns: The charge date.
    static func chargeDate(
        firstCharge: Date, period: BillingPeriod, index: Int, calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .month, value: index * period.months, to: firstCharge) ?? firstCharge
    }

    /// Returns the first charge on or after the start of the day containing `now`.
    ///
    /// - Parameters:
    ///   - firstCharge: The first charge.
    ///   - period: How often it is charged.
    ///   - now: The current moment.
    ///   - calendar: The calendar that defines days and months.
    /// - Returns: The next charge; the first charge itself if it is still ahead.
    static func nextCharge(
        firstCharge: Date, period: BillingPeriod, now: Date = .now, calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        let monthsSince = max(calendar.dateComponents([.month], from: firstCharge, to: today).month ?? 0, 0)
        var index = monthsSince / period.months
        while chargeDate(firstCharge: firstCharge, period: period, index: index, calendar: calendar) < today {
            index += 1
        }
        return chargeDate(firstCharge: firstCharge, period: period, index: index, calendar: calendar)
    }

    /// Returns the latest charge on or before `now`, the one a "record this charge" tap records.
    ///
    /// - Returns: The last charge that already happened, or `nil` before the first one.
    static func lastCharge(
        firstCharge: Date, period: BillingPeriod, now: Date = .now, calendar: Calendar = .current
    ) -> Date? {
        guard firstCharge <= now else { return nil }
        var index = max(calendar.dateComponents([.month], from: firstCharge, to: now).month ?? 0, 0) / period.months
        while index > 0, chargeDate(firstCharge: firstCharge, period: period, index: index, calendar: calendar) > now {
            index -= 1
        }
        return chargeDate(firstCharge: firstCharge, period: period, index: index, calendar: calendar)
    }

    /// Returns when a charge is due, by day: "Today", "Tomorrow", or the day and month.
    ///
    /// A relative format would count down to the stored time of day ("in 5 seconds").
    ///
    /// - Parameters:
    ///   - charge: The charge date.
    ///   - now: The current moment.
    ///   - calendar: The calendar that defines days.
    /// - Returns: The localized text for the list row.
    static func dueText(for charge: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(charge, inSameDayAs: now) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
            calendar.isDate(charge, inSameDayAs: tomorrow)
        {
            return String(localized: "Tomorrow")
        }
        var style = Date.FormatStyle.dateTime.day().month()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return charge.formatted(style)
    }

    /// Returns whether a charge is already among the recorded expenses.
    ///
    /// Uses the import's duplicate key (whole second, kopiykas, category, note), so a
    /// second tap on Record does not count the same charge twice.
    ///
    /// - Parameters:
    ///   - charge: The charge about to be recorded.
    ///   - existing: Expenses that may already hold it.
    /// - Returns: `true` if one of them is the same charge.
    static func isAlreadyRecorded(_ charge: ExpenseRecord, among existing: [ExpenseRecord]) -> Bool {
        let key = ExpenseImport.DuplicateKey(charge)
        return existing.contains { ExpenseImport.DuplicateKey($0) == key }
    }

    /// Returns what the subscriptions cost per month, a yearly plan counting as a twelfth.
    static func monthlyCost(of subscriptions: [(amount: Double, period: BillingPeriod)]) -> Double {
        subscriptions.reduce(0) { $0 + $1.amount / Double($1.period.months) }
    }

    /// Returns the icon file name for a service, such as "youtube-music" for "YouTube Music".
    ///
    /// The icon repository names files in lowercase ASCII with hyphens. A name that is not
    /// Latin after folding (a Ukrainian service, say) has no icon there, so no request is made.
    ///
    /// - Parameter name: The service name as the person typed it.
    /// - Returns: The slug, or `nil` if the name cannot match an icon.
    static func iconSlug(for name: String) -> String? {
        let folded = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
        let words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let slug = words.joined(separator: "-")
        guard !slug.isEmpty,
            slug.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" })
        else { return nil }
        return slug
    }

    /// Returns the letter-avatar colour for a name, the same on every launch.
    ///
    /// Uses the sum of the name's Unicode scalars, not `hashValue`: Swift seeds hashing
    /// randomly per process, so a hash would give a new colour every launch.
    static func avatarColor(for name: String) -> CategoryColor {
        let sum = name.lowercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return CategoryColor.allCases[sum % CategoryColor.allCases.count]
    }
}

/// Downloads service icons from the icon repository configured in the build settings.
enum SubscriptionIcons {
    /// The largest icon accepted; the repository's PNGs are around 10–40 KB.
    static let maximumIconSize = 512 * 1024
    /// The largest width or height accepted, in pixels; the repository's PNGs are 512 px.
    static let maximumIconPixels = 1_024

    /// A session of its own: nothing cached on disk, no redirect off the icon host, and a
    /// User-Agent that names no device, OS or app version.
    private static let session: URLSession? = baseURL.map { base in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": "Kalyta"]
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration, delegate: SameHostRedirects(to: base), delegateQueue: nil)
    }

    /// The repository's PNG folder, from `ICON_BASE_URL` in `Config/Kalyta.xcconfig`.
    static var baseURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "KalytaIconBaseURL") as? String).flatMap(URL.init(string:))
    }

    /// The outcome of looking up an icon.
    enum FetchResult: Equatable {
        /// The repository has the icon.
        case found(Data)
        /// The repository has no icon by that name; no point asking again.
        case missing
        /// The request did not get an answer (offline, timeout, server error); ask again later.
        case failed

        /// Whether the slug is settled and should not be requested again until a rename.
        var isFinal: Bool {
            if case .failed = self { return false }
            return true
        }
    }

    /// Classifies a response, so an offline attempt is never mistaken for a missing icon.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status, or `nil` when the request failed before a response.
    ///   - mimeType: The response's MIME type.
    ///   - data: The response body.
    /// - Returns: ``FetchResult/found(_:)`` only for a valid image within the byte and pixel caps;
    ///   ``FetchResult/failed`` for no response, 429 or a server error; otherwise
    ///   ``FetchResult/missing``.
    static func classify(statusCode: Int?, mimeType: String?, data: Data?) -> FetchResult {
        guard let statusCode else { return .failed }
        if statusCode == 429 || statusCode >= 500 { return .failed }
        guard statusCode == 200, mimeType?.hasPrefix("image/") == true, let data, data.count <= maximumIconSize,
            let (width, height) = pixelSize(of: data), max(width, height) <= maximumIconPixels,
            UIImage(data: data) != nil
        else { return .missing }
        return .found(data)
    }

    /// Reads an image's pixel size from its header, without decoding the pixels.
    ///
    /// - Parameter data: The image file.
    /// - Returns: The width and height, or `nil` if the data is not an image.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    /// Looks up the icon for a slug.
    ///
    /// The request tells the server which service this is; the README says so.
    ///
    /// - Parameter slug: The icon name from ``SubscriptionMath/iconSlug(for:)``.
    /// - Returns: The classified result of the request.
    static func fetchIcon(slug: String) async -> FetchResult {
        guard let url = baseURL?.appending(path: "\(slug).png") else { return .failed }
        guard let session, let (data, response) = try? await session.data(from: url) else { return .failed }
        let http = response as? HTTPURLResponse
        return classify(statusCode: http?.statusCode, mimeType: http?.mimeType, data: data)
    }
}

extension SubscriptionIcons {
    /// Downloads and stores the icon for a subscription whose name has a new slug.
    ///
    /// The slug is remembered only when the answer is final (found or missing), so an
    /// attempt made offline is retried on the next save or return to the app, while a
    /// found or missing icon is never requested again until a rename.
    ///
    /// - Parameters:
    ///   - subscription: The subscription to update.
    ///   - context: The context to save it in.
    @MainActor
    static func refreshIcon(for subscription: Subscription, in context: ModelContext) async {
        let slug = SubscriptionMath.iconSlug(for: subscription.name)
        guard slug != subscription.iconSlugTried || (slug == nil && subscription.iconData != nil) else { return }
        guard let slug else {
            subscription.iconSlugTried = nil
            subscription.iconData = nil
            try? context.save()
            return
        }
        let result = await fetchIcon(slug: slug)
        guard result.isFinal else { return }
        subscription.iconSlugTried = slug
        if case .found(let data) = result { subscription.iconData = data } else { subscription.iconData = nil }
        try? context.save()
    }

    /// Retries the icon of every subscription whose last attempt got no answer.
    ///
    /// - Parameter context: The context to read and save the subscriptions in.
    @MainActor
    static func retryUnsettled(in context: ModelContext) async {
        let pending = ((try? context.fetch(FetchDescriptor<Subscription>())) ?? []).filter {
            let slug = SubscriptionMath.iconSlug(for: $0.name)
            return slug != nil && slug != $0.iconSlugTried
        }
        for subscription in pending { await refreshIcon(for: subscription, in: context) }
    }
}

/// Schedules the day-before reminders for subscriptions.
enum SubscriptionReminders {
    /// The hour of the day a reminder arrives, the day before the charge.
    static let reminderHour = 10

    /// Asks for permission to notify; called when the first subscription is created.
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Reschedules the reminders for every stored subscription.
    ///
    /// - Parameter context: The context to read the subscriptions from.
    @MainActor
    static func reschedule(from context: ModelContext) async {
        let items = ((try? context.fetch(FetchDescriptor<Subscription>())) ?? []).map {
            (
                key: $0.key, name: $0.name, amount: $0.amount,
                nextCharge: SubscriptionMath.nextCharge(firstCharge: $0.firstChargeDate, period: $0.period)
            )
        }
        await reschedule(items)
    }

    /// Replaces every pending reminder with one for each subscription's next charge.
    ///
    /// iOS keeps at most 64 pending local notifications per app, so only the next charge
    /// of each subscription is scheduled; this runs again at every launch and return to
    /// the foreground. A subscription not opened for a whole cycle can miss a reminder.
    ///
    /// - Parameter subscriptions: The key, name, amount and next charge of each subscription.
    static func reschedule(_ subscriptions: [(key: String, name: String, amount: Double, nextCharge: Date)]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let calendar = Calendar.current
        for item in subscriptions {
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: item.nextCharge) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: dayBefore)
            components.hour = reminderHour
            guard let fireDate = calendar.date(from: components), fireDate > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.name
            content.body = String(localized: "Tomorrow: \(formattedHryvnias(item.amount))")
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.key, content: content, trigger: trigger))
        }
    }
}
