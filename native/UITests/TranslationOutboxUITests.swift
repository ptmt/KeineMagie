import XCTest

final class TranslationOutboxUITests: XCTestCase {
    private func app(_ mode: String, namespace: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = mode
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = namespace
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        return app
    }
    func testTypingAndTranslateDuringHeldVerificationAndProviderStatus() {
        let app = app("translation-outbox-status", namespace: UUID().uuidString)
        app.launch()
        let editor = app.textViews["translator-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("Synthetic draft")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(editor.exists)
        editor.tap(); editor.typeText(" during verification")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let submit = app.buttons["translator-submit"]
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertTrue(app.buttons["translation-copy"].waitForExistence(timeout: 8))
        XCTAssertEqual(editor.value as? String, "Synthetic draft during verification")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "outbox-held-checks-completed"; shot.lifetime = .keepAlways; add(shot)
    }
    func testOfflineQueueAndTypingSurviveTerminateRelaunchThenRetry() {
        let namespace = UUID().uuidString
        let offline = app("translation-outbox-offline", namespace: namespace)
        offline.launch()
        let editor = offline.textViews["translator-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("Saved offline draft")
        offline.buttons["translator-submit"].tap()
        XCTAssertTrue(offline.staticTexts["Queued"].waitForExistence(timeout: 5))
        editor.tap(); editor.typeText(" still editing")
        let edited = editor.value as? String
        XCTAssertTrue(edited?.contains("still editing") == true)
        offline.terminate()
        offline.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, edited)
        XCTAssertTrue(offline.staticTexts["Saved offline draft"].exists)
        let shot = XCTAttachment(screenshot: offline.screenshot()); shot.name = "outbox-offline-relaunch"; shot.lifetime = .keepAlways; add(shot)
        offline.terminate()
        let online = app("translation-controls", namespace: namespace)
        // This fixture uses another owner; it must not receive the previous queue.
        online.launch()
        XCTAssertTrue(online.textViews["translator-input"].waitForExistence(timeout: 10))
        XCTAssertFalse(online.staticTexts["Saved offline draft"].exists)
        online.terminate()
        let restored = app("translation-outbox-status", namespace: namespace)
        restored.launch()
        XCTAssertTrue(restored.textViews["translator-input"].waitForExistence(timeout: 10))
        if restored.buttons["Retry / check result"].firstMatch.exists { restored.buttons["Retry / check result"].firstMatch.tap() }
        XCTAssertTrue(restored.buttons["translation-copy"].waitForExistence(timeout: 15))
        XCTAssertEqual(restored.textViews["translator-input"].value as? String, edited)
    }
}
