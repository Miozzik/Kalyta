import AppIntents
import SwiftUI
import WidgetKit

/// The widgets and controls Kalyta offers.
@main
struct KalytaWidgets: WidgetBundle {
    var body: some Widget {
        ScanReceiptWidget()
        if #available(iOS 18, *) { ScanReceiptControl() }
    }
}

/// A Home Screen and Lock Screen widget that opens the receipt scanner and shows today's spending.
///
/// The app publishes the total after every save; the widget reads it and drops to 0 at midnight.
struct ScanReceiptWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodayTotal.widgetKind, provider: Provider()) { entry in
            ScanReceiptWidgetView(total: entry.total)
        }
        .configurationDisplayName("Scan Receipt")
        .description("Quick receipt scan.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }

    /// Supplies today's published total now and 0 from midnight; the app reloads it after each save.
    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now, total: 0) }

        func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
            completion(SimpleEntry(date: .now, total: storedTotal()))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
            let entries = TodayTotal.timeline(total: storedTotal()).map { SimpleEntry(date: $0.date, total: $0.total) }
            completion(Timeline(entries: entries, policy: .atEnd))
        }

        private func storedTotal() -> Double {
            TodayTotal.sharedDefaults.map { TodayTotal.storedTotal(in: $0) } ?? 0
        }
    }

    /// Today's spending at a moment of the timeline.
    struct SimpleEntry: TimelineEntry {
        let date: Date
        /// Today's spending in hryvnias.
        let total: Double
    }
}

/// The widget's face: the scan symbol and today's spending, with the title where there is room.
///
/// Tapping anywhere opens the app through ``ScanRequest/url``. Only the amount is marked
/// private, so a locked iPhone still shows what the widget is.
private struct ScanReceiptWidgetView: View {
    @Environment(\.widgetFamily) private var family
    /// Today's spending in hryvnias.
    let total: Double

    /// The amount, hidden while the iPhone is locked.
    private var amount: some View {
        Text(formattedHryvnias(total)).privacySensitive()
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.body)
                            .accessibilityLabel("Scan Receipt")
                        amount
                            .font(.caption2)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    .padding(4)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Scan a receipt")
                .containerBackground(for: .widget) {}
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Label("Scan Receipt", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .accessibilityHint("Scan a receipt")
                    HStack(spacing: 4) {
                        Text("Today")
                        amount
                    }
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerBackground(for: .widget) {}
            default:
                VStack(alignment: .leading) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 40))
                        .accessibilityHidden(true)
                    Spacer()
                    Text("Scan Receipt")
                        .font(.headline)
                        .accessibilityHint("Scan a receipt")
                    HStack(spacing: 4) {
                        Text("Today")
                        amount
                    }
                    .font(.subheadline)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityElement(children: .combine)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .containerBackground(.summaryGradient, for: .widget)
            }
        }
        .widgetURL(ScanRequest.url)
    }
}

/// A Control Center, Lock Screen and Action button control that opens the receipt scanner.
///
/// The intent opens the app itself, so the control needs no link.
@available(iOS 18, *)
struct ScanReceiptControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ScanReceiptControl") {
            ControlWidgetButton(action: ScanReceiptIntent()) {
                Label("Scan Receipt", systemImage: "qrcode.viewfinder")
                    .controlWidgetActionHint("Scan a receipt")
            }
            .tint(.teal)
        }
        .displayName("Scan Receipt")
        .description("Quick receipt scan.")
    }
}
