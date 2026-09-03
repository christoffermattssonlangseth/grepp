import SwiftUI

/// Central visual style. Bold, gym-friendly: one strong accent, chunky shapes,
/// large type. Change `accent` here to re-skin the whole app.
enum Theme {
    /// Vivid orange — high-energy, reads well in light and dark.
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.13)

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
    /// Frosted-glass card: a translucent material panel with a hairline highlight
    /// edge and a soft drop shadow. The one place the app's card look is defined.
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
