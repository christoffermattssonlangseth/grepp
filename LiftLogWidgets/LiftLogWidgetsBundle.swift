import SwiftUI
import WidgetKit

/// The extension's two faces: the rest clock on the lock screen and in the
/// Dynamic Island, and the last-session widget on the home screen.
@main
struct LiftLogWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LastSessionWidget()
        RestActivityWidget()
    }
}
