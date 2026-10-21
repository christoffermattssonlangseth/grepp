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

    /// Navigation titles in the serif, the way the rest of the app's titles
    /// are: SwiftUI's `.fontDesign` doesn't reach the UIKit navigation bar.
    private static func styleSystemControls() {
        func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let d = base.fontDescriptor.withDesign(.serif) else { return base }
            return UIFont(descriptor: d, size: size)
        }
        let bar = UINavigationBarAppearance()
        bar.configureWithDefaultBackground()
        bar.largeTitleTextAttributes = [.font: serif(34, .medium)]
        bar.titleTextAttributes = [.font: serif(17, .semibold)]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task { await store.load() }
                // The widget is what you see once the app is gone, so it gets a
                // reload on the way out whatever happened to the ones before.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { store.refreshWidget() }
                    if phase == .active {
                        store.reloadCredentials()
                        Task { await store.resume() }
                    }
                }
        }
    }
}
