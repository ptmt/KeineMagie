import XCTest

final class TranslationFollowupUITests: XCTestCase {
    @MainActor private func launch(_ mode: String = "translation-followup", locale: String = "en", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = mode
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"] }
        app.launch()
        XCTAssertTrue(app.textViews["translator-input"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor private func reveal(_ control: XCUIElement, in app: XCUIApplication) {
        // Finish native interactive keyboard dismissal before measuring the
        // scroll viewport; its height changes while the dismissal is in flight.
        if app.keyboards.firstMatch.exists {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.30))
            start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.95)))
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
            waitForExpectations(timeout: 5)
        }
        for _ in 0..<8 {
            let top = app.navigationBars.firstMatch.frame.maxY + 8
            let bottom = app.buttons["translator-submit"].frame.minY - 8
            print("ENTRY GEOMETRY control=\(control.frame) top=\(top) bottom=\(bottom)")
            if control.exists && control.frame.minY >= top && control.frame.maxY <= bottom { break }
            let frame = control.frame
            let shift = frame.minY < top ? top - frame.minY : bottom - frame.maxY
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width - 4, dy: (top + bottom) / 2))
            // Native pan recognition ignores tiny correction drags.
            let distance = (shift < 0 ? -1.0 : 1.0) * max(24, min(100, abs(shift)))
            start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)))
        }
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        let bottom = app.buttons["translator-submit"].frame.minY - 8
        capture(app, "followup-entry-full-bounds")
        XCTAssertGreaterThanOrEqual(control.frame.minY, top - 1)
        XCTAssertLessThanOrEqual(control.frame.maxY, bottom + 1)
    }
    @MainActor private func translate(_ app: XCUIApplication) {
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("Fragment")
        if !app.buttons["translator-submit"].isHittable { app.swipeUp() }
        app.buttons["translator-submit"].tap()
        let button = app.buttons["translation-clarify"]
        XCTAssertTrue(button.waitForExistence(timeout: 12))
        reveal(button, in: app)
        button.tap()
    }
    @MainActor func testCompactKeyboardSendPreviewAndApplyPair() {
        let app = launch(); translate(app)
        let input = app.textFields["followup-question"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["followup-send"].isEnabled)
        let initial = input.frame.height
        input.typeText("It is an appointment.\nPlease explain.\nThird line.\nFourth line.")
        XCTAssertGreaterThan(input.frame.height, initial)
        capture(app, "followup-small-keyboard")
        app.buttons["followup-send"].tap()
        XCTAssertTrue(app.staticTexts["followup-answer"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.staticTexts["followup-answer"].label, "Short explanation: this means an appointment.")
        XCTAssertFalse(app.buttons["followup-apply"].exists, "Pair preview is an explicit disclosure")
        let preview = app.buttons["followup-proposal"]
        if !preview.isHittable { app.swipeUp() }
        preview.tap()
        if !app.buttons["followup-apply"].exists || !app.buttons["followup-apply"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["followup-proposed-source"].exists)
        capture(app, "followup-paired-preview")
        app.buttons["followup-apply"].tap()
        XCTAssertTrue(app.staticTexts["followup-applied"].exists)
        app.buttons["followup-done"].tap()
        XCTAssertEqual(app.textViews["translator-input"].value as? String, "У меня встреча.")
        XCTAssertEqual(app.staticTexts["translation-result-text"].label, "Ich habe einen Termin.")
        capture(app, "followup-applied-pair")
    }
    @MainActor func testErrorRetryPreservesQuestionAndUsesOneAcceptedTurn() {
        let app = launch("translation-followup-retry"); translate(app)
        let input = app.textFields["followup-question"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("Explain")
        app.buttons["followup-send"].tap()
        XCTAssertTrue(app.staticTexts["followup-error"].waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "Explain")
        capture(app, "followup-error-kept-draft")
        app.buttons["followup-send"].tap()
        XCTAssertTrue(app.staticTexts["followup-answer"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(identifier: "followup-answer").count, 1)
    }
    @MainActor func testFiveLocaleCompactEntryAndKeyboard() {
        for locale in ["en", "de", "ru", "es", "fr"] {
            let app = launch("translation-followup-accessibility", locale: locale)
            let open = app.buttons["history-clarify-followup-synthetic"]
            if !open.isHittable { app.swipeUp() }
            XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
            let input = app.textFields["followup-question"]
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["followup-send"].isEnabled)
            capture(app, "followup-" + locale + "-empty-keyboard")
            app.terminate()
        }
    }
    @MainActor func testRussianDarkAccessibilityComposer() {
        let app = launch("translation-followup-accessibility", locale: "ru", large: true)
        app.swipeUp(); app.swipeUp()
        let open = app.buttons["history-clarify-followup-synthetic"]
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        let input = app.textFields["followup-question"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("Context")
        XCTAssertTrue(app.buttons["followup-send"].isHittable)
        capture(app, "followup-ru-dark-accessibility-keyboard")
    }
}
