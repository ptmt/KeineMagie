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
        for id in ["translator-input", "translator-submit", "translation-output", "translation-copy", "translation-result-text", "translator-direction"] {
            let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
            if element.exists { print("COMPACT_GEOMETRY \(name) \(id) \(element.frame)") }
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    @MainActor func testResultBaselineGeometry() {
        let app = launch()
        let editor = app.textViews["translator-input"]
        editor.tap(); editor.typeText("Anspruch")
        app.buttons["translator-submit"].tap()
        let copy = app.buttons["translation-copy"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: copy); waitForExpectations(timeout: 15)
        record(app, "compact-result")
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        record(app, "compact-result-keyboard")
    }
    @MainActor func testHeaderDirectionAllChoicesKeepsKeyboardDraftAndNoSelectorRow() {
        let app = launch("valid")
        let editor = app.textViews["translator-input"]
        let menu = app.buttons["translator-direction"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Direction belongs in the parent navigation toolbar")
        guard menu.exists else { return }
        XCTAssertFalse(app.segmentedControls["translator-direction"].exists)
        XCTAssertGreaterThanOrEqual(menu.frame.width, 44)
        // iOS 27 reports the 36pt visual capsule; exercise the 44pt hit region.
        for dy in [-21.0, 21.0] {
            menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: dy)).tap()
            XCTAssertTrue(app.buttons["translator-direction-ru-de"].waitForExistence(timeout: 3))
            app.buttons["translator-direction-ru-de"].tap()
        }
        XCTAssertLessThan(menu.frame.maxY, editor.frame.minY)
        let title = app.navigationBars.staticTexts["Translator"].firstMatch
        XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: 1)
        let settings = app.buttons["Settings"]
        XCTAssertLessThanOrEqual(menu.frame.maxX, settings.frame.minX)
        editor.tap(); editor.typeText("Ich hat Zeit")
        for (raw, label) in [("ru-de", "Russian to German"), ("de-ru", "German to Russian"), ("de-de", "Polish German")] {
            menu.tap()
            let option = app.buttons["translator-direction-" + raw]
            XCTAssertTrue(option.waitForExistence(timeout: 3)); XCTAssertEqual(option.label, label)
            option.tap()
            XCTAssertEqual(menu.label, label)
            XCTAssertEqual(editor.value as? String, "Ich hat Zeit")
            XCTAssertTrue(app.keyboards.firstMatch.exists, "Direction switching must not dismiss editing")
        }
        editor.typeText("!")
        XCTAssertEqual(editor.value as? String, "Ich hat Zeit!")
        XCTAssertFalse(app.buttons["translation-copy"].exists, "Changing direction must not translate")
        record(app, "compact-header-keyboard")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(menu.label, "Polish German")
    }
    @MainActor func testCopySharesFirstTextRowReservesLaneAndRetainsOutputOnDirectionSwitch() {
        let app = launch()
        app.textViews["translator-input"].tap(); app.textViews["translator-input"].typeText("Anspruch")
        app.buttons["translator-submit"].tap()
        let copy = app.buttons["translation-copy"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: copy); waitForExpectations(timeout: 15)
        let text = app.staticTexts["translation-result-text"]
        XCTAssertTrue(text.exists)
        guard text.exists else { return }
        // SwiftUI selectable Text reports its material container's padded AX bounds.
        let output = app.otherElements["translation-output"]
        XCTAssertEqual(copy.frame.minY, output.frame.minY + 16, accuracy: 1)
        // Selectable Text AX adds horizontal padding; glyphs must retain the 8pt gap.
        XCTAssertLessThanOrEqual(text.frame.maxX - 16, copy.frame.minX)
        let before = text.label
        app.buttons["translator-direction"].tap(); app.buttons["translator-direction-de-de"].tap()
        XCTAssertEqual(text.label, before, "Explicit direction choice preserves the existing result")
        record(app, "compact-inline-copy")
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
        app.swipeDown()
        XCTAssertTrue(app.buttons["Settings"].exists)
    }
    @MainActor private func assertHeader(_ app: XCUIApplication, locale: String, large: Bool) {
        let titles = ["de":"Übersetzer", "en":"Translator", "ru":"Переводчик", "es":"Traductor", "fr":"Traducteur"]
        let title = app.navigationBars.staticTexts[titles[locale]!].firstMatch
        let menu = app.buttons["translator-direction"]
        let settings = app.buttons["main-settings"]
        XCTAssertEqual(app.navigationBars.staticTexts.matching(identifier: titles[locale]!).count, 1, "Only one visible title")
        XCTAssertTrue(title.exists)
        XCTAssertTrue(menu.isHittable)
        XCTAssertTrue(settings.isHittable)
        guard title.exists, menu.exists, settings.exists else { return }
        for control in [menu, settings] {
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX)
        }
        XCTAssertLessThanOrEqual(title.frame.maxX, menu.frame.minX, "Title must not overlap direction")
        XCTAssertLessThanOrEqual(menu.frame.maxX, settings.frame.minX, "Direction is immediately left of Settings")
        XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX)
        if !large { XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: 1) }
        print("HEADER \(locale) large=\(large) title=\(title.frame) menu=\(menu.frame) settings=\(settings.frame)")
    }
    @MainActor func testLocalizedHeaderDarkAndAccessibility() {
        for locale in ["de", "en", "ru", "es", "fr"] {
            for large in [false, true] {
                let app = launch(locale: locale, large: large)
                assertHeader(app, locale: locale, large: large)
                let editor = app.textViews["translator-input"]
                editor.tap(); editor.typeText("Draft")
                XCTAssertTrue(app.keyboards.firstMatch.exists)
                let menu = app.buttons["translator-direction"]
                menu.tap()
                for raw in ["ru-de", "de-ru", "de-de"] { XCTAssertTrue(app.buttons["translator-direction-" + raw].exists) }
                app.buttons["translator-direction-de-ru"].tap()
                assertHeader(app, locale: locale, large: large)
                XCTAssertEqual(editor.value as? String, "Draft")
                XCTAssertTrue(app.keyboards.firstMatch.exists)
                record(app, "compact-header-\(locale)-\(large ? "AXXXXL" : "ordinary")-keyboard")
                app.buttons["main-settings"].tap()
                XCTAssertTrue(app.staticTexts["app-version-build"].waitForExistence(timeout: 5), "Gear must actually open Settings")
                app.terminate()
            }
        }
    }
}
