import SwiftUI
import WidgetKit

/// The extension's faces: the rest clock on the lock screen and in the
/// Dynamic Island, the last-session widget on the home and lock screens, and
/// a plain shortcut into the app for the lock screen, and the same as a
/// control for the lock screen's corner buttons and Control Centre.
@main
struct LiftLogWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LastSessionWidget()
        OpenAppWidget()
        OpenAppControl()
        RestActivityWidget()
    }
}
