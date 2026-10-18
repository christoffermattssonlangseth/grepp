import AppIntents
import SwiftUI
import WidgetKit

/// Grepp in place of the torch or camera at the foot of the lock screen, or in
/// Control Centre. Controls draw only a symbol, so it's the system dumbbell
/// rather than the app's barbell.
struct OpenAppControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OpenAppControl") {
            ControlWidgetButton(action: OpenLogIntent()) {
                Label("Grepp", systemImage: "dumbbell.fill")
            }
        }
        .displayName("Open Grepp")
        .description("Opens Grepp on the Log tab.")
    }
}
