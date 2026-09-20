import XCTest

final class LumaUITests: XCTestCase {
    private let applicationBundleIdentifier = "by.nevermind.Luma"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunches() throws {
        let app = launchApplication(language: "en", locale: "en_US")

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 5),
            "Luma не перешла в состояние активного приложения."
        )
        XCTAssertTrue(app.staticTexts["Applications"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["refresh-button"].exists)
    }

    @MainActor
    func testSupportedLocalizationsRenderMainInterface() throws {
        let localizations: [(language: String, locale: String, title: String)] = [
            ("en", "en_US", "Applications"),
            ("ru", "ru_RU", "Приложения"),
            ("de", "de_DE", "Apps"),
            ("fr", "fr_FR", "Applications"),
            ("es", "es_ES", "Aplicaciones"),
            ("zh-Hans", "zh_CN", "应用"),
            ("ja", "ja_JP", "アプリケーション")
        ]

        for localization in localizations {
            let app = launchApplication(language: localization.language, locale: localization.locale)

            XCTAssertTrue(
                app.wait(for: .runningForeground, timeout: 5),
                "Luma не запустилась для локали \(localization.locale)."
            )
            XCTAssertTrue(
                app.staticTexts[localization.title].waitForExistence(timeout: 5),
                "Основной заголовок не найден для локали \(localization.locale)."
            )

            let refreshButton = app.buttons["refresh-button"]
            XCTAssertTrue(refreshButton.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(refreshButton.frame.width, 60, "Кнопка обновления слишком узкая для локали \(localization.locale).")
            XCTAssertGreaterThan(refreshButton.frame.height, 20, "Кнопка обновления имеет некорректную высоту для локали \(localization.locale).")

            app.terminate()
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = launchApplication(language: "en", locale: "en_US")
            app.terminate()
        }
    }

    @MainActor
    private func launchApplication(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: applicationBundleIdentifier)
        app.launchArguments = [
            "-AppleLanguages",
            "(\(language))",
            "-AppleLocale",
            locale
        ]
        app.launch()
        return app
    }
}
