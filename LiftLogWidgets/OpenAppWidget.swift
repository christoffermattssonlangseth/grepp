import SwiftUI
import WidgetKit

/// Just the barbell on the lock screen: a shortcut into the app, nothing to
/// read. For when the Last session widget says more than you want there.
struct OpenAppWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenApp", provider: OpenAppProvider()) { _ in
            // Sized to the circle, not in points: the circle is 68–76pt
            // depending on the phone. At 0.36 of it the outer plates stay
            // clear of the rim; a fixed 15pt left half the circle empty.
            GeometryReader { geo in
                Barbell(height: min(geo.size.width, geo.size.height) * 0.36, color: .primary)
                    .widgetAccentable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
                .accessibilityLabel("Open Grepp")
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(WidgetSnapshot.logURL)
        }
        .configurationDisplayName("Open Grepp")
        .description("The app, one tap from the lock screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// Nothing changes, so one entry that never asks to be refreshed.
struct OpenAppProvider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }

    func placeholder(in context: Context) -> Entry { Entry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date())], policy: .never))
    }
}
