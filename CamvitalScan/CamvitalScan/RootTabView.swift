import SwiftUI

struct RootTabView: View {
    @State private var selection = AppLaunchConfiguration.initialTab

    var body: some View {
        TabView(selection: $selection) {
            MeasureView()
                .tag(AppTab.measure)
                .tabItem {
                    Label("Measure", systemImage: "heart.circle.fill")
                }

            HistoryView()
                .tag(AppTab.history)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(PulseTheme.accent)
    }
}
