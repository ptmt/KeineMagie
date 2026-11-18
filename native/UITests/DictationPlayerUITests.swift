import XCTest
import AVFoundation

/// Run only with Fixtures/generate_dictation_player_wav.py and the existing Go
/// local fixture. These are interaction/geometry tests, not screenshot acceptance.
final class DictationPlayerUITests: XCTestCase {
    @MainActor func testNativeBackSwipeDraftAndGlobalAccessory() throws {
        let app = try launch()
        app.buttons["dictation-prepare"].tap()
        wait(app.buttons["dictation-play"], "enabled == true")
        let draft = app.textFields["dictation-draft"]
        draft.tap(); draft.typeText("A preserved draft")
        let footer = app.otherElements["dictation-player"]
        XCTAssertEqual(app.navigationBars.count, 1)
        XCTAssertFalse(app.buttons["History"].exists)
        XCTAssertTrue(app.sliders.count == 0)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        if footer.exists && footer.isHittable { XCTAssertLessThanOrEqual(footer.frame.maxY, keyboard.frame.minY + 1) }
        capture(app,"player-normal-keyboard")
        // The system accessory may hide with the keyboard, just like its tab bar.
        app.navigationBars.buttons.element(boundBy: 0).tap() // The system Back item.
        XCTAssertTrue(app.buttons["dictation-row"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(footer.exists)
        app.buttons["dictation-row"].firstMatch.tap()
        XCTAssertEqual(draft.value as? String, "A preserved draft")
        // Dismiss the keyboard before exercising the persistent system tab bar.
        app.swipeDown()
        for tab in ["Translator", "Podcasts", "Coach"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(footer.exists)
            XCTAssertTrue(app.buttons["dictation-play"].exists)
            XCTAssertFalse(app.buttons["dictation-prepare"].exists)
            XCTAssertEqual(app.navigationBars.count, 1)
        }
        app.tabBars.buttons["Dictation"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "A preserved draft")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45)))
        XCTAssertTrue(app.buttons["dictation-row"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(footer.exists)
    }

    @MainActor func testDecodedWAVClockSequenceAndExplicitFinal() throws {
        let app = try launch()
        let remaining = app.staticTexts["dictation-remaining"]
        XCTAssertFalse(app.otherElements["dictation-player"].exists, "No permanent empty accessory before explicit preparation")
        XCTAssertTrue(app.buttons["dictation-audio-info"].exists, "Cost/details remain available before explicit preparation")
        app.buttons["dictation-prepare"].tap()
        let play = app.buttons["dictation-play"]
        wait(play, "enabled == true")
        wait(remaining, "value == '0:08'")
        play.tap()
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].waitForExistence(timeout: 10))
        wait(app.staticTexts["dictation-elapsed"], "value != '0:00'")
        XCTAssertNotEqual(remaining.value as? String,"0:08")
        capture(app,"player-real-elapsed-remaining-advancing")
        wait(remaining, "value == '0:00'")
        XCTAssertEqual(app.staticTexts["dictation-elapsed"].value as? String, "0:08")
        XCTAssertFalse(app.buttons["dictation-pause"].exists)
        app.segmentedControls["dictation-mode"].buttons["By sentences"].tap()
        wait(play, "enabled == true")
        wait(remaining, "value == '0:19'") // 8 + real 3-second gap + 8-second repeat.
        play.tap()
        wait(play, "label == 'Optional final reading' AND enabled == true")
        XCTAssertEqual(remaining.value as? String, "0:00")
        XCTAssertEqual(app.staticTexts["dictation-elapsed"].value as? String, "0:19")
        capture(app,"player-sentences-natural-end-including-gap")
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
        play.tap()
        XCTAssertTrue(app.staticTexts["Whole-text starts: 2 of 4"].waitForExistence(timeout: 5))
        wait(play, "label == 'Optional final reading' AND enabled == false")
        XCTAssertEqual(app.staticTexts["dictation-elapsed"].value as? String, "0:08")
    }

    @MainActor func testActiveWAVPlaysAcrossAllTabsAndReturnsToExactAttempt() async throws {
        let app = try launch()
        let title = app.navigationBars.firstMatch.identifier
        app.buttons["dictation-prepare"].tap()
        let play = app.buttons["dictation-play"]
        wait(play, "enabled == true")
        play.tap()
        wait(app.staticTexts["dictation-elapsed"], "value == '0:01'")
        capture(app,"global-dictation-playing")
        app.tabBars.buttons["Translator"].tap()
        XCTAssertTrue(app.otherElements["dictation-player"].exists)
        let elapsed = app.staticTexts["dictation-elapsed"]
        let before = elapsed.value as? String
        try await Task.sleep(for: .seconds(1))
        XCTAssertNotEqual(elapsed.value as? String, before)
        XCTAssertFalse(play.isEnabled)
        capture(app,"global-translator-playing")
        for tab in ["Podcasts", "Coach"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.otherElements["dictation-player"].exists)
            XCTAssertTrue(app.buttons["dictation-player-open"].exists)
            capture(app,"global-" + tab.lowercased())
        }
        app.buttons["dictation-player-open"].tap()
        XCTAssertTrue(app.textFields["dictation-draft"].waitForExistence(timeout:5))
        XCTAssertEqual(app.navigationBars.firstMatch.identifier,title)
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
        wait(app.staticTexts["dictation-remaining"], "value == '0:00'")
        XCTAssertEqual(elapsed.value as? String,"0:08")
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
    }

    @MainActor func testGlobalAccessoryLightDarkSequenceAndSeparateControl() throws {
        for theme in ["Light", "Dark"] {
            let app = try launch(theme:theme)
            let title = app.navigationBars.firstMatch.identifier
            app.segmentedControls["dictation-mode"].buttons["By sentences"].tap()
            app.buttons["dictation-prepare"].tap()
            let play = app.buttons["dictation-play"]
            wait(play,"enabled == true")
            let draft = app.textFields["dictation-draft"]
            draft.tap(); draft.typeText("Exact attempt draft")
            // Standard Back dismisses the editor/keyboard. Never tap an AX-only
            // offscreen tab at {-1,-1} while the native keyboard hides the tab bar.
            app.navigationBars.buttons.element(boundBy:0).tap()
            wait(app.tabBars.buttons["Translator"],"hittable == true")
            app.tabBars.buttons["Translator"].tap()
            XCTAssertGreaterThanOrEqual(play.frame.height,44)
            XCTAssertGreaterThanOrEqual(play.frame.width,44)
            play.tap() // Transport never selects Dictation or opens a destination.
            XCTAssertTrue(app.tabBars.buttons["Translator"].isSelected)
            let elapsed = app.staticTexts["dictation-elapsed"]
            wait(elapsed,"value != '0:00'")
            capture(app,"global-\(theme)-translator-playing")
            for tab in ["Podcasts", "Coach", "Dictation"] {
                let before = elapsed.value as? String
                app.tabBars.buttons[tab].tap()
                if tab == "Dictation" { app.buttons["dictation-player-open"].tap() }
                XCTAssertTrue(app.otherElements["dictation-player"].exists)
                XCTAssertNotEqual(elapsed.value as? String,before,"The single clock keeps advancing across tabs")
                XCTAssertFalse(play.isEnabled,"No pause UI; the sequence is still active")
                capture(app,"global-\(theme)-\(tab.lowercased())-playing")
            }
            XCTAssertEqual(draft.value as? String,"Exact attempt draft")
            app.navigationBars.buttons.element(boundBy:0).tap()
            XCTAssertTrue(app.buttons["dictation-row"].firstMatch.waitForExistence(timeout:5))
            app.tabBars.buttons["Coach"].tap()
            app.buttons["dictation-player-open"].tap()
            XCTAssertEqual(app.navigationBars.firstMatch.identifier,title)
            XCTAssertEqual(draft.value as? String,"Exact attempt draft")
            XCTAssertTrue(app.staticTexts["Whole-text starts: 0 of 4"].exists)
            wait(app.staticTexts["dictation-remaining"],"value == '0:00'")
            XCTAssertEqual(elapsed.value as? String,"0:19")
            wait(play,"label == 'Optional final reading' AND enabled == true")
            app.terminate()
        }
    }

    @MainActor func testBackgroundStillInterruptsAndContinuePreservesCountFromAnotherTab() async throws {
        let app = try launch()
        app.buttons["dictation-prepare"].tap()
        let play = app.buttons["dictation-play"]
        wait(play,"enabled == true")
        app.tabBars.buttons["Translator"].tap()
        play.tap()
        wait(app.staticTexts["dictation-elapsed"],"value == '0:01'")
        XCUIDevice.shared.press(.home)
        try await Task.sleep(for:.seconds(1))
        app.activate()
        wait(play,"label == 'Continue' AND enabled == true")
        let frozen = app.staticTexts["dictation-elapsed"].value as? String
        try await Task.sleep(for:.seconds(1))
        XCTAssertEqual(app.staticTexts["dictation-elapsed"].value as? String,frozen)
        play.tap()
        XCTAssertTrue(app.tabBars.buttons["Translator"].isSelected)
        app.buttons["dictation-player-open"].tap()
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
        wait(app.staticTexts["dictation-remaining"],"value == '0:00'")
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
    }

    @MainActor func testSystemReduceTransparencyGlobalAccessory() throws {
        let settings = XCUIApplication(bundleIdentifier:"com.apple.Preferences")
        settings.launchArguments = ["-AppleLanguages","(en)","-AppleLocale","en_US"]
        settings.launch()
        let accessibility = settings.staticTexts["Accessibility"].firstMatch
        for _ in 0..<6 {
            if accessibility.exists && accessibility.isHittable { break }
            settings.swipeUp()
        }
        XCTAssertTrue(accessibility.isHittable); accessibility.tap()
        let display = settings.staticTexts["Display & Text Size"].firstMatch
        XCTAssertTrue(display.waitForExistence(timeout:5)); display.tap()
        let transparency = settings.switches["Reduce Transparency"].firstMatch
        for _ in 0..<4 {
            if transparency.exists && transparency.isHittable { break }
            settings.swipeUp()
        }
        XCTAssertTrue(transparency.isHittable)
        let wasOn = transparency.value as? String == "1"
        if !wasOn { transparency.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap() }
        wait(transparency,"value == '1'")
        capture(settings,"system-reduce-transparency-enabled")
        defer {
            if !wasOn {
                settings.activate()
                if transparency.value as? String == "1" { transparency.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap() }
                wait(transparency,"value == '0'")
            }
            settings.terminate()
        }
        let app = try launch(theme:"Dark")
        app.buttons["dictation-prepare"].tap()
        wait(app.buttons["dictation-play"],"enabled == true")
        for tab in ["Dictation","Translator","Coach"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.otherElements["dictation-player"].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons["dictation-play"].frame.height,44)
            capture(app,"global-reduce-transparency-" + tab.lowercased())
        }
        app.terminate()
    }

    @MainActor func testOwnerLogoutRemovesAttemptStackAndPlayer() throws {
        let app = try launch()
        app.tabBars.buttons["Translator"].tap()
        app.buttons["main-settings"].tap()
        app.buttons["ChatGPT"].tap()
        let logout = app.buttons["Sign out"]
        XCTAssertTrue(logout.waitForExistence(timeout: 5)); logout.tap()
        wait(app.tabBars.firstMatch, "exists == false")
        XCTAssertFalse(app.otherElements["dictation-player"].exists)
        XCTAssertFalse(app.textFields["dictation-draft"].exists)
        XCTAssertFalse(app.buttons["dictation-row"].exists)
    }

    @MainActor private func launch(theme: String = "Light") throws -> XCUIApplication {
        let root = URL(fileURLWithPath: "/Users/tinyserve/.hermes/cache/scratch/dictation-camera-player")
        guard let data = try? Data(contentsOf: root.appendingPathComponent("fixture/fixture.json")),
              let info = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let token = info["native"] else { throw XCTSkip("Start the isolated generated-WAV fixture described in Fixtures/generate_dictation_player_wav.py") }
        let duration = try AVAudioPlayer(contentsOf: root.appendingPathComponent("clock-fixture.wav")).duration
        XCTAssertEqual(duration, 8, accuracy: 0.001)
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "dictation-local"
        app.launchEnvironment["KM_DICTATION_UI_APPEARANCE"] = theme
        app.launchEnvironment["KM_DICTATION_FIXTURE_TOKEN"] = token
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Dictation"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Dictation"].tap()
        app.buttons["dictation-add"].tap()
        let title = app.textFields["dictation-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Player " + UUID().uuidString.prefix(6))
        let original = app.textViews["dictation-original"]
        original.tap(); original.typeText("Heute scheint die Sonne.")
        app.buttons["dictation-create"].tap()
        XCTAssertTrue(app.buttons["dictation-prepare"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func wait(_ element: XCUIElement, _ predicate: String) {
        expectation(for: NSPredicate(format: predicate), evaluatedWith: element)
        waitForExpectations(timeout: 25)
    }
    @MainActor private func capture(_ app:XCUIApplication,_ name:String) {
        let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
}
