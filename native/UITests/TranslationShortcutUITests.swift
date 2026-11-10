import XCTest

final class TranslationShortcutUITests: XCTestCase {
    @MainActor
    func testCompactTranslatorKeepsStylesAndSubmitAboveKeyboard() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "valid"
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        let editor = app.textViews["translator-input"]
        let friendly = app.buttons["Freundlich"]
        let addShortcut = app.buttons["shortcut-add"]
        let submit = app.buttons["translator-submit"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(friendly.isHittable)
        XCTAssertTrue(addShortcut.isHittable)
        XCTAssertLessThan(editor.frame.maxY, friendly.frame.minY)
        XCTAssertLessThan(friendly.frame.maxY, submit.frame.minY)
        XCTAssertFalse(app.staticTexts["Kurzbefehle"].exists)
        XCTAssertTrue(app.navigationBars.staticTexts["Übersetzer"].exists)
        let normal = XCTAttachment(screenshot: app.screenshot())
        normal.name = "synthetic-session-compact-translator-no-keyboard"
        normal.lifetime = .keepAlways; add(normal)
        editor.tap()
        editor.typeText("Guten Morgen")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        friendly.tap()
        XCTAssertTrue(friendly.isSelected)
        XCTAssertTrue(addShortcut.isHittable)
        XCTAssertTrue(submit.exists)
        XCTAssertLessThan(editor.frame.maxY, friendly.frame.minY)
        XCTAssertLessThan(friendly.frame.maxY, submit.frame.minY)
        XCTAssertLessThan(submit.frame.maxY, app.keyboards.firstMatch.frame.minY)
        let keyboard = XCTAttachment(screenshot: app.screenshot())
        keyboard.name = "synthetic-session-compact-translator-keyboard"
        keyboard.lifetime = .keepAlways; add(keyboard)
    }

    @MainActor
    func testTabsAndCustomShortcutEditingPersistence() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "valid"
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Übersetzer"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Diktat"].tap()
        XCTAssertTrue(app.staticTexts["Noch nicht verfügbar"].exists)
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Noch nicht verfügbar"].exists)
        app.tabBars.buttons["Übersetzer"].tap()
        app.buttons["shortcut-add"].tap()
        let customTitle = "Work \(UUID().uuidString.prefix(6))"
        let title = app.textFields["shortcut-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText(customTitle)
        let instruction = app.textViews["shortcut-instruction"]
        instruction.tap(); instruction.typeText("Use concise professional language.")
        app.buttons["shortcut-save"].tap()
        let chip = app.buttons[customTitle]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        let chips = app.scrollViews.containing(.button, identifier: "Freundlich").firstMatch
        for _ in 0..<10 where !chip.isHittable { chips.swipeLeft() }
        chip.tap()
        XCTAssertTrue(chip.isSelected)
        app.terminate(); app.launch()
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertFalse(chip.isSelected, "Selection must not be persisted")
        app.buttons["shortcut-manage"].tap()
        app.collectionViews.buttons.matching(identifier: customTitle).allElementsBoundByIndex.first(where: { $0.isHittable })!.tap()
        let edit = app.textViews["shortcut-instruction"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertEqual(edit.value as? String, "Use concise professional language.")
        edit.tap()
        edit.typeText(" Keep it short.")
        app.buttons["shortcut-save"].tap()
        app.collectionViews.buttons.matching(identifier: customTitle).allElementsBoundByIndex.first(where: { $0.isHittable })!.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue((edit.value as? String)?.contains("Keep it short.") == true)
        app.buttons["shortcut-delete"].tap()
        app.buttons["shortcut-done"].tap()
        XCTAssertFalse(chip.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "synthetic-session-translator-shortcuts"
        shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testTranslatorStylesUseAllFiveInterfaceLanguages() {
        for (locale, translator, friendly, formal, heading) in [
            ("de", "Übersetzer", "Freundlich", "Formell", "Kurzbefehle"),
            ("en", "Translator", "Friendly", "Formal", "Shortcuts"),
            ("ru", "Переводчик", "Дружелюбно", "Официально", "Шаблоны"),
            ("es", "Traductor", "Amable", "Formal", "Atajos"),
            ("fr", "Traducteur", "Amical", "Formel", "Raccourcis")
        ] {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "valid"
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
            app.launch()
            XCTAssertTrue(app.tabBars.buttons[translator].waitForExistence(timeout: 10))
            XCTAssertTrue(app.navigationBars.staticTexts[translator].exists)
            XCTAssertTrue(app.buttons[friendly].isHittable)
            XCTAssertTrue(app.buttons[formal].isHittable)
            XCTAssertTrue(app.buttons["shortcut-add"].isHittable)
            XCTAssertFalse(app.staticTexts[heading].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "synthetic-session-compact-translator-\(locale)"
            shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }
}
