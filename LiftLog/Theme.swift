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
    static let accent = Color(red: 0.122, green: 0.471, blue: 0.600)   // #1F7899

    /// Anything drawn *on* the accent — button labels, the send glyph, chat text.
    /// Named rather than inlined as `.white` so a re-skin to a light accent is
    /// one edit here instead of a hunt through the views.
    static let onAccent = Color.white

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
    static func readableName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "-", with: " ")
    }
}

/// The app's mark: a barbell, drawn rather than shipped as an image so it takes
/// the accent colour, stays crisp at any size, and needs no asset per scale.
///
/// Sized by `height`; the width follows at 2.3:1. Two plates a side, with the bar
/// running past them so it reads as a bar and not a dumbbell.
struct Barbell: View {
    var height: CGFloat = 24
    var color: Color = Theme.accent

    var body: some View {
        ZStack {
            Capsule()
                .frame(height: height * 0.13)
            HStack(spacing: height * 0.09) {
                plate(0.52)
                plate(1.0)
                Spacer(minLength: height * 0.4)
                plate(1.0)
                plate(0.52)
            }
            .padding(.horizontal, height * 0.09)
        }
        .foregroundStyle(color)
        .frame(width: height * 2.3, height: height)
        .accessibilityHidden(true)
    }

    private func plate(_ scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height * 0.07, style: .continuous)
            .frame(width: height * 0.15, height: height * scale)
    }
}

extension View {
    /// Tap any empty space, or drag a scrolling list, and the keyboard goes.
    /// Controls still win their own taps — this only catches the space between
    /// them. Dismisses through the responder chain rather than a FocusState, so it
    /// works on any screen with no wiring; put it on the screen's scroll container.
    func dismissesKeyboardOnTap() -> some View {
        self
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
            .scrollDismissesKeyboard(.interactively)
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
