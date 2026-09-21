import SwiftUI

/// Central visual style. Cold and hard-wearing: one steel accent, chunky shapes,
/// large type. Change `accent` and `onAccent` here to re-skin the whole app.
enum Theme {
    /// Steel cyan — cool and instrument-like, which suits a screen full of
    /// numbers better than a warm accent does.
    ///
    /// Deliberately a shade deeper than it looks like it wants to be: white text
    /// on it needs 4.5:1 for the small type in a Coach bubble, and a brighter
    /// steel (#2B8CB3) only manages 3.81:1. This one measures 4.99:1 on white
    /// and 4.48:1 against the light ground it also tints.
    static let accent = Brand.accent   // #1F7899, defined once in Shared/Brand.swift

    /// Anything drawn *on* the accent — button labels, the send glyph, chat text.
    /// Named rather than inlined as `.white` so a re-skin to a light accent is
    /// one edit here instead of a hunt through the views.
    static let onAccent = Brand.onAccent

    /// A lift going up. Green, because that is what green means to everyone,
    /// kept dull enough not to shout beside the steel: 3.6:1 on white, which
    /// is enough for the bold figures it colours and the dots it fills.
    static let progressing = Color(red: 0.20, green: 0.60, blue: 0.36)   // #33995C

    /// A lift that has stopped. Amber, not red: a stall is a fact to act on,
    /// not an error.
    static let stalled = Color(red: 0.80, green: 0.55, blue: 0.10)   // #CC8C1A

    /// Strava's own orange, for its button only — their brand rules ask for it.
    static let strava = Color(red: 0.988, green: 0.298, blue: 0.008)   // #FC4C02

    static let corner: CGFloat = 20
    static let bigFieldHeight: CGFloat = 76

    /// Soft accent-tinted backdrop. Gives the frosted glass something to refract,
    /// so the material cards actually read as glass rather than flat panels.
    static var backgroundView: some View {
        LinearGradient(
            colors: [accent.opacity(0.22),
                     Color(.systemGroupedBackground),
                     accent.opacity(0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    /// Turn a stored kebab-case name into a readable label, keeping its casing —
    /// e.g. "over-head-press" -> "over head press".
    static func readableName(_ raw: String) -> String { Brand.readableName(raw) }
}

/// "PR" or "REP PR": the same capsule wherever a record is shown — on a set as
/// it lands, on a lift in today's session, on a day in History.
struct RecordBadge: View {
    let record: Analytics.Record
    var body: some View {
        Text(record == .load ? "PR" : "REP PR")
            .font(.caption2.weight(.heavy))
            .tracking(0.5)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.progressing, in: Capsule())
            .foregroundStyle(.white)
            .accessibilityLabel(record == .load ? "personal record" : "rep record")
    }
}

/// The raised surface — the number pad, the chart, the things you act on.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.glassCard() }
}

/// The flat surface — lists and chrome that should sit in the page, not float.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.panel() }
}

extension View {
    /// Tap any empty space, or drag a scrolling list, and the keyboard goes.
    /// Controls still win their own taps — this only catches the space between
    /// them. Dismisses through the responder chain rather than a FocusState, so it
    /// works on any screen with no wiring; put it on the screen's scroll container.
    ///
    /// A ScrollView, not a List or Form: on those the container's tap gesture
    /// swallows the taps meant for buttons in rows. Settings uses a keyboard
    /// Done button instead.
    func dismissesKeyboardOnTap() -> some View {
        self
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
            .scrollDismissesKeyboard(.interactively)
    }

    /// The small control that names a choice and opens a menu — the bar, the
    /// lift, the model, the day. A capsule of thin material: a bare label in a
    /// Menu drew as nothing on iOS 26, and this gives it a body once, here.
    func pill() -> some View {
        self
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }

    /// The quieter surface. Same shape and padding as `glassCard`, but thinner
    /// material, no highlight edge and no shadow — so it sits *in* the page rather
    /// than floating above it. Use it for chrome and lists; reserve `glassCard` for
    /// the one or two things on a screen that should read as raised.
    func panel(cornerRadius: CGFloat = Theme.corner) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Frosted-glass card: a translucent material panel with a hairline highlight
    /// edge and a soft drop shadow. The raised surface — when everything is a
    /// glass card nothing is, so most content belongs in `panel` instead.
    func glassCard(cornerRadius: CGFloat = Theme.corner) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
    }
}
