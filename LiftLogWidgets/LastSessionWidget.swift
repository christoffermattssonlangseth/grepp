import SwiftUI
import WidgetKit

/// "Last session: Thursday · squat 87.5x5" on the home screen. A tap opens the app.
///
/// Reads the snapshot the app leaves in the App Group; never the log itself.
/// The timeline re-renders at each local midnight so "2 days ago" stays true
/// without the app being opened.
struct LastSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: LastSessionProvider()) { entry in
            LastSessionView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Brand.accent.opacity(0.28),
                                            Color(.systemBackground),
                                            Brand.accent.opacity(0.14)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Last session")
        .description("What you lifted last time, and how long ago.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LastSessionEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct LastSessionProvider: TimelineProvider {
    func placeholder(in context: Context) -> LastSessionEntry {
        LastSessionEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (LastSessionEntry) -> Void) {
        completion(LastSessionEntry(date: Date(),
                                    snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LastSessionEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let calendar = Calendar.current
        var entries = [LastSessionEntry(date: Date(), snapshot: snapshot)]
        // One entry per upcoming midnight, so the "days ago" line ticks over.
        var day = calendar.startOfDay(for: Date())
        for _ in 0..<3 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            entries.append(LastSessionEntry(date: next, snapshot: snapshot))
            day = next
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct LastSessionView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LastSessionEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.lines.isEmpty {
            session(snapshot)
        } else {
            empty
        }
    }

    // MARK: - Content

    private func session(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(relative(snapshot))
                .font(.title3.weight(.heavy))
                .fontWidth(.condensed)
                .lineLimit(1)
                .padding(.top, 4)
            Text(dayLabel(snapshot))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            lines(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Barbell(height: 11)
            Text("LAST SESSION")
                .font(.system(size: 10, weight: .heavy)).tracking(1.5)
                .foregroundStyle(.secondary)
        }
    }

    /// Small: the lifts and their last set. Medium: the lifts and every set.
    private func lines(_ snapshot: WidgetSnapshot) -> some View {
        let shown = Array(snapshot.lines.prefix(family == .systemSmall ? 3 : 4))
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(line.name.replacingOccurrences(of: "-", with: " "))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(family == .systemSmall ? lastSet(line) : line.sets)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            if snapshot.lines.count > shown.count {
                Text("+\(snapshot.lines.count - shown.count) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            Text("Nothing logged yet")
                .font(.headline)
                .fontWidth(.condensed)
            Text("Open LiftLog and land a set.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Words

    private func lastSet(_ line: WidgetSnapshot.Line) -> String {
        line.sets.split(separator: " ").last.map(String.init) ?? ""
    }

    private func daysAgo(_ snapshot: WidgetSnapshot) -> Int? {
        guard let day = snapshot.date else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: entry.date)).day
    }

    private func relative(_ snapshot: WidgetSnapshot) -> String {
        switch daysAgo(snapshot) {
        case .some(let n) where n <= 0: return "Today"
        case .some(1): return "Yesterday"
        case .some(let n): return "\(n) days ago"
        case .none: return snapshot.day
        }
    }

    private func dayLabel(_ snapshot: WidgetSnapshot) -> String {
        guard let day = snapshot.date else { return "" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}
