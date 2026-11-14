import XCTest

final class QuietTranslatorUITests: XCTestCase {
    private func launch(_ mode: String, namespace: String = UUID().uuidString, locale: String = "en", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = mode
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = namespace
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.textViews["translator-input"].waitForExistence(timeout: 12))
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "quiet-" + name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCompletedAppearsInHistoryAndLastControlClearsTabs() {
        let app = launch("translation-controls")
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("Synthetic completed request")
        app.buttons["translator-submit"].tap()
        XCTAssertTrue(app.buttons["translation-copy"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["translation-pending"].exists)
        shot(app, "completed")
        app.swipeUp()
        let copy = app.buttons["history-copy-synthetic-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        if !copy.isHittable { app.swipeUp() }
        XCTAssertTrue(copy.isHittable)
        XCTAssertLessThan(copy.frame.maxY, app.tabBars.firstMatch.frame.minY)
        shot(app, "completed-history-bottom")
    }
    func testPendingCompletedAndLongOutput() {
        let app = launch("translation-pending")
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("Synthetic long output")
        app.buttons["translator-submit"].tap()
        XCTAssertTrue(app.buttons["translation-pending"].waitForExistence(timeout: 3))
        shot(app, "translating")
        XCTAssertTrue(app.buttons["translation-copy"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["translation-pending"].exists)
        XCTAssertFalse(app.staticTexts["Completed"].exists)
        XCTAssertTrue(app.buttons["translator-submit"].isHittable)
        shot(app, "completed-long-output")
    }
    func testTwoPendingAndDraftSurviveLifecycle() {
        let namespace = UUID().uuidString
        let app = launch("translation-outbox-offline", namespace: namespace)
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("First saved request")
        app.buttons["translator-submit"].tap()
        XCTAssertTrue(app.buttons["translation-pending"].waitForExistence(timeout: 5))
        app.buttons["translator-clear"].tap(); editor.typeText("Second saved request")
        app.buttons["translator-submit"].tap()
        XCTAssertTrue(app.buttons["translation-pending"].label.contains("2"))
        shot(app, "two-pending-main")
        app.buttons["translation-pending"].tap()
        XCTAssertTrue(app.staticTexts["First saved request"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Second saved request"].exists)
        shot(app, "two-pending-sheet")
        app.buttons["pending-done"].tap()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(editor.value as? String, "Second saved request")
        app.terminate()
        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 12))
        XCTAssertEqual(editor.value as? String, "Second saved request")
        XCTAssertTrue(app.buttons["translation-pending"].label.contains("2"))
        shot(app, "relaunch")
    }
    func testFiveLocalesFailureCopy() {
        let labels = ["de": "Antwort nicht erhalten", "en": "Couldn’t get the answer", "ru": "Не удалось получить ответ", "es": "No se pudo obtener la respuesta", "fr": "Réponse non reçue"]
        for locale in ["de", "en", "ru", "es", "fr"] {
            let app = launch("translation-outbox-lostack", locale: locale)
            let editor = app.textViews["translator-input"]
            editor.tap(); editor.typeText("ein semmel")
            app.buttons["translator-submit"].tap()
            XCTAssertTrue(app.buttons["translation-pending"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["translation-pending"].label, labels[locale])
            shot(app, "failed-" + locale)
            app.terminate()
        }
    }
    func testLargeTypeFailureSheet() {
        let app = launch("translation-outbox-lostack", locale: "ru", large: true)
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("ein semmel")
        // Large editor may scroll the submit below the viewport.
        app.swipeUp()
        app.buttons["translator-submit"].tap()
        let pending = app.buttons["translation-pending"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        if !pending.isHittable { app.swipeUp() }
        shot(app, "dynamic-type-main")
        pending.tap()
        XCTAssertTrue(app.buttons["translation-check"].waitForExistence(timeout: 5))
        XCTAssertLessThan(app.buttons["translation-check"].frame.maxY, app.frame.maxY - 20)
        shot(app, "dynamic-type-sheet")
    }
    func testSheetReturnsToEditingDraftAndLocalMenuIsTruthful() {
        let app = launch("translation-outbox-lostack")
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("Saved request")
        app.buttons["translator-submit"].tap()
        XCTAssertTrue(app.buttons["translation-pending"].waitForExistence(timeout: 5))
        editor.tap(); editor.typeText(" still editing")
        let beforeSheet = editor.value as? String
        app.buttons["translation-pending"].tap()
        XCTAssertTrue(app.buttons["pending-done"].waitForExistence(timeout: 5))
        app.buttons["pending-done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, beforeSheet)
        editor.typeText(" after sheet")
        XCTAssertEqual((editor.value as? String)?.replacingOccurrences(of: " after sheet", with: ""), beforeSheet)
        shot(app, "draft-focus-restored")
        app.buttons["translation-pending"].tap()
        app.buttons["translation-actions"].tap()
        XCTAssertTrue(app.buttons["Delete from device"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Cancel"].exists)
        app.buttons["Delete from device"].tap()
        XCTAssertTrue(app.staticTexts["No pending translations."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Answers are in history."].exists)
        shot(app, "local-removal-empty")
    }
    func testSendingSheetHasNoCancelOrDelete() {
        let app = launch("translation-pending")
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("One in flight")
        app.buttons["translator-submit"].tap()
        XCTAssertTrue(app.buttons["translation-pending"].waitForExistence(timeout: 3))
        app.buttons["translation-pending"].tap()
        XCTAssertTrue(app.buttons["pending-done"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["translation-actions"].exists)
        XCTAssertFalse(app.buttons["translation-send"].exists)
    }
    func testProviderFailureStillOffersOriginalRequestRetry() {
        let app = launch("translation-catalog-failure")
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("Provider retry")
        app.buttons["translator-submit"].tap()
        XCTAssertTrue(app.buttons["translation-pending"].waitForExistence(timeout: 5))
        app.buttons["translation-pending"].tap()
        XCTAssertTrue(app.buttons["translation-send"].waitForExistence(timeout: 5))
    }
    func testUnknownIsCompactAndRecoveryIsInSheet() {
        let app = launch("translation-outbox-lostack")
        XCTAssertFalse(app.buttons["translation-pending"].exists)
        shot(app, "empty")
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("ein semmel")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["translator-submit"].isHittable)
        shot(app, "typing-keyboard")
        app.buttons["translator-submit"].tap()
        let pending = app.buttons["translation-pending"]
        XCTAssertTrue(pending.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Translation queue"].exists)
        XCTAssertFalse(app.buttons["Retry / check result"].exists)
        XCTAssertFalse(app.staticTexts["Outcome unknown"].exists)
        shot(app, "unknown-main")
        pending.tap()
        XCTAssertTrue(app.buttons["translation-check"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["history.delete"].exists)
        app.buttons["translation-check"].tap()
        XCTAssertTrue(app.staticTexts["No saved answer yet. Check again later."].waitForExistence(timeout: 5))
        shot(app, "unknown-sheet")
    }
}
