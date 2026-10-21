import SwiftUI
import WidgetKit

/// "Last session: Thursday · squat 87.5x5" on the home screen, and the same in
/// lock-screen sizes: a round glyph, a two-line card, a line above the clock.
/// A tap opens the app on the Log tab.
///
/// Reads the snapshot the app leaves in the App Group; never the log itself.
/// The timeline re-renders at each local midnight so "2 days ago" stays true
/// without the app being opened.
struct LastSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: LastSessionProvider()) { entry in
            LastSessionView(entry: entry)
                .widgetURL(WidgetSnapshot.logURL)
        }
        .configurationDisplayName("Last session")
        .description("What you lifted last time, and what's loaded to lift next.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
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
        switch family {
        case .accessoryCircular:
            circular.containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            rectangular.containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            inline.containerBackground(for: .widget) { Color.clear }
        default:
            homePlate(WidgetStyle.current)
        }
    }

    /// The home widget on the plate Settings picked. Black and follow-phone
    /// get a hairline edge, like the Log tab's readout windows; black keeps
    /// dark text styles in light mode, or the text would vanish on it.
    @ViewBuilder
    private func homePlate(_ style: WidgetStyle) -> some View {
        switch style {
        case .auto:
            home.containerBackground(for: .widget) {
                ZStack {
                    Color(UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
                    ContainerRelativeShape().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                }
            }
        case .black:
            home
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) {
                    ZStack {
                        Color.black
                        ContainerRelativeShape().strokeBorder(.white.opacity(0.22), lineWidth: 1)
                    }
                }
        case .steel:
            home.containerBackground(for: .widget) {
                LinearGradient(colors: [Brand.steel.opacity(0.28),
                                        Color(.systemBackground),
                                        Brand.steel.opacity(0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    @ViewBuilder
    private var home: some View {
        if let snapshot = entry.snapshot, !snapshot.lines.isEmpty || !snapshot.upNext.isEmpty {
            content(snapshot)
        } else {
            empty
        }
    }

    // MARK: - Lock screen

    /// The lock screen draws in one tint, so everything here is shape and
    /// weight, not colour; the bar is the accented part when the wallpaper
    /// tints widgets.
    private var hasSessions: Bool { !(entry.snapshot?.lines.isEmpty ?? true) }

    /// The app's glyph, and how long since you lifted: "today", "1d", "4d".
    private var circular: some View {
        VStack(spacing: 2) {
            Barbell(height: hasSessions ? 20 : 26, color: .primary)
                .widgetAccentable()
            if let snapshot = entry.snapshot, hasSessions {
                Text(shortRelative(snapshot))
                    .font(.system(size: 12, weight: .heavy))
                    .fontWidth(.condensed)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.snapshot.map { "Grepp, last session \(relative($0).lowercased())" } ?? "Grepp")
    }

    /// The plan when one is loaded, else the last session: a heading and two lifts.
    private var rectangular: some View {
        let snapshot = entry.snapshot
        let planned = !(snapshot?.upNext.isEmpty ?? true)
        let lines = Array((planned ? snapshot?.upNext : snapshot?.lines)?.prefix(2) ?? [])
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Barbell(height: 8, color: .primary).widgetAccentable()
                Text(planned ? "up next" : snapshot.map { relative($0) } ?? "grepp")
                    .font(.system(size: 11, weight: .heavy)).tracking(1)
                    .lineLimit(1)
            }
            if lines.isEmpty {
                Text("nothing logged yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Brand.readableName(line.name))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(compactSets(line.sets))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Above the clock, one line: "Yesterday · squat" or "Up next · deadlift".
    private var inline: some View {
        let snapshot = entry.snapshot
        let text: String
        if let next = snapshot?.upNext.first {
            text = "Up next · \(Brand.readableName(next.name))"
        } else if let snapshot, let last = snapshot.lines.first {
            text = "\(relative(snapshot)) · \(Brand.readableName(last.name))"
        } else {
            text = "Grepp"
        }
        return Label(text, systemImage: "dumbbell.fill")
    }

    /// The circular widget's few letters.
    private func shortRelative(_ snapshot: WidgetSnapshot) -> String {
        switch daysAgo(snapshot) {
        case .some(let n) where n <= 0: return "today"
        case .some(let n): return "\(n)d"
        case .none: return ""
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
                Text("up next")
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
            Text(Brand.readableName(name))
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
            Text("last session")
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
            Text("nothing logged yet")
                .font(.headline)
                .fontWidth(.condensed)
            Text("open grepp and land a set.")
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
        case .some(let n) where n <= 0: return "today"
        case .some(1): return "yesterday"
        case .some(let n): return "\(n) days ago"
        case .none: return snapshot.day
        }
    }

    private func dayLabel(_ snapshot: WidgetSnapshot) -> String {
        guard let day = snapshot.date else { return "" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).lowercased()
    }
}
