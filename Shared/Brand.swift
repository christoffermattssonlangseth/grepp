import SwiftUI

/// The one colour and the one mark that the app and its widgets both draw.
///
/// Lives outside `LiftLog/` on purpose: this folder compiles into the widget
/// extension as well, and the rest of `Theme` leans on UIKit things (the
/// keyboard dismisser) that don't exist there. `Theme.accent` is this value.
enum Brand {
    /// Steel cyan — cool and instrument-like, which suits a screen full of
    /// numbers better than a warm accent does. See `Theme` for the contrast
    /// numbers that picked this exact shade.
    static let accent = Color(red: 0.122, green: 0.471, blue: 0.600)   // #1F7899

    /// Anything drawn *on* the accent.
    static let onAccent = Color.white

    /// A stored kebab-case name as a label, casing kept: "over-head-press"
    /// reads "over head press". Here so the widget says it the same way.
    static func readableName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "-", with: " ")
    }
}

/// The UserDefaults keys the app and its extensions share. One spelling each:
/// a typo in a string literal would have quietly given the lock screen a
/// default rest for ever.
enum Prefs {
    static let muscleMap = "muscle_map"
    static let barWeight = "bar_weight"
    static let plateInventory = "plate_inventory"
    static let barOverrides = "bar_overrides"
    static let restTarget = "rest_target"
    static let stravaEnabled = "strava_enabled"
    static let coachModel = "coach_model"
    static let coachShowCost = "coach_show_cost"
    static let coachFableOK = "coach_fable_ok"
    static let trendsExercise = "trends_exercise"
    static let trendsMode = "trends_mode"
}

/// The app's mark: a barbell, drawn rather than shipped as an image so it takes
/// the accent colour, stays crisp at any size, and needs no asset per scale.
///
/// Sized by `height`; the width follows at 2.3:1. Two plates a side, with the bar
/// showing between them and at the sleeves.
struct Barbell: View {
    var height: CGFloat = 24
    var color: Color = Brand.accent

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
