import XCTest

final class TranslationCopyUITests: XCTestCase {
    @MainActor
    func testClearLivesInsideInputKeepsKeyboardAndUsesAllFiveLabels() {
        for (locale, label) in [("de", "Text löschen"), ("en", "Clear text"), ("ru", "Очистить текст"), ("es", "Borrar texto"), ("fr", "Effacer le texte")] {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "valid"
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
            app.launch()
            let editor = app.textViews["translator-input"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            let clear = app.buttons["translator-clear"]
            XCTAssertFalse(clear.exists)
            editor.tap(); editor.typeText("Long input with Unicode Привет 👋 and another line\nKeep typing")
            XCTAssertTrue(clear.waitForExistence(timeout: 3))
            XCTAssertEqual(clear.label, label)
            XCTAssertFalse(clear.staticTexts[label].exists)
            XCTAssertGreaterThanOrEqual(clear.frame.width, 44)
            XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
            let container = app.otherElements["translator-input-container"]
            XCTAssertTrue(container.frame.contains(clear.frame), "Clear must be inside the input border")
            XCTAssertLessThanOrEqual(editor.frame.maxX, clear.frame.minX, "Typing must reserve space for the clear target")
            clear.tap()
            XCTAssertEqual(editor.value as? String, "")
            XCTAssertFalse(clear.exists)
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            editor.typeText("Continue")
            XCTAssertEqual(editor.value as? String, "Continue")
            XCTAssertFalse(app.buttons["translation-copy"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testClearPreservesCompletedOutput() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "translation-copy"
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        let editor = app.textViews["translator-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("SOURCE NOT OUTPUT")
        let submit = app.buttons["translator-submit"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: submit)
        waitForExpectations(timeout: 10)
        submit.tap()
        XCTAssertTrue(app.buttons["translation-copy"].waitForExistence(timeout: 10))
        app.buttons["translator-clear"].tap()
        XCTAssertEqual(editor.value as? String, "")
        XCTAssertTrue(app.buttons["translation-copy"].exists, "Clear input is not delete output or history")
        XCTAssertFalse(submit.isEnabled)
    }

    @MainActor
    func testClearIsDisabledDuringPendingTranslation() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "translation-pending"
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        let editor = app.textViews["translator-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("Keep this pending draft")
        let submit = app.buttons["translator-submit"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: submit)
        waitForExpectations(timeout: 10)
        submit.tap()
        let clear = app.buttons["translator-clear"]
        XCTAssertTrue(clear.exists)
        XCTAssertFalse(clear.isEnabled)
        XCTAssertEqual(editor.value as? String, "Keep this pending draft")
        XCTAssertTrue(app.buttons["translation-copy"].waitForExistence(timeout: 15))
        XCTAssertTrue(clear.isEnabled)
    }

    @MainActor
    func testRenderedQuietControlsWithLongInput() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "translation-controls"
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        let editor = app.textViews["translator-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        // Create the same custom tag as the supplied screenshot through the real UI.
        app.buttons["shortcut-add"].tap()
        let title = app.textFields["shortcut-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("bike")
        let instruction = app.textViews["shortcut-instruction"]
        instruction.tap(); instruction.typeText("Use bicycle vocabulary.")
        app.buttons["shortcut-save"].tap()
        editor.tap()
        editor.typeText("ограничений к требованиям: пожалуйста, проверьте все условия и сохраните точный смысл исходного текста.\nДополнительная строка для проверки поля ввода.")
        let submit = app.buttons["translator-submit"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: submit)
        waitForExpectations(timeout: 10)
        submit.tap()
        let copy = app.buttons["translation-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        XCTAssertFalse(copy.staticTexts["Copy"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "native-quiet-controls-synthetic-long-input"
        screenshot.lifetime = .keepAlways; add(screenshot)
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let clear = app.buttons["translator-clear"]
        if copy.isHittable {
            copy.tap()
            XCTAssertEqual(copy.label, "Copied")
        }
        let keyboard = XCTAttachment(screenshot: app.screenshot())
        keyboard.name = "native-quiet-controls-synthetic-keyboard"
        keyboard.lifetime = .keepAlways; add(keyboard)
        clear.tap(); editor.typeText("Upper-right editing remains available")
        XCTAssertEqual(editor.value as? String, "Upper-right editing remains available")
    }

    @MainActor
    func testOneTapCopiesExactCompletedTranslationInAllLocales() {
        for (locale, label, copied) in [("de", "Kopieren", "Kopiert"), ("en", "Copy", "Copied"), ("ru", "Копировать", "Скопировано"), ("es", "Copiar", "Copiado"), ("fr", "Copier", "Copié")] {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "translation-copy"
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
            app.launch()
            let editor = app.textViews["translator-input"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["translation-copy"].exists)
            editor.tap(); editor.typeText("SOURCE NOT OUTPUT")
            let submit = app.buttons["translator-submit"]
            let ready = NSPredicate(format: "enabled == true")
            expectation(for: ready, evaluatedWith: submit)
            waitForExpectations(timeout: 10)
            submit.tap()
            let button = app.buttons["translation-copy"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            for _ in 0..<4 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.isHittable)
            XCTAssertEqual(button.label, label)
            XCTAssertFalse(button.staticTexts[label].exists, "Copy must be an icon, not visible text")
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            button.tap()
            XCTAssertEqual(button.label, copied)
            // Simulator-only app-side probe reads the actual UIPasteboard API after
            // the real button action; cross-process test-runner pasteboards differ.
            XCTAssertEqual(button.value as? String, "pasteboard-exact")
            let reset = NSPredicate(format: "label == %@", label)
            expectation(for: reset, evaluatedWith: button)
            waitForExpectations(timeout: 5)
            app.terminate()
        }
    }
}
