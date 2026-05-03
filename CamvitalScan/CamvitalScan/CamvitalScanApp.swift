import SwiftUI

@main
struct CamvitalScanApp: App {
    @StateObject private var history = HistoryStore(
        seedReadings: AppLaunchConfiguration.isAppStoreScreenshotMode
            ? AppLaunchConfiguration.seededHistory
            : nil
    )
    @StateObject private var settings = SettingsStore()
    @StateObject private var healthKit = HealthKitManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(history)
                .environmentObject(settings)
                .environmentObject(healthKit)
                .preferredColorScheme(.dark)
        }
    }
}
