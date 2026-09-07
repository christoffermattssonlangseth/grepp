import SwiftUI

@main
struct LiftLogApp: App {
    @StateObject private var store = Store.shared

    init() {
        // The lock-screen button lands in the store, whether or not a screen is up.
        SameAgainIntent.handler = { Store.shared.sameAgain() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task { await store.load() }
        }
    }
}
