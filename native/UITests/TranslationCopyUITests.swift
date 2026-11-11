import XCTest

final class TranslationCopyUITests: XCTestCase {
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
