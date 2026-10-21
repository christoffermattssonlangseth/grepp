import Foundation

/// How the home-screen widget looks, picked in Settings. Kept in the App
/// Group beside the snapshot, so the widget reads what the app wrote.
enum WidgetStyle: String, CaseIterable, Identifiable {
    /// The app's own grounds: charcoal in dark mode, ivory in light.
    case auto
    /// Black whatever the phone's mode.
    case black
    /// The steel tint the widget had before: the accent washed over the ground.
    case steel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "follow phone"
        case .black: return "black"
        case .steel: return "steel"
        }
    }

    static let key = "widget_style"

    static var current: WidgetStyle {
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.string(forKey: key)
            .flatMap(WidgetStyle.init(rawValue:)) ?? .auto
    }
}
