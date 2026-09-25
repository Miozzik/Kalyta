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

/// A Home Screen and Lock Screen widget that opens the receipt scanner.
///
/// It shows no data, so its timeline holds one entry that never changes.
struct ScanReceiptWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScanReceipt", provider: Provider()) { _ in
            ScanReceiptWidgetView()
        }
        .configurationDisplayName("Scan Receipt")
        .description("Quick receipt scan.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }

    /// Supplies the single, unchanging entry.
    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }

        func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
            completion(SimpleEntry(date: .now))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
            completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
        }
    }

    /// The only entry: the widget shows nothing that changes over time.
    struct SimpleEntry: TimelineEntry {
        let date: Date
    }
}

/// The widget's face: the scan symbol, with its title where there is room.
///
/// Tapping anywhere opens the app through ``ScanRequest/url``; the widget reads no data.
private struct ScanReceiptWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Scan Receipt")
                .accessibilityHint("Scan a receipt")
                .containerBackground(for: .widget) {}
            case .accessoryRectangular:
                // Stage 14 adds today's total under the title in both layouts below.
                VStack(alignment: .leading) {
                    Label("Scan Receipt", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .accessibilityHint("Scan a receipt")
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
