import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store

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
    }
}

