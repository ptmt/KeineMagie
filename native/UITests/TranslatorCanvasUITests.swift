import XCTest

/// Explicit synthetic transport/cache, never a paid provider or user account.
final class TranslatorCanvasUITests: XCTestCase {
    @MainActor private func launch(_ mode: String = "translation-controls", locale: String = "en", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = mode
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.textViews["translator-input"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func record(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }
    @MainActor func testContinuousCanvasAndHeaderDirection() {
        let app = launch()
        record(app, "canvas-empty-synthetic")
        let canvas = app.otherElements["translator-canvas"]
        XCTAssertTrue(canvas.exists, "Source and output belong to one continuous canvas")
        let input = app.textViews["translator-input"]
        let direction = app.buttons["translator-direction"]
        XCTAssertLessThanOrEqual(direction.frame.maxY, input.frame.minY, "Language pair belongs in navigation header")
        let settings = app.buttons["main-settings"]
        XCTAssertLessThanOrEqual(direction.frame.maxX, settings.frame.minX)
        XCTAssertEqual(direction.frame.midY, settings.frame.midY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(direction.frame.width, 44)
        XCTAssertGreaterThanOrEqual(direction.frame.height, 44)
        XCTAssertLessThanOrEqual(direction.frame.maxY, app.tabBars.firstMatch.frame.minY)
        XCTAssertFalse(app.otherElements["shortcut-strip"].exists, "Styles belong in contextual sheet")
    }
    @MainActor func testLargeKeyboardEditorStaysAboveActions() {
        let app = launch("valid", locale: "ru", large: true)
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("One\nTwo\nThree\nFour\nFive\nSix\nSeven\nEight\nLast line")
        record(app, "canvas-large-keyboard-synthetic")
        XCTAssertLessThanOrEqual(editor.frame.maxY, app.buttons["translator-submit"].frame.minY - 8)
        XCTAssertLessThanOrEqual(app.buttons["translator-direction"].frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertEqual(editor.value as? String, "One\nTwo\nThree\nFour\nFive\nSix\nSeven\nEight\nLast line")
        for id in ["translator-submit", "translator-styles", "translator-direction"] {
            let control = app.buttons[id]
            XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX, "Full control must fit at accessibility sizes: " + id)
        }
    }
    @MainActor func testFilledCanvasPreview() {
        let app = launch()
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("Пожалуйста, проверьте все условия и сохраните точный смысл исходного текста.")
        app.buttons["translator-submit"].tap()
        let copy = app.buttons["translation-copy"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: copy); waitForExpectations(timeout: 15)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.30))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        record(app, "canvas-filled-synthetic")
        XCTAssertTrue(app.staticTexts["translation-result-text"].exists)
    }
}
