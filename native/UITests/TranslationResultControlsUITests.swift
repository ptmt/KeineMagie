import XCTest

final class TranslationResultControlsUITests: XCTestCase {
    @MainActor private func launch(locale: String = "en", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "translation-followup-accessibility"
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale, "-AppleInterfaceStyle", large ? "Dark" : "Light"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"] }
        app.launch()
        XCTAssertTrue(app.textViews["translator-input"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor private func revealEntireControl(_ control: XCUIElement, in app: XCUIApplication) {
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 8 : app.tabBars.firstMatch.frame.minY
        for _ in 0..<6 {
            let frame = control.frame
            if frame.minY >= top && frame.maxY <= bottom { break }
            let shift = frame.minY < top ? top - frame.minY : bottom - frame.maxY
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width - 4, dy: (top + bottom) / 2))
            let end = start.withOffset(CGVector(dx: 0, dy: max(-140, min(140, shift))))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertGreaterThanOrEqual(control.frame.minY, top - 1)
        XCTAssertLessThanOrEqual(control.frame.maxY, bottom + 1)
    }
    @MainActor func testClarifyIsInsideResultFooterAndClearKeepsOutput() {
        let app = launch()
        let input = app.textViews["translator-input"]
        input.tap(); input.typeText("Fragment")
        app.buttons["translator-submit"].tap()
        let clarify = app.buttons["translation-clarify"]
        XCTAssertTrue(clarify.waitForExistence(timeout: 12))
        if !clarify.isHittable { app.swipeUp() }
        let output = app.otherElements["translation-output"]
        XCTAssertTrue(output.frame.contains(clarify.frame), "Clarify must be inside the result card, not a sibling List row")
        XCTAssertGreaterThanOrEqual(clarify.frame.height, 43.9)
        capture(app, "result-footer")
        app.swipeDown()
        app.buttons["translator-clear"].tap()
        XCTAssertEqual(input.value as? String, "")
        XCTAssertEqual(app.staticTexts["translation-result-text"].label, "Fragment")
        if !clarify.isHittable { app.swipeUp() }
        clarify.tap()
        XCTAssertTrue(app.textFields["followup-question"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["followup-answer"].exists)
        capture(app, "result-cleared-discussion")
        app.buttons["followup-done"].tap()
        app.tabBars.buttons.element(boundBy: 2).tap()
        app.tabBars.buttons.element(boundBy: 0).tap()
        app.swipeDown()
        capture(app, "result-footer-after-navigation")
    }
    @MainActor func testResultFooterAllLocalesIncludingLargeType() {
        for (locale, large) in [("en", false), ("de", false), ("ru", false), ("es", false), ("fr", false), ("ru", true)] {
            let app = launch(locale: locale, large: large)
            let input = app.textViews["translator-input"]
            input.tap(); input.typeText("Fragment")
            let submit = app.buttons["translator-submit"]
            for _ in 0..<6 {
                if submit.isHittable { break }
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.45))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.15))
                start.press(forDuration: 0.1, thenDragTo: end)
            }
            submit.tap()
            let clarify = app.buttons["translation-clarify"]
            XCTAssertTrue(clarify.waitForExistence(timeout: 12))
            for _ in 0..<6 {
                let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
                if clarify.isHittable && clarify.frame.maxY <= keyboardTop - 8 { break }
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.45))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.15))
                start.press(forDuration: 0.1, thenDragTo: end)
            }
            revealEntireControl(clarify, in: app)
            let output = app.otherElements["translation-output"]
            XCTAssertTrue(output.frame.insetBy(dx: -0.1, dy: -0.1).contains(clarify.frame))
            XCTAssertGreaterThanOrEqual(clarify.frame.height, 43.9)
            if app.keyboards.firstMatch.exists { XCTAssertLessThanOrEqual(clarify.frame.maxY, app.keyboards.firstMatch.frame.minY - 8) }
            XCTAssertFalse(clarify.label.isEmpty)
            capture(app, "result-footer-\(locale)-\(large ? "large-dark" : "light")")
            clarify.tap()
            XCTAssertTrue(app.textFields["followup-question"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["followup-answer"].exists)
            app.terminate()
        }
    }
    @MainActor func testHistoryActionsTrailingAllLocales() {
        for locale in ["en", "de", "ru", "es", "fr"] {
            let app = launch(locale: locale)
            let copy = app.buttons["history-copy-followup-synthetic"]
            let clarify = app.buttons["history-clarify-followup-synthetic"]
            XCTAssertTrue(clarify.waitForExistence(timeout: 8))
            if !clarify.isHittable { app.swipeUp() }
            for button in [copy, clarify] {
                XCTAssertGreaterThanOrEqual(button.frame.width, 44)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                XCTAssertLessThanOrEqual(button.frame.width, 45, "History actions must be icon-only")
                XCTAssertGreaterThan(button.frame.minX, app.frame.midX)
                XCTAssertFalse(button.label.isEmpty)
            }
            capture(app, "history-controls-" + locale)
            clarify.tap()
            XCTAssertTrue(app.textFields["followup-question"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["followup-answer"].exists)
            app.buttons["followup-done"].tap()
            app.swipeDown()
            XCTAssertEqual(app.textViews["translator-input"].value as? String, "")
            XCTAssertFalse(app.buttons["translation-copy"].exists)
            app.terminate()
        }
    }
    @MainActor func testHistoryCopiesExactUnicodeAndOpensEachRecordWithoutChangingDraft() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "translation-history-controls"
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.textViews["translator-input"].waitForExistence(timeout: 10))
        for index in 1...2 {
            let id = "history-control-\(index)"
            let copy = app.buttons["history-copy-" + id]
            for _ in 0..<6 { if copy.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(copy.isHittable); copy.tap()
            XCTAssertEqual(copy.value as? String, "pasteboard-exact-" + id)
            app.buttons["history-clarify-" + id].tap()
            XCTAssertTrue(app.textFields["followup-question"].waitForExistence(timeout: 5))
            let context = app.descendants(matching: .any).matching(identifier: "followup-context").firstMatch
            XCTAssertTrue(context.label.contains(index == 1 ? "Привет" : "Second exact translation"))
            XCTAssertFalse(app.staticTexts["followup-answer"].exists)
            capture(app, "history-discussion-\(index)")
            app.buttons["followup-done"].tap()
        }
        app.swipeDown(); app.swipeDown()
        XCTAssertEqual(app.textViews["translator-input"].value as? String, "")
    }
    @MainActor func testStylesInsideSourceFooter() {
        let app = launch()
        let source = app.otherElements["translator-input-container"]
        let add = app.buttons["shortcut-add"]
        XCTAssertTrue(source.frame.contains(add.frame), "Styles belong inside the source card footer")
        XCTAssertGreaterThan(add.frame.minY, app.textViews["translator-input"].frame.maxY)
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        capture(app, "source-footer")
    }
    @MainActor func testHistoryDarkLargeText() {
        let app = launch(locale: "ru", large: true)
        let clarify = app.buttons["history-clarify-followup-synthetic"]
        for _ in 0..<5 { if clarify.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(clarify.isHittable)
        revealEntireControl(clarify, in: app)
        XCTAssertEqual(clarify.frame.width, 44, accuracy: 1)
        XCTAssertGreaterThan(clarify.frame.minX, app.frame.midX)
        capture(app, "history-controls-ru-dark-large")
    }
}
