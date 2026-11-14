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
        XCTAssertFalse(app.buttons["translation-pending"].exists, "Completed receipts are not pending work")
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
        XCTAssertTrue(offline.buttons["translation-pending"].waitForExistence(timeout: 5))
        editor.tap(); editor.typeText(" still editing")
        let edited = editor.value as? String
        XCTAssertTrue(edited?.contains("still editing") == true)
        offline.terminate()
        offline.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, edited)
        let pending = offline.buttons["translation-pending"]
        XCTAssertTrue(pending.isHittable)
        XCTAssertLessThan(pending.frame.maxY, offline.tabBars.firstMatch.frame.minY)
        pending.tap()
        XCTAssertTrue(offline.staticTexts["Saved offline draft"].waitForExistence(timeout: 5))
        XCTAssertTrue(offline.buttons["translation-send"].firstMatch.isHittable)
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
        if restored.buttons["translation-pending"].exists {
            restored.buttons["translation-pending"].tap()
            if restored.buttons["translation-send"].firstMatch.exists { restored.buttons["translation-send"].firstMatch.tap() }
            restored.buttons["pending-done"].tap()
        }
        XCTAssertTrue(restored.buttons["translation-copy"].waitForExistence(timeout: 15))
        XCTAssertEqual(restored.textViews["translator-input"].value as? String, edited)
    }
    func testLostAcknowledgementRelaunchAnd401HidePrivateDraft() {
        let namespace = UUID().uuidString
        let lost = app("translation-outbox-lostack", namespace: namespace)
        lost.launch()
        let editor = lost.textViews["translator-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("Synthetic lost acknowledgement")
        lost.buttons["translator-submit"].tap()
        XCTAssertTrue(lost.buttons["translation-pending"].waitForExistence(timeout: 5))
        lost.terminate()
        let recover = app("translation-outbox-status", namespace: namespace)
        recover.launch()
        let pending = recover.buttons["translation-pending"]
        XCTAssertTrue(pending.waitForExistence(timeout: 10)); pending.tap()
        recover.buttons["translation-check"].tap()
        // No server history fixture is stored by the lost-ack transport. Checking
        // must retain the unknown request, not manufacture success via a POST.
        XCTAssertTrue(recover.staticTexts["No saved answer yet. Check again later."].waitForExistence(timeout: 10))
        recover.terminate()
        let denied = app("translation-outbox-401", namespace: UUID().uuidString)
        denied.launch()
        XCTAssertTrue(denied.textViews["translator-input"].waitForExistence(timeout: 10))
        denied.textViews["translator-input"].tap(); denied.textViews["translator-input"].typeText("Private synthetic draft")
        denied.buttons["translator-submit"].tap()
        XCTAssertTrue(denied.staticTexts["outbox.local"].waitForExistence(timeout: 5) || !denied.buttons["translator-submit"].exists)
        XCTAssertFalse(denied.staticTexts["Private synthetic draft"].exists)
        XCTAssertEqual(denied.textViews["translator-input"].value as? String, "")
        let shot = XCTAttachment(screenshot: denied.screenshot()); shot.name = "outbox-401-unassigned"; shot.lifetime = .keepAlways; add(shot)
    }
}
