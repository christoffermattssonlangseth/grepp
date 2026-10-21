import SwiftUI

/// Central visual style: a control panel. Black ground, monospace type, square
/// corners, 1px rules, and one safety orange for whatever is live. Change
/// `accent` and `onAccent` here to re-skin the whole app.
enum Theme {
    /// Safety orange, defined once in Shared/Brand.swift so the widgets match.
    /// Kept for what is live or chosen: the field being typed in, the set under
    /// way, the selected lift, the button that lands a set.
    static let accent = Brand.accent   // #FF6B1A

    /// Anything drawn *on* the accent — button labels, the send glyph, chat text.
    /// Black: 7.3:1 on the orange, where white only manages 2.9:1.
    static let onAccent = Brand.onAccent

    /// A lift going up. Green, because that is what green means to everyone:
    /// 5.9:1 on black, enough for the bold figures it colours.
    static let progressing = Color(red: 0.20, green: 0.60, blue: 0.36)   // #33995C

    /// A lift that has stopped. Amber, not red: a stall is a fact to act on,
    /// not an error.
    static let stalled = Color(red: 0.80, green: 0.55, blue: 0.10)   // #CC8C1A

    /// Strava's own orange, for its button only — their brand rules ask for it.
    static let strava = Color(red: 0.988, green: 0.298, blue: 0.008)   // #FC4C02

    /// Text that warns: a save that failed, a line that won't parse. A light
    /// amber, 10:1 on black, so it stays apart from the orange accent.
    static let warning = Color(red: 0.94, green: 0.69, blue: 0.29)   // #F0B04A

    /// Strava's orange lifted for small text on black (#FF8A50, 8.4:1).
    static let stravaText = Color(red: 1.00, green: 0.54, blue: 0.31)

    /// The panel face: a step off black, so a panel reads against the ground.
    static let surface = Color(white: 0.04)   // #0A0A0A
    /// The 1px line around panels and between rows.
    static let rule = Color(white: 0.23)      // #3A3A3A
    /// Labels and figures that step back: 6:1 on black.
    static let dim = Color(white: 0.55)       // #8C8C8C

    /// Square, near enough: just enough to stop corners shimmering.
    static let corner: CGFloat = 2
    static let bigFieldHeight: CGFloat = 76

    /// The ground every screen sits on.
    static var backgroundView: some View {
        Color.black.ignoresSafeArea()
    }

    /// A list row's face: the panel colour, square.
    static var row: some View { Rectangle().fill(surface) }

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
            .background(Theme.progressing, in: Rectangle())
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
    /// lift, the model, the day. A bracketed box on black: a bare label in a
    /// Menu drew as nothing on iOS 26, and this gives it a body once, here.
    func pill() -> some View {
        self
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.black, in: Rectangle())
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
    }

    /// The quieter surface: a panel face with a 1px rule round it. It sits *in*
    /// the page; reserve `glassCard` for the one or two things that should read
    /// as raised.
    func panel(cornerRadius: CGFloat = Theme.corner) -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Theme.rule, lineWidth: 1))
    }

    /// The raised surface. On a control panel nothing floats, so raised means a
    /// brighter rule rather than a shadow. Named for what it used to be.
    func glassCard(cornerRadius: CGFloat = Theme.corner) -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color(white: 0.32), lineWidth: 1))
    }
}

/// The control panel's button: a square box with a 1px rule, its label in the
/// tint; prominent, a solid block of the tint with black type. Stands in for
/// the system's bordered and glass styles, whose capsules and blur belong to
/// a softer app. Small and mini control sizes get tighter padding.
struct PanelButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let small = controlSize == .small || controlSize == .mini
        return configuration.label
            .font(small ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            .padding(.horizontal, small ? 9 : 14)
            .padding(.vertical, small ? 5 : 9)
            .foregroundStyle(prominent ? AnyShapeStyle(Theme.onAccent) : AnyShapeStyle(.tint))
            .background {
                if prominent { Rectangle().fill(.tint) } else { Rectangle().fill(Color.black) }
            }
            .overlay {
                if !prominent { Rectangle().strokeBorder(Theme.rule, lineWidth: 1) }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PanelButtonStyle {
    /// A ruled box, label in the tint.
    static var panel: PanelButtonStyle { PanelButtonStyle() }
    /// A solid block of the tint, black label: the one thing to press.
    static var panelProminent: PanelButtonStyle { PanelButtonStyle(prominent: true) }
}
