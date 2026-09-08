import XCTest

final class LumaUITests: XCTestCase {
    private let applicationBundleIdentifier = "by.nevermind.Luma"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication(bundleIdentifier: applicationBundleIdentifier)
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 5),
            "Luma did not reach the foreground."
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication(bundleIdentifier: applicationBundleIdentifier)
            app.launch()
            app.terminate()
        }
    }
}
