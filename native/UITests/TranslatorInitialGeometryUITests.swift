import XCTest

final class TranslatorInitialGeometryUITests: XCTestCase {
    private let historyLabels = ["en":"Your history", "de":"Dein Verlauf", "ru":"Ваша история", "es":"Tu historial", "fr":"Votre historique"]
    @MainActor private func launch(_ mode: String, locale: String, namespace: String = UUID().uuidString) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = mode
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = namespace
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
        app.launch()
        XCTAssertTrue(app.textViews["translator-input"].waitForExistence(timeout: 8))
        return app
    }
    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String, locale: String) -> [String:CGRect] {
        var result: [String:CGRect] = [:]
        for id in ["translator-input", "translator-submit", "history-row-synthetic-history-1"] {
            let element = app.descendants(matching: .any).matching(identifier:id).firstMatch
            if element.exists { result[id] = element.frame }
        }
        let header = app.staticTexts[historyLabels[locale]!]
        XCTAssertTrue(header.exists, "History header must remain present")
        if header.exists { result["history"] = header.frame }
        let form = app.cells.containing(.button, identifier:"translator-submit").firstMatch
        if form.exists { result["form"] = form.frame }
        print("GEOMETRY \(name) \(result)")
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name=name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string:app.debugDescription); tree.name=name+"-tree"; tree.lifetime = .keepAlways; add(tree)
        return result
    }
    private func same(_ a:[String:CGRect], _ b:[String:CGRect], file: StaticString = #filePath, line: UInt = #line) {
        for (key, before) in a {
            guard let after = b[key] else { XCTFail("Missing \(key)",file:file,line:line);continue }
            XCTAssertEqual(before.minY,after.minY,accuracy:0.6,"\(key) y",file:file,line:line)
            XCTAssertEqual(before.height,after.height,accuracy:0.6,"\(key) height",file:file,line:line)
        }
    }
    @MainActor func testProviderSettlementFiveLocalesAndKeyboardNavigation() {
        for locale in ["de","en","ru","es","fr"] {
            let app = launch("translation-geometry",locale:locale)
            let before = snapshot(app,"provider-pending-"+locale,locale:locale)
            Thread.sleep(forTimeInterval:13)
            same(before,snapshot(app,"provider-ready-"+locale,locale:locale))
            let editor=app.textViews["translator-input"];editor.tap();editor.typeText("Synthetic geometry draft")
            same(before,snapshot(app,"keyboard-"+locale,locale:locale))
            app.tabBars.buttons.element(boundBy:3).tap();app.tabBars.buttons.element(boundBy:0).tap()
            same(before,snapshot(app,"navigation-"+locale,locale:locale))
            XCTAssertEqual(editor.value as? String,"Synthetic geometry draft")
            app.terminate()
        }
    }
    @MainActor func testProviderErrorDoesNotMoveForm() {
        let app=launch("translation-geometry-error",locale:"en")
        let before=snapshot(app,"provider-error-pending",locale:"en")
        Thread.sleep(forTimeInterval:13)
        same(before,snapshot(app,"provider-error-settled",locale:"en"))
        app.buttons["Settings"].tap()
        app.buttons["ChatGPT"].tap()
        XCTAssertTrue(app.staticTexts["provider-diagnostic"].waitForExistence(timeout:5))
    }
    @MainActor func testCachedHistoryFailureBelowRowsFiveLocales() {
        for locale in ["de","en","ru","es","fr"] {
            let ns=UUID().uuidString
            let app=launch("cache-populated",locale:locale,namespace:ns)
            XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"history-row-synthetic-history-1").firstMatch.waitForExistence(timeout:8))
            app.terminate();app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"]="cache-delayed-error";app.launch()
            XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"history-row-synthetic-history-1").firstMatch.waitForExistence(timeout:8))
            let before=snapshot(app,"cached-pending-"+locale,locale:locale)
            Thread.sleep(forTimeInterval:11)
            same(before,snapshot(app,"cached-error-"+locale,locale:locale))
            // List virtualizes rows below the viewport; reveal the trailing error
            // only AFTER checking unchanged first-row/form geometry.
            for _ in 0..<15 {
                if app.buttons["history-retry"].isHittable { break }
                app.swipeUp()
            }
            XCTAssertEqual(app.staticTexts.matching(identifier:"history-load-error").count,1)
            XCTAssertTrue(app.buttons["history-retry"].isHittable)
            let shot = XCTAttachment(screenshot:app.screenshot()); shot.name="history-actionable-error-"+locale;shot.lifetime = .keepAlways;add(shot)
            app.terminate()
        }
    }
    @MainActor func testQuietOutboxDoesNotDisplaceHistoryOnRestore() {
        let app=launch("translation-outbox-offline",locale:"en")
        let before=snapshot(app,"outbox-before",locale:"en")
        app.textViews["translator-input"].tap();app.textViews["translator-input"].typeText("Synthetic saved draft")
        app.buttons["translator-submit"].tap()
        XCTAssertTrue(app.buttons["translation-pending"].waitForExistence(timeout:5))
        same(before,snapshot(app,"outbox-after",locale:"en"))
        app.terminate();app.launch();XCTAssertTrue(app.textViews["translator-input"].waitForExistence(timeout:8))
        same(before,snapshot(app,"outbox-restored",locale:"en"))
        XCTAssertEqual(app.textViews["translator-input"].value as? String,"Synthetic saved draft")
        app.buttons["translation-pending"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic saved draft"].waitForExistence(timeout:5))
    }
}
