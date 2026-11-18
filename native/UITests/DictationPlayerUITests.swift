import XCTest
import AVFoundation

/// Run only with Fixtures/generate_dictation_player_wav.py and the existing Go
/// local fixture. These are interaction/geometry tests, not screenshot acceptance.
final class DictationPlayerUITests: XCTestCase {
    @MainActor func testNativeBackSwipeDraftAndTabIsolation() throws {
        let app = try launch()
        let draft = app.textFields["dictation-draft"]
        draft.tap(); draft.typeText("A preserved draft")
        let footer = app.otherElements["dictation-player"]
        XCTAssertTrue(footer.exists)
        XCTAssertEqual(app.navigationBars.count, 1)
        XCTAssertFalse(app.buttons["History"].exists)
        XCTAssertTrue(app.sliders.count == 0)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        XCTAssertLessThanOrEqual(footer.frame.maxY, keyboard.frame.minY + 1)
        capture(app,"player-normal-keyboard")
        XCTAssertGreaterThanOrEqual(app.buttons["dictation-prepare"].frame.height + 0.001, 44)
        app.navigationBars.buttons.element(boundBy: 0).tap() // The system Back item.
        XCTAssertTrue(app.buttons["dictation-row"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(footer.exists)
        app.buttons["dictation-row"].firstMatch.tap()
        XCTAssertEqual(draft.value as? String, "A preserved draft")
        // Dismiss the keyboard before exercising the persistent system tab bar.
        app.swipeDown()
        for tab in ["Translator", "Podcasts", "Coach"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertFalse(footer.exists)
            XCTAssertFalse(app.buttons["dictation-play"].exists)
            XCTAssertFalse(app.buttons["dictation-prepare"].exists)
            XCTAssertEqual(app.navigationBars.count, 1)
        }
        app.tabBars.buttons["Dictation"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "A preserved draft")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45)))
        XCTAssertTrue(app.buttons["dictation-row"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(footer.exists)
    }

    @MainActor func testDecodedWAVClockSequenceAndExplicitFinal() throws {
        let app = try launch()
        let remaining = app.staticTexts["dictation-remaining"]
        XCTAssertEqual(remaining.value as? String, "—", "No duration before real cached bytes")
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

    @MainActor func testActiveWAVStopsOffTabAndContinuesWithoutAnotherStart() async throws {
        let app = try launch()
        app.buttons["dictation-prepare"].tap()
        let play = app.buttons["dictation-play"]
        wait(play, "enabled == true")
        play.tap()
        wait(app.staticTexts["dictation-elapsed"], "value == '0:01'")
        app.tabBars.buttons["Translator"].tap()
        XCTAssertFalse(app.otherElements["dictation-player"].exists)
        try await Task.sleep(for: .seconds(2))
        app.tabBars.buttons["Dictation"].tap()
        wait(play, "label == 'Continue' AND enabled == true")
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
        let frozen = app.staticTexts["dictation-elapsed"].value as? String
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(app.staticTexts["dictation-elapsed"].value as? String, frozen)
        capture(app,"player-interrupted-count-preserved")
        play.tap()
        wait(app.staticTexts["dictation-remaining"], "value == '0:00'")
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
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

    @MainActor private func launch() throws -> XCUIApplication {
        let root = URL(fileURLWithPath: "/Users/tinyserve/.hermes/cache/scratch/dictation-camera-player")
        guard let data = try? Data(contentsOf: root.appendingPathComponent("fixture/fixture.json")),
              let info = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let token = info["native"] else { throw XCTSkip("Start the isolated generated-WAV fixture described in Fixtures/generate_dictation_player_wav.py") }
        let duration = try AVAudioPlayer(contentsOf: root.appendingPathComponent("clock-fixture.wav")).duration
        XCTAssertEqual(duration, 8, accuracy: 0.001)
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "dictation-local"
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
