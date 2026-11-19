import XCTest

final class TranslationDeadlineUITests: XCTestCase {
    @MainActor func testSlowRealHTTPTranslationCompletesWithoutAttention() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "translation-deadline"
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let editor = app.textViews["translator-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("сплетни")
        app.buttons["translator-submit"].tap()
        XCTAssertTrue(app.buttons["translation-copy"].waitForExistence(timeout: 18), "A 10-second real HTTP response must not be canceled by the auth transport's former 8-second cap")
        XCTAssertEqual(editor.value as? String, "сплетни")
        XCTAssertTrue(app.staticTexts["Gerüchte"].firstMatch.exists)
        XCTAssertFalse(app.buttons["translation-pending"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "translation-real-http-ten-seconds"; shot.lifetime = .keepAlways; add(shot)
    }
}
