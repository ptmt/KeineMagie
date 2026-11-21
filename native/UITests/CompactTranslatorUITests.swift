import XCTest

final class CompactTranslatorUITests: XCTestCase {
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
    }
    @MainActor func testHeaderDirectionAllChoicesKeepsKeyboardDraft() {
        let app = launch("valid")
        let editor = app.textViews["translator-input"]
        let menu = app.buttons["translator-direction"]
        XCTAssertLessThanOrEqual(menu.frame.maxY, editor.frame.minY)
        editor.tap(); editor.typeText("Ich hat Zeit")
        for (raw, label) in [("ru-de", "Russian to German"), ("de-ru", "German to Russian"), ("de-de", "Polish German")] {
            menu.tap()
            let option = app.buttons["translator-direction-" + raw]
            XCTAssertTrue(option.waitForExistence(timeout: 3)); XCTAssertEqual(option.label, label)
            option.tap()
            XCTAssertEqual(menu.label, label)
            XCTAssertEqual(editor.value as? String, "Ich hat Zeit")
            XCTAssertTrue(app.keyboards.firstMatch.exists)
        }
        editor.typeText("!")
        XCTAssertEqual(editor.value as? String, "Ich hat Zeit!")
        XCTAssertFalse(app.buttons["translation-copy"].exists)
        record(app, "canvas-direction-keyboard")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(menu.label, "Polish German")
    }
    @MainActor func testCopySharesFirstTextRowAndRetainsOutputOnDirectionSwitch() {
        let app = launch()
        app.textViews["translator-input"].tap(); app.textViews["translator-input"].typeText("Anspruch")
        app.buttons["translator-submit"].tap()
        let copy = app.buttons["translation-copy"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: copy); waitForExpectations(timeout: 15)
        let text = app.staticTexts["translation-result-text"]
        XCTAssertTrue(text.exists)
        let output = app.otherElements["translation-output"]
        XCTAssertEqual(copy.frame.minY, output.frame.minY + 16, accuracy: 1)
        XCTAssertLessThanOrEqual(text.frame.maxX - 16, copy.frame.minX)
        let before = text.label
        app.buttons["translator-direction"].tap(); app.buttons["translator-direction-de-de"].tap()
        XCTAssertEqual(text.label, before)
    }
    @MainActor func testOtherTabToolbarsRemainReachable() {
        let app = launch("valid")
        app.tabBars.buttons["Podcasts"].tap()
        XCTAssertTrue(app.buttons["podcast-add"].exists)
        app.buttons["podcast-add"].tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.buttons["coach-profile"].exists)
        app.buttons["coach-profile"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor func testLocalizedHeaderDirectionAndAccessibility() {
        for locale in ["de", "en", "ru", "es", "fr"] {
            for large in [false, true] {
                let app = launch(locale: locale, large: large)
                let editor = app.textViews["translator-input"]
                editor.tap(); editor.typeText("Draft")
                XCTAssertTrue(app.keyboards.firstMatch.exists)
                let menu = app.buttons["translator-direction"]
                let settings = app.buttons["main-settings"]
                let titleLabel = ["de": "Übersetzer", "en": "Translator", "ru": "Переводчик", "es": "Traductor", "fr": "Traducteur"][locale]!
                let titles = app.navigationBars.staticTexts.matching(NSPredicate(format: "label == %@", titleLabel))
                let title = titles.firstMatch
                // UIButton's compact language label is also a StaticText child,
                // not a second navigation title.
                XCTAssertEqual(titles.count, 1)
                XCTAssertLessThanOrEqual(title.frame.maxX, menu.frame.minX)
                XCTAssertLessThanOrEqual(menu.frame.maxX, settings.frame.minX)
                XCTAssertEqual(menu.frame.midY, settings.frame.midY, accuracy: 1)
                XCTAssertGreaterThanOrEqual(menu.frame.width, 44)
                XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
                XCTAssertLessThanOrEqual(menu.frame.maxY, editor.frame.minY)
                menu.tap()
                record(app, "header-menu-\(locale)-\(large ? "AXXXXL" : "ordinary")")
                for raw in ["ru-de", "de-ru", "de-de"] { XCTAssertTrue(app.buttons["translator-direction-" + raw].exists) }
                app.buttons["translator-direction-de-ru"].tap()
                XCTAssertEqual(editor.value as? String, "Draft")
                XCTAssertTrue(app.keyboards.firstMatch.exists)
                for control in [menu, app.buttons["translator-submit"], app.buttons["translator-styles"]] {
                    XCTAssertGreaterThanOrEqual(control.frame.height, 44)
                    XCTAssertGreaterThanOrEqual(control.frame.minX, 0)
                    XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX)
                    XCTAssertLessThanOrEqual(control.frame.maxY, app.keyboards.firstMatch.frame.minY)
                }
                record(app, "canvas-\(locale)-\(large ? "AXXXXL" : "ordinary")-keyboard")
                app.buttons["main-settings"].tap()
                XCTAssertTrue(app.staticTexts["app-version-build"].waitForExistence(timeout: 5))
                app.terminate()
            }
        }
    }
}
