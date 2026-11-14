import XCTest

final class CatalogAdvisoryUITests: XCTestCase {
    private let oldWarning = "ChatGPT connection saved; model catalog unavailable. Check the connection again."
    @MainActor private func launch(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = mode
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }
    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testCatalogFailureIsSettingsOnlyAndTypingCanTranslate() {
        let app = launch("translation-catalog-unavailable")
        let editor = app.textViews["translator-input"]
        let submit = app.buttons["translator-submit"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertFalse(submit.isEnabled, "Empty text, not catalog state, disables submit")
        let before = [editor.frame, submit.frame, app.segmentedControls["translator-direction"].frame]
        Thread.sleep(forTimeInterval: 4)
        let after = [editor.frame, submit.frame, app.segmentedControls["translator-direction"].frame]
        XCTAssertEqual(before, after)
        XCTAssertFalse(app.staticTexts[oldWarning].exists)
        XCTAssertFalse(app.staticTexts["provider-diagnostic"].exists)
        screenshot(app, "catalog-empty-quiet")
        editor.tap(); editor.typeText("Synthetic catalog draft")
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertTrue(app.buttons["translation-copy"].waitForExistence(timeout: 8))
        XCTAssertEqual(editor.value as? String, "Synthetic catalog draft")
        screenshot(app, "catalog-translation-completed")
        app.buttons["Settings"].tap()
        app.buttons["ChatGPT"].tap()
        let diagnostic = app.staticTexts["provider-diagnostic"]
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 8))
        XCTAssertTrue(diagnostic.label.contains("Connection saved."))
        XCTAssertTrue(app.buttons["Disconnect ChatGPT"].exists)
        XCTAssertFalse(app.staticTexts[oldWarning].exists)
        screenshot(app, "catalog-settings-advisory")
    }
    @MainActor func testTimeoutIsAdvisoryAndActualFailureRemainsInQueue() {
        let timeout = launch("translation-catalog-timeout")
        let editor = timeout.textViews["translator-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 4)
        editor.tap(); editor.typeText("Synthetic timeout draft")
        XCTAssertTrue(timeout.buttons["translator-submit"].isEnabled)
        timeout.buttons["translator-submit"].tap()
        XCTAssertTrue(timeout.buttons["translation-copy"].waitForExistence(timeout: 8))
        screenshot(timeout, "catalog-timeout-translation-completed")
        timeout.terminate()
        let failure = launch("translation-catalog-failure")
        XCTAssertTrue(failure.textViews["translator-input"].waitForExistence(timeout: 10))
        failure.textViews["translator-input"].tap(); failure.textViews["translator-input"].typeText("Synthetic failed translation")
        failure.buttons["translator-submit"].tap()
        XCTAssertTrue(failure.buttons["Retry / check result"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(failure.buttons["translation-copy"].exists)
        XCTAssertEqual(failure.textViews["translator-input"].value as? String, "Synthetic failed translation")
        XCTAssertFalse(failure.staticTexts[oldWarning].exists)
        screenshot(failure, "catalog-real-request-failed-queue")
    }
}
