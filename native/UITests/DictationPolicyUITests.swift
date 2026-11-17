import XCTest

/// Pending simulator acceptance: uses the isolated cached-audio Go fixture only.
/// Captures must be exported and inspected; compilation is not visual acceptance.
final class DictationPolicyUITests: XCTestCase {
    @MainActor func testFocusedRussianLightAndDarkPolicyStates() throws {
        for theme in ["Light","Dark"] {
            let app=try launch(locale:"ru",theme:theme)
            let prepare=app.buttons["dictation-prepare"]
            XCTAssertTrue(prepare.waitForExistence(timeout:15))
            XCTAssertTrue(app.staticTexts["dictation-rules"].exists)
            XCTAssertFalse(app.buttons["dictation-pause"].exists)
            XCTAssertFalse(app.staticTexts["dictation-revealed"].exists)
            capture(app,"ru-\(theme)-unprepared")
            app.buttons["dictation-menu"].tap()
            XCTAssertTrue(app.buttons["dictation-reveal"].waitForExistence(timeout:3))
            capture(app,"ru-\(theme)-reveal-menu")
            app.tap() // Dismiss only: opening the menu must not reveal or prepare.
            XCTAssertFalse(app.staticTexts["dictation-revealed"].exists)
            prepare.tap()
            let play=app.buttons["dictation-play"]
            XCTAssertTrue(play.waitForExistence(timeout:60))
            waitEnabled(play)
            capture(app,"ru-\(theme)-ready")
            for count in 1...4 {
                play.tap()
                XCTAssertTrue(app.staticTexts["Запуски всего текста: \(count) из 4"].waitForExistence(timeout:15))
                if count == 1 {capture(app,"ru-\(theme)-play-requested-inspect-state")}
                waitForEndOrExhaustion(app)
                if count < 4 {waitEnabled(play)}
            }
            XCTAssertFalse(play.isEnabled)
            XCTAssertTrue(app.buttons["dictation-check"].exists)
            XCTAssertFalse(app.staticTexts["dictation-revealed"].exists)
            capture(app,"ru-\(theme)-exhausted")
            app.segmentedControls["dictation-mode"].buttons.element(boundBy:1).tap()
            capture(app,"ru-\(theme)-sentences")
            app.buttons["dictation-menu"].tap()
            app.buttons["dictation-reveal"].tap()
            XCTAssertFalse(app.staticTexts["dictation-revealed"].exists)
            let confirm=app.buttons["Показать оригинал"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout:3));confirm.tap()
            XCTAssertTrue(app.staticTexts["dictation-revealed"].waitForExistence(timeout:10))
            capture(app,"ru-\(theme)-original-explicit")
            app.buttons["dictation-menu"].tap()
            XCTAssertFalse(app.buttons["dictation-reveal"].exists)
            app.terminate()
        }
    }
    @MainActor func testContinuousSentencesStopBeforeExplicitFinalReading() throws {
        let app=try launch(locale:"en",theme:"Dark")
        let prepare=app.buttons["dictation-prepare"]
        XCTAssertTrue(prepare.waitForExistence(timeout:10));prepare.tap()
        let play=app.buttons["dictation-play"]
        XCTAssertTrue(play.waitForExistence(timeout:30));waitEnabled(play);play.tap()
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].waitForExistence(timeout:10))
        waitEnabled(play)
        app.segmentedControls["dictation-mode"].buttons.element(boundBy:1).tap()
        waitEnabled(play)
        play.tap() // Sentence and its repeat are continuous, with the real 3-second gap.
        expectation(for:NSPredicate(format:"label == %@ AND enabled == true","Optional final reading"),evaluatedWith:play)
        waitForExpectations(timeout:30)
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
        XCTAssertFalse(app.buttons["dictation-next"].exists)
        capture(app,"en-Dark-final-awaits-explicit-tap")
        play.tap()
        XCTAssertTrue(app.staticTexts["Whole-text starts: 2 of 4"].waitForExistence(timeout:10))
        expectation(for:NSPredicate(format:"label == %@ AND enabled == false","Optional final reading"),evaluatedWith:play)
        waitForExpectations(timeout:15)
        XCTAssertFalse(app.staticTexts["dictation-revealed"].exists)
        capture(app,"en-Dark-final-used-shared-limit")
    }
    @MainActor func testFiveLocaleRulesAndQuietAudioDetails() throws {
        for locale in ["de","en","ru","es","fr"] {
            let app=try launch(locale:locale,theme:"Dark")
            let rules=app.staticTexts["dictation-rules"]
            XCTAssertTrue(rules.waitForExistence(timeout:10))
            XCTAssertFalse(rules.label.contains("dictation.policy"))
            XCTAssertTrue(app.buttons["dictation-audio-info"].exists)
            XCTAssertTrue(app.buttons["dictation-check"].exists)
            XCTAssertFalse(app.staticTexts["dictation-revealed"].exists)
            capture(app,"\(locale)-Dark-rules-toolbar")
            app.terminate()
        }
    }
    @MainActor func testLargeTypeKeyboardAndCheckGeometry() throws {
        let app=try launch(locale:"en",theme:"Dark",large:true)
        let draft=app.textFields["dictation-draft"]
        XCTAssertTrue(draft.waitForExistence(timeout:15))
        app.swipeUp()
        draft.tap();draft.typeText("My draft stays here")
        let check=app.buttons["dictation-check"]
        XCTAssertGreaterThanOrEqual(check.frame.height,44)
        XCTAssertLessThanOrEqual(check.frame.maxY,draft.frame.minY)
        XCTAssertFalse(app.staticTexts["dictation-revealed"].exists)
        capture(app,"en-Dark-accessibility-keyboard")
        XCTAssertEqual(draft.value as? String,"My draft stays here")
        let keyboard=app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        let font=UIFont.preferredFont(forTextStyle:.body,compatibleWith:UITraitCollection(preferredContentSizeCategory:.accessibilityExtraExtraExtraLarge))
        let textHeight=("My draft stays here" as NSString).boundingRect(with:CGSize(width:draft.frame.width-24,height:1000),options:.usesLineFragmentOrigin,attributes:[.font:font],context:nil).height
        XCTAssertLessThanOrEqual(draft.frame.minY+12+ceil(textHeight),keyboard.frame.minY-8,"The complete typed fixture and caret must remain above the keyboard at maximum Dynamic Type")
    }
    @MainActor private func launch(locale:String,theme:String,large:Bool=false) throws -> XCUIApplication {
        let url=URL(fileURLWithPath:"/Users/tinyserve/.hermes/cache/scratch/dictation-final/fixture/fixture.json")
        guard let data=try? Data(contentsOf:url),let info=try JSONSerialization.jsonObject(with:data) as? [String:String],let token=info["native"] else {throw XCTSkip("Start isolated Go cached-audio fixture; never use production")}
        let app=XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"]="dictation-local"
        app.launchEnvironment["KM_DICTATION_UI_APPEARANCE"]=theme
        app.launchEnvironment["KM_DICTATION_FIXTURE_TOKEN"]=token
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"]=UUID().uuidString
        app.launchArguments=["-AppleLanguages","(\(locale))","-AppleLocale",locale,"-AppleInterfaceStyle",theme]
        if large {app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]}
        app.launch()
        let tabs=["de":"Diktat","en":"Dictation","ru":"Диктант","es":"Dictado","fr":"Dictée"]
        let tab=app.tabBars.buttons[tabs[locale]!]
        XCTAssertTrue(tab.waitForExistence(timeout:15));tab.tap()
        app.buttons["dictation-add"].tap()
        let title=app.textFields["dictation-title"];XCTAssertTrue(title.waitForExistence(timeout:5));title.tap();title.typeText("Ein Spaziergang im Park")
        let original=app.textViews["dictation-original"];original.tap();original.typeText("Heute scheint die Sonne.")
        app.buttons["dictation-create"].tap()
        return app
    }
    @MainActor private func waitEnabled(_ element:XCUIElement) {
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:element);waitForExpectations(timeout:40)
    }
    @MainActor private func waitForEndOrExhaustion(_ app:XCUIApplication) {
        // The final state is disabled by policy; wait for its listening label to leave.
        let play=app.buttons["dictation-play"]
        expectation(for:NSPredicate(format:"label != %@","Воспроизведение"),evaluatedWith:play);waitForExpectations(timeout:40)
    }
    @MainActor private func capture(_ app:XCUIApplication,_ name:String) {
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
}
