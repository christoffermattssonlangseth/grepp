import SwiftUI

@main
struct LiftLogApp: App {
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The lock-screen button lands in the store, whether or not a screen is up.
        SameAgainIntent.handler = { Store.shared.sameAgain() }
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
                }
        }
    }
}
