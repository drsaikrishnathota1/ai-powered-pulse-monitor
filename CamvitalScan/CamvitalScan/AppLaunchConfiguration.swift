import Foundation

enum AppTab: String {
    case measure
    case history
    case settings
}

enum AppLaunchConfiguration {
    private static let arguments = ProcessInfo.processInfo.arguments
    private static let environment = ProcessInfo.processInfo.environment

    static let isAppStoreScreenshotMode = arguments.contains("APPSTORE_SCREENSHOTS")

    static var initialTab: AppTab {
        guard
            let rawValue = environment["APPSTORE_TAB"],
            let tab = AppTab(rawValue: rawValue)
        else {
            return .measure
        }
        return tab
    }

    static var seededHistory: [HeartReading] {
        [
            HeartReading(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                date: Date(timeIntervalSince1970: 1_777_750_000),
                bpm: 68,
                quality: 0.94
            ),
            HeartReading(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                date: Date(timeIntervalSince1970: 1_777_663_600),
                bpm: 74,
                quality: 0.91
            ),
            HeartReading(
                id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                date: Date(timeIntervalSince1970: 1_777_577_200),
                bpm: 63,
                quality: 0.89
            )
        ]
    }
}
