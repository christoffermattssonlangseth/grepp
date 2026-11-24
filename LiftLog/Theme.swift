import SwiftUI

/// Central visual style: warm and calm. Ivory by day, soft charcoal by night
/// (or true black, if Settings says so),
/// serif titles over a clean sans, generous rounded cards, and one terracotta
/// accent. Change `accent` and `onAccent` here to re-skin the whole app.
enum Theme {
    /// Terracotta, defined once in Shared/Brand.swift so the widgets match.
    static let accent = Brand.accent   // #C6613F

    /// Lighter warm terracotta for gradient endpoints and subtle highlights.
    static let accentSoft = Color(red: 0.875, green: 0.490, blue: 0.345)

    /// Anything drawn *on* the accent — button labels, the send glyph.
    static let onAccent = Brand.onAccent

    /// A lift going up. Green, because that is what green means to everyone,
    /// a touch muted to sit with the warm grounds.
    static let progressing = dynamic(light: (0.16, 0.50, 0.30), dark: (0.36, 0.72, 0.48))

    /// Text on a `progressing` fill: white on the deep green by day, charcoal
    /// on the light green by night — white there was 2.4:1.
    static let onProgressing = dynamic(light: (1, 1, 1), dark: (0.149, 0.149, 0.141))

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

    /// The page: ivory, or a warm charcoal rather than black — or black, when
    /// true black is on.
    static let ground = dynamic(light: (0.980, 0.976, 0.961), dark: (0.149, 0.149, 0.141),   // #FAF9F5 / #262624
                                black: (0, 0, 0))                                            // #000000
    /// A card's face: white on ivory, a step up from the charcoal. On true
    /// black it is black too, and the card is drawn by its outline alone.
    static let surface = dynamic(light: (1.0, 1.0, 1.0), dark: (0.188, 0.188, 0.180),        // #FFFFFF / #30302E
                                 black: (0, 0, 0))                                           // #000000
    /// A control's face — chips, secondary buttons, your chat bubble.
    static let raised = dynamic(light: (0.941, 0.933, 0.902), dark: (0.231, 0.231, 0.220),   // #F0EEE6 / #3B3B38
                                black: (0.133, 0.133, 0.125))                                // #222220
    /// The hairline round cards and between rows. On true black it is all
    /// that draws a card, so it is brighter there.
    static let rule = dynamic(light: (0.890, 0.882, 0.855), dark: (0.267, 0.263, 0.251),     // #E3E1DA / #444340
                              black: (0.310, 0.306, 0.294))                                  // #4F4E4B

    /// The outline for tiles that have none of their own: nothing in light
    /// and charcoal, where the fill sets them off, and the rule on true
    /// black, where the fill is the page.
    static let edge = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark && traits[TrueBlackTrait.self]
            ? UIColor(red: 0.310, green: 0.306, blue: 0.294, alpha: 1)
            : .clear
    })
    /// Labels and figures that step back.
    static let dim = dynamic(light: (0.45, 0.447, 0.424), dark: (0.65, 0.639, 0.604))        // #73726C / #A6A39A

    /// A colour per appearance. `black` is the true-black variant of `dark`;
    /// colours without one look the same on either dark ground.
    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double),
                                black: (Double, Double, Double)? = nil) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark
                ? (traits[TrueBlackTrait.self] ? (black ?? dark) : dark)
                : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Soft and generous, continuous like iOS's own.
    static let corner: CGFloat = 20
    /// Corner radius for nested tiles sitting inside a card.
    static let tileCorner: CGFloat = 14
    static let bigFieldHeight: CGFloat = 76

    /// Subtle top-edge highlight for directional card borders.
    static let hairlineTop = Color(UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return traits[TrueBlackTrait.self]
                ? UIColor.white.withAlphaComponent(0.20)
                : UIColor.white.withAlphaComponent(0.12)
        }
        return UIColor(red: 0.84, green: 0.83, blue: 0.80, alpha: 1)
    })

    /// Subtle bottom-edge fade for directional card borders.
    static let hairlineBottom = Color(UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return traits[TrueBlackTrait.self]
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor.white.withAlphaComponent(0.04)
        }
        return UIColor(red: 0.91, green: 0.90, blue: 0.88, alpha: 1)
    })

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

    /// Rounded display font for hero numbers and headers.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Turn a stored kebab-case name into a readable label, keeping its casing —
    /// e.g. "over-head-press" -> "over head press".
    static func readableName(_ raw: String) -> String { Brand.readableName(raw) }
}

// MARK: - True black

/// Whether dark mode draws on true black. A trait, not just a setting the
/// colours read: the colours are UIKit dynamic ones, and a trait change makes
/// them resolve again everywhere — no view rebuilt, no chat state lost.
struct TrueBlackTrait: UITraitDefinition {
    static let defaultValue = false
}

