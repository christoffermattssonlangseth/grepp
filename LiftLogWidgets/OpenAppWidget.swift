import SwiftUI
import WidgetKit

/// Just the barbell on the lock screen: a shortcut into the app, nothing to
/// read. For when the Last session widget says more than you want there.
struct OpenAppWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenApp", provider: OpenAppProvider()) { _ in
            Barbell(height: 15, color: .primary)
                .widgetAccentable()
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
