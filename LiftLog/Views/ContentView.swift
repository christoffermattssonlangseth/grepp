import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var showingFirstRun = false
    @State private var showingIntake = false
    @AppStorage(Prefs.intakePending) private var intakePending = false

    var body: some View {
        TabView(selection: $store.selectedTab) {
            LogView()
                .tabItem { Label("Log", systemImage: "plus.circle.fill") }
                .tag(0)
            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet") }
                .tag(1)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)
            CoachView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(Theme.accent)
        // A fresh install: ask where the log lives before anything tries to load it,
        // then, once the log can be written, the setup questions.
        .onAppear {
            showingFirstRun = store.needsSetup
            offerIntake()
        }
        .fullScreenCover(isPresented: $showingFirstRun, onDismiss: offerIntake) {
            FirstRunView().environmentObject(store)
        }
        .sheet(isPresented: $showingIntake) {
            IntakeView().environmentObject(store)
        }
        // GitHub is chosen first and connected later in Settings: the setup
        // waits for the token rather than asking questions it can't save.
        .onChange(of: store.canWriteFiles) { _, _ in offerIntake() }
    }

    private func offerIntake() {
        guard intakePending, !showingFirstRun, !store.needsSetup, store.canWriteFiles else { return }
        showingIntake = true
    }
}

