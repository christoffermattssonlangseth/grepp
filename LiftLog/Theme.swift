import SwiftUI

/// Central visual style: warm and calm. Ivory by day, soft charcoal by night,
/// serif titles over a clean sans, generous rounded cards, and one terracotta
/// accent. Change `accent` and `onAccent` here to re-skin the whole app.
enum Theme {
    /// Terracotta, defined once in Shared/Brand.swift so the widgets match.
    static let accent = Brand.accent   // #C6613F

    /// Anything drawn *on* the accent — button labels, the send glyph.
    static let onAccent = Brand.onAccent

    /// A lift going up. Green, because that is what green means to everyone,
    /// a touch muted to sit with the warm grounds.
    static let progressing = dynamic(light: (0.16, 0.50, 0.30), dark: (0.36, 0.72, 0.48))

    /// A lift that has stopped. Amber, not red: a stall is a fact to act on,
    /// not an error.
    static let stalled = Color(red: 0.80, green: 0.55, blue: 0.10)   // #CC8C1A

    /// Strava's own orange, for its button only — their brand rules ask for it.
    static let strava = Color(red: 0.988, green: 0.298, blue: 0.008)   // #FC4C02

    /// Text that warns: a save that failed, a line that won't parse. Deep
    /// amber on ivory (5.4:1), light amber on charcoal.
    static let warning = dynamic(light: (0.56, 0.33, 0.00), dark: (0.94, 0.69, 0.29))

    /// Strava's orange for small text — deep on ivory, lifted on charcoal.
    static let stravaText = dynamic(light: (0.72, 0.22, 0.00), dark: (1.00, 0.54, 0.31))

    /// The page: ivory, or a warm charcoal rather than black.
    static let ground = dynamic(light: (0.980, 0.976, 0.961), dark: (0.149, 0.149, 0.141))   // #FAF9F5 / #262624
    /// A card's face: white on ivory, a step up from the charcoal.
    static let surface = dynamic(light: (1.0, 1.0, 1.0), dark: (0.188, 0.188, 0.180))        // #FFFFFF / #30302E
    /// A control's face — chips, secondary buttons, your chat bubble.
    static let raised = dynamic(light: (0.941, 0.933, 0.902), dark: (0.231, 0.231, 0.220))   // #F0EEE6 / #3B3B38
    /// The hairline round cards and between rows.
    static let rule = dynamic(light: (0.890, 0.882, 0.855), dark: (0.267, 0.263, 0.251))     // #E3E1DA / #444340
    /// Labels and figures that step back.
    static let dim = dynamic(light: (0.45, 0.447, 0.424), dark: (0.65, 0.639, 0.604))        // #73726C / #A6A39A

    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Soft and generous, continuous like iOS's own.
    static let corner: CGFloat = 16
    static let bigFieldHeight: CGFloat = 76

    /// The ground every screen sits on.
    static var backgroundView: some View {
        ground.ignoresSafeArea()
    }

    /// A list row's face.
    static var row: some View { Rectangle().fill(surface) }

    /// The serif for titles and big moments: Apple's New York.
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
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

/// Rises and fades in the first time it comes on screen: rows that arrive
/// as you scroll slide into place rather than popping in.
private struct SlideIn: ViewModifier {
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear { withAnimation(.smooth(duration: 0.7)) { shown = true } }
    }
}

extension View {
    /// Rise and fade in on first showing. See `SlideIn`.
    func slidesIn() -> some View { modifier(SlideIn()) }

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
    /// lift, the model, the day. A soft capsule: a bare label in a
    /// Menu drew as nothing on iOS 26, and this gives it a body once, here.
    func pill() -> some View {
        self
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.raised, in: Capsule())
    }

    /// The quieter surface: a card face with a hairline round it. It sits *in*
    /// the page; reserve `glassCard` for the one or two things that should read
    /// as raised.
    func panel(cornerRadius: CGFloat = Theme.corner) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.rule, lineWidth: 0.5))
    }

    /// The raised surface: a card with a hairline and the faintest shadow, for
    /// the one or two things on a screen you act on.
    func glassCard(cornerRadius: CGFloat = Theme.corner) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.rule, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

/// The app's button: a soft rounded block — warm grey with the label in the
/// tint, or, prominent, solid tint with white type. Stands in for
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
            .padding(.horizontal, small ? 10 : 16)
            .padding(.vertical, small ? 6 : 10)
            .foregroundStyle(prominent ? AnyShapeStyle(Theme.onAccent) : AnyShapeStyle(.tint))
            .background {
                let shape = RoundedRectangle(cornerRadius: small ? 10 : 12, style: .continuous)
                if prominent { shape.fill(.tint) } else { shape.fill(Theme.raised) }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PanelButtonStyle {
    /// A warm grey block, label in the tint.
    static var panel: PanelButtonStyle { PanelButtonStyle() }
    /// A solid block of the tint, white label: the one thing to press.
    static var panelProminent: PanelButtonStyle { PanelButtonStyle(prominent: true) }
}
