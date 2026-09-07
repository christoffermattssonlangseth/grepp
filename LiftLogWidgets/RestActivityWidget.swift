import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The rest clock, outside the app: on the lock screen while the phone is in
/// your pocket, and in the Dynamic Island while you're in the music app.
///
/// The countdown is drawn by the system from `start...end`, so it keeps
/// ticking without the app running. Once the target passes, the activity is
/// stale (the app set its stale date to `end`), and the card flips to READY
/// the same way the in-app card goes solid accent.
struct RestActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(state: context.state, due: context.isStale)
                .activityBackgroundTint(context.isStale ? Brand.accent : nil)
                .activitySystemActionForegroundColor(context.isStale ? Brand.onAccent : Brand.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.isStale ? "READY" : "REST")
                            .font(.caption2.weight(.heavy)).tracking(1.5)
                            .foregroundStyle(context.isStale ? Brand.accent : .secondary)
                        Text(context.state.exercise)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(state: context.state, size: 34)
                        .foregroundStyle(Brand.accent)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        RestProgress(state: context.state)
                            .tint(Brand.accent)
                        SameAgainButton(state: context.state, due: context.isStale)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Brand.accent)
            } compactTrailing: {
                RestCountdown(state: context.state, size: 15)
                    .foregroundStyle(context.isStale ? Brand.accent : .primary)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: context.isStale ? "checkmark" : "timer")
                    .foregroundStyle(Brand.accent)
            }
            .keylineTint(Brand.accent)
        }
    }
}

/// The big countdown. Drawn by the system, so it ticks with the app asleep.
private struct RestCountdown: View {
    let state: RestActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Text(timerInterval: state.start...state.end, countsDown: true, showsHours: false)
            .font(.system(size: size, weight: .heavy))
            .fontWidth(.condensed)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

/// The thin bar filling toward the target — the same one the in-app card has.
private struct RestProgress: View {
    let state: RestActivityAttributes.ContentState

    var body: some View {
        ProgressView(timerInterval: state.start...state.end, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
    }
}

/// The lock screen card. Same anatomy as the in-app rest card: a label, the
/// lift, the clock, a bar. Due, the whole thing goes accent.
private struct RestLockScreenView: View {
    let state: RestActivityAttributes.ContentState
    let due: Bool

    private var fore: Color { due ? Brand.onAccent : .primary }
    private var dim: Color { due ? Brand.onAccent.opacity(0.8) : .secondary }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Barbell(height: 10, color: due ? Brand.onAccent : Brand.accent)
                        Text(due ? "READY" : "REST")
                            .font(.caption2.weight(.heavy)).tracking(1.5)
                            .foregroundStyle(dim)
                    }
                    Text(state.exercise)
                        .font(.headline)
                        .foregroundStyle(fore)
                        .lineLimit(1)
                    if let next = state.nextUp {
                        Text("next · \(next)")
                            .font(.footnote)
                            .foregroundStyle(dim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                RestCountdown(state: state, size: 44)
                    .foregroundStyle(due ? Brand.onAccent : Brand.accent)
            }
            RestProgress(state: state)
                .tint(due ? Brand.onAccent : Brand.accent)
            SameAgainButton(state: state, due: due)
        }
        .padding(16)
    }
}

/// Lands the next set from the lock screen. The label is the set itself, so
/// what the tap does is never in doubt. Absent when there's nothing to land.
private struct SameAgainButton: View {
    let state: RestActivityAttributes.ContentState
    let due: Bool

    var body: some View {
        if let label = state.landLabel {
            Button(intent: SameAgainIntent()) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text(label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text(state.nextUp == nil ? "same again" : "next")
                        .font(.caption2.weight(.semibold))
                        .opacity(0.7)
                }
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(due ? Brand.accent : Brand.onAccent)
            .background(due ? Brand.onAccent : Brand.accent,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
