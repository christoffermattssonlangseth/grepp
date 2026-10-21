import SwiftUI
import UserNotifications

@main
struct LiftLogApp: App {
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The lock-screen button lands in the store, whether or not a screen is up.
        SameAgainIntent.handler = { await Store.shared.sameAgain() }
        OpenLogIntent.handler = { Store.shared.selectedTab = 0 }
        // Set before launch finishes, so a tap that launched the app is delivered.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        Self.styleSystemControls()
    }

    /// The parts SwiftUI draws through UIKit don't take `.fontDesign`: the
    /// navigation titles and the segmented switches get the panel's mono here.
    /// Selected segment: white block, black type, as on the mockup.
    private static func styleSystemControls() {
        let mono = { (size: CGFloat, weight: UIFont.Weight) in
            UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
        let bar = UINavigationBarAppearance()
        bar.configureWithDefaultBackground()
        bar.largeTitleTextAttributes = [.font: mono(32, .heavy), .kern: -1.5]
        bar.titleTextAttributes = [.font: mono(17, .bold)]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar

        let segment = UISegmentedControl.appearance()
        segment.selectedSegmentTintColor = .white
        segment.setTitleTextAttributes([.font: mono(13, .regular),
                                        .foregroundColor: UIColor(white: 0.55, alpha: 1)], for: .normal)
        segment.setTitleTextAttributes([.font: mono(13, .semibold),
                                        .foregroundColor: UIColor.black], for: .selected)

        UISearchTextField.appearance().font = mono(16, .regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                // The control panel: black, monospace, whatever the phone is set to.
                .preferredColorScheme(.dark)
                .fontDesign(.monospaced)
                .task { await store.load() }
                // The widget is what you see once the app is gone, so it gets a
                // reload on the way out whatever happened to the ones before.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { store.refreshWidget() }
                    if phase == .active { store.reloadCredentials() }
                }
        }
    }
}
