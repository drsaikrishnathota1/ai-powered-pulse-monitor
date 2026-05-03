import XCTest

/// Saves PNGs for App Store Connect. Run on a **6.5″ class** simulator (e.g. iPhone 17 Pro Max).
/// Output: `/tmp/CamvitalScanAppStoreScreenshots/`
final class AppStoreScreenshotUITests: XCTestCase {

    func testCapture6Point5InchScreens() throws {
        let out = URL(fileURLWithPath: "/tmp/CamvitalScanAppStoreScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        func savePNG(_ name: String) throws {
            let data = XCUIScreen.main.screenshot().pngRepresentation
            try data.write(to: out.appendingPathComponent(name))
        }

        func launch(tab: String) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["APPSTORE_SCREENSHOTS"]
            app.launchEnvironment["APPSTORE_TAB"] = tab
            app.launch()
            return app
        }

        _ = launch(tab: "measure")
        try savePNG("01_measure.png")

        _ = launch(tab: "history")
        try savePNG("02_history.png")

        _ = launch(tab: "settings")
        try savePNG("03_settings.png")

        _ = launch(tab: "measure")
        try savePNG("04_measure_again.png")
    }
}