/// The same trait as SwiftUI sees it: set `.environment(\.trueBlack, …)` at
/// the root and it reaches the trait collection the colours resolve against.
private struct TrueBlackKey: UITraitBridgedEnvironmentKey {
    static let defaultValue = false
    static func read(from traitCollection: UITraitCollection) -> Bool { traitCollection[TrueBlackTrait.self] }
    static func write(to mutableTraits: inout UIMutableTraits, value: Bool) { mutableTraits[TrueBlackTrait.self] = value }
}

extension EnvironmentValues {
    var trueBlack: Bool {
        get { self[TrueBlackKey.self] }
        set { self[TrueBlackKey.self] = newValue }
    }
}

/// "PR" or "REP PR": soft tinted capsule wherever a record is shown — on a set
/// as it lands, on a lift in today's session, on a day in History.
struct RecordBadge: View {
    let record: Analytics.Record
    var body: some View {
        Text(record == .load ? "PR" : "REP PR")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(Theme.progressing)
            .background(Theme.progressing.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.progressing.opacity(0.32), lineWidth: 1))
            .accessibilityLabel(record == .load ? "personal record" : "rep record")
    }
}

/// The raised surface — the number pad, the chart, the things you act on.
struct Card<Content: View>: View {
    var glow: Color? = nil
    @ViewBuilder var content: Content
    var body: some View { content.glassCard(glow: glow) }
}

/// The flat surface — lists and chrome that should sit in the page, not float.
struct Panel<Content: View>: View {
    var glow: Color? = nil
    @ViewBuilder var content: Content
    var body: some View { content.panel(glow: glow) }
}

/// Uppercase tracked micro-label for card and section eyebrows.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.dim)
    }
}

/// Tinted rounded-square icon badge: a symbol on a faint wash of its colour.
struct IconBadge: View {
    let systemName: String
    var color: Color = Theme.accent
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(color.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(color.opacity(0.30), lineWidth: 1)
                )
            Image(systemName: systemName)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Precision capsule progress bar with gradient fill and subtle glow.
struct PrecisionMeterBar: View {
    let progress: Double
    var accent: Color = Theme.accent
    var secondaryAccent: Color = Theme.accentSoft
    var height: CGFloat = 6
    var trackColor: Color? = nil

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0), 1)
            let fillWidth = clamped <= 0 ? 0 : max(height, proxy.size.width * clamped)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(trackColor ?? Theme.raised)
                if fillWidth > 0 {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, secondaryAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)
                        .shadow(color: accent.opacity(0.32), radius: 5, x: 0, y: 0)
                }
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: progress)
    }
}

/// Bespoke inline screen header bar with optional live indicator dot and trailing control.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var statusColor: Color? = nil
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, statusColor: Color? = nil,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.statusColor = statusColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.display(28, weight: .bold))
                    .tracking(-0.7)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    HStack(spacing: 6) {
                        if let statusColor {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                                .shadow(color: statusColor.opacity(0.75), radius: 4)
                        }
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.bottom, 2)
    }
}

/// Circular elevated icon button for screen headers.
struct HeaderCircleButton: View {
    let systemName: String
    let accessibilityLabel: String
    var tint: Color = .primary
    var isSpinning: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .frame(width: 36, height: 36)
                .background(Theme.raised, in: Circle())
                .overlay(Circle().strokeBorder(Theme.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Tactile press style for interactive cards.
struct CardPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CardPressButtonStyle {
    static var cardPress: CardPressButtonStyle { CardPressButtonStyle() }
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
    /// The hairline a bare tile needs on true black. See `Theme.edge`.
    func tileEdge(cornerRadius: CGFloat = Theme.corner) -> some View {
        overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Theme.edge, lineWidth: 0.5))
    }

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
    /// lift, the model, the day. A soft capsule with a crisp hairline.
    func pill() -> some View {
        self
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1))
    }

    /// An inset row or sub-card sitting *inside* a `Panel` or `Card`, creating
    /// a clear 3-tier surface hierarchy (ground → surface → raised).
    func insetTile(cornerRadius: CGFloat = Theme.tileCorner) -> some View {
        self
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.rule.opacity(0.75), lineWidth: 1)
            )
    }

    /// The quieter surface: a card face with a directional hairline and optional
    /// ambient accent glow.
    func panel(glow: Color? = nil, cornerRadius: CGFloat = Theme.corner) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.surface)
                    if let glow {
                        RadialGradient(
                            colors: [glow.opacity(0.14), glow.opacity(0.03), .clear],
                            center: .topLeading,
                            startRadius: 4,
                            endRadius: 210
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                glow?.opacity(0.28) ?? Theme.hairlineTop,
                                Theme.rule,
                                Theme.hairlineBottom
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }

    /// The raised surface: a card with a directional hairline, optional ambient
    /// glow, and the faintest shadow, for the one or two things on a screen you act on.
    func glassCard(glow: Color? = nil, cornerRadius: CGFloat = Theme.corner) -> some View {
        self
            .panel(glow: glow, cornerRadius: cornerRadius)
            .shadow(color: .black.opacity(0.045), radius: 10, x: 0, y: 3)
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
