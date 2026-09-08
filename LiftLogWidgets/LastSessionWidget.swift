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
        .description("What you lifted last time, and what's loaded to lift next.")
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
        if let snapshot = entry.snapshot, !snapshot.lines.isEmpty || !snapshot.upNext.isEmpty {
            content(snapshot)
        } else {
            empty
        }
    }

    // MARK: - Content

    /// Small: the plan when there is one, else the last session — the plan is
    /// the thing you'd glance at on the way to the gym. Medium: both, side by side.
    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        if family == .systemSmall {
            if !snapshot.upNext.isEmpty { upNext(snapshot) } else { session(snapshot) }
        } else if snapshot.upNext.isEmpty || snapshot.lines.isEmpty {
            if snapshot.upNext.isEmpty { session(snapshot) } else { upNext(snapshot) }
        } else {
            HStack(alignment: .top, spacing: 14) {
                session(snapshot, compact: true)
                Divider()
                upNext(snapshot, compact: true)
            }
        }
    }

    /// The plan loaded in the Log tab: Coach's next session, or whatever's queued.
    /// One row per lift, sets compressed — "90x8 ×3" — so four fit.
    private func upNext(_ snapshot: WidgetSnapshot, compact: Bool = false) -> some View {
        let shown = Array(snapshot.upNext.prefix(4))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.accent)
                Text("UP NEXT")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.5)
                    .foregroundStyle(.secondary)
            }
            Text(snapshot.upNext.count == 1 ? "1 lift loaded" : "\(snapshot.upNext.count) lifts loaded")
                .font((compact ? Font.headline : .title3).weight(.heavy))
                .fontWidth(.condensed)
                .lineLimit(1)
                .padding(.top, 4)
            if compact { Spacer().frame(height: 6) } else { Spacer(minLength: 6) }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                    row(name: line.name, sets: compactSets(line.sets))
                }
                if snapshot.upNext.count > shown.count {
                    Text("+\(snapshot.upNext.count - shown.count) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Name left, sets right, one line.
    private func row(name: String, sets: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name.replacingOccurrences(of: "-", with: " "))
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(sets)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// "90x8 90x8 90x8" → "90x8 ×3"; "bwx6 bwx6 bwx7" → "bwx6 ×2 bwx7". A
    /// trailing " · 1 done" is kept as is.
    private func compactSets(_ sets: String) -> String {
        let parts = sets.components(separatedBy: " · ")
        let tokens = parts[0].split(separator: " ").map(String.init)
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            var run = 1
            while i + run < tokens.count, tokens[i + run] == tokens[i] { run += 1 }
            out.append(run > 1 ? "\(tokens[i]) ×\(run)" : tokens[i])
            i += run
        }
        return ([out.joined(separator: " ")] + parts.dropFirst()).joined(separator: " · ")
    }

    private func session(_ snapshot: WidgetSnapshot, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(relative(snapshot))
                .font((compact ? Font.headline : .title3).weight(.heavy))
                .fontWidth(.condensed)
                .lineLimit(1)
                .padding(.top, 4)
            Text(dayLabel(snapshot))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if compact { Spacer().frame(height: 6) } else { Spacer(minLength: 6) }
            lines(snapshot, compact: compact)
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

    /// Small, or sharing the medium with the plan: the lifts and their last set.
    /// Medium on its own: the lifts and every set.
    private func lines(_ snapshot: WidgetSnapshot, compact: Bool = false) -> some View {
        let narrow = compact || family == .systemSmall
        let shown = Array(snapshot.lines.prefix(4))
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                row(name: line.name, sets: narrow ? compactSets(line.sets) : line.sets)
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
            Text("Open Grepp and land a set.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Words

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
