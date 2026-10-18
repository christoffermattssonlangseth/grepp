import AppIntents
import SwiftUI
import WidgetKit

/// Just the barbell on the lock screen: a shortcut into the app, nothing to
/// read. For when the Last session widget says more than you want there.
///
/// One setting, picked by tapping the widget while editing the lock screen:
/// a ring around the circle, or none.
struct OpenAppWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OpenApp", intent: OpenAppConfiguration.self,
                               provider: OpenAppProvider()) { entry in
            OpenAppView(outline: entry.outline)
                .accessibilityLabel("Open Grepp")
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(WidgetSnapshot.logURL)
        }
        .configurationDisplayName("Open Grepp")
        .description("The app, one tap from the lock screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// What the lock-screen editor offers when the widget is tapped.
struct OpenAppConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Open Grepp"
    static var description = IntentDescription("The barbell, with or without a ring around it.")

    @Parameter(title: "Outline", default: true)
    var outline: Bool

    init() {}
}

struct OpenAppView: View {
    let outline: Bool

    var body: some View {
        // Sized to the circle, not in points: the circle is 68–76pt
        // depending on the phone. At 0.36 of it the outer plates stay
        // clear of the rim; a fixed 15pt left half the circle empty.
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                if outline {
                    // Inset by half the line so the whole stroke sits inside
                    // the circle iOS clips the widget to.
                    Circle()
                        .strokeBorder(.primary, lineWidth: max(2, side * 0.035))
                        .widgetAccentable()
                }
                // A touch smaller inside the ring, so the plates don't meet it.
                Barbell(height: side * (outline ? 0.31 : 0.36), color: .primary)
                    .widgetAccentable()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Nothing changes but the setting, so one entry that never asks to be refreshed.
struct OpenAppProvider: AppIntentTimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
        let outline: Bool
    }

    func placeholder(in context: Context) -> Entry { Entry(date: Date(), outline: true) }

    func snapshot(for configuration: OpenAppConfiguration, in context: Context) async -> Entry {
        Entry(date: Date(), outline: configuration.outline)
    }

    func timeline(for configuration: OpenAppConfiguration, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [Entry(date: Date(), outline: configuration.outline)], policy: .never)
    }
}
