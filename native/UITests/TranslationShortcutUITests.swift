import XCTest

final class TranslationShortcutUITests: XCTestCase {
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
        chip.tap()
        XCTAssertTrue(chip.isSelected)
        app.terminate(); app.launch()
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertFalse(chip.isSelected, "Selection must not be persisted")
        app.buttons["shortcut-manage"].tap()
        app.collectionViews.buttons[customTitle].tap()
        let edit = app.textViews["shortcut-instruction"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertEqual(edit.value as? String, "Use concise professional language.")
        edit.tap()
        edit.typeText(" Keep it short.")
        app.buttons["shortcut-save"].tap()
        app.collectionViews.buttons[customTitle].tap()
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
    func testPodcastAndStylesUseAllFiveInterfaceLanguages() {
        for (locale, translator, podcasts, library, heading) in [
            ("de", "Übersetzer", "Podcasts & Shadowing", "Mediathek", "Kurzbefehle"),
            ("en", "Translator", "Podcasts & shadowing", "Library", "Shortcuts"),
            ("ru", "Переводчик", "Подкасты и шэдоуинг", "Библиотека", "Шаблоны"),
            ("es", "Traductor", "Pódcasts y shadowing", "Biblioteca", "Atajos"),
            ("fr", "Traducteur", "Podcasts et shadowing", "Bibliothèque", "Raccourcis")
        ] {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "valid"
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
            app.launch()
            XCTAssertTrue(app.tabBars.buttons[translator].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts[heading].exists)
            app.tabBars.buttons[podcasts].tap()
            XCTAssertTrue(app.staticTexts[library].waitForExistence(timeout: 5))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "synthetic-session-podcast-\(locale)"
            shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }
}
