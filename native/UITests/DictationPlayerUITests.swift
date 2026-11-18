import XCTest
import AVFoundation
import UIKit

/// Run only with Fixtures/generate_dictation_player_wav.py and the existing Go
/// local fixture. These are interaction/geometry tests, not screenshot acceptance.
final class DictationPlayerUITests: XCTestCase {
    @MainActor func testPreparationReadinessAcrossFreshAttempts() throws {
        // Exercise the quick no-op save while a new navigation destination is
        // installed. Its controls must observe save completion, without a tab
        // switch or an unrelated render to make them ready.
        for _ in 0..<8 {
            let app=try launch()
            XCTAssertTrue(app.buttons["dictation-prepare"].isEnabled)
            app.terminate()
        }
    }

    @MainActor func testExplicitStopFromAnotherTabRestartsAtZero() async throws {
        for theme in ["Light", "Dark"] {
            let app=try launch(theme:theme)
            let title=app.navigationBars.firstMatch.identifier
            app.buttons["dictation-prepare"].tap()
            let transport=app.buttons["dictation-play"]
            wait(transport,"enabled == true")
            app.tabBars.buttons["Translator"].tap()
            capture(app,"stop-\(theme)-ready")
            transport.tap()
            waitClock(app,"0:02")
            XCTAssertEqual(app.buttons["dictation-player-open"].value as? String,"Playing")
            XCTAssertEqual(transport.label,"Stop and return to beginning")
            capture(app,"stop-\(theme)-playing")
            transport.tap()
            waitClock(app,"0:00")
            XCTAssertEqual(app.buttons["dictation-player-open"].value as? String,"Stopped")
            XCTAssertTrue(app.tabBars.buttons["Translator"].isSelected)
            capture(app,"stop-\(theme)-stopped")
            try await Task.sleep(for:.seconds(1))
            XCTAssertEqual(clock(app),"0:00")
            transport.tap()
            waitClock(app,"0:01")
            app.buttons["dictation-player-open"].tap()
            XCTAssertEqual(app.navigationBars.firstMatch.identifier,title)
            XCTAssertTrue(app.staticTexts["Whole-text starts: 2 of 4"].waitForExistence(timeout:5))
            transport.tap();waitClock(app,"0:00")
            app.terminate()
        }
    }

    @MainActor func testStopDuringDelayedAdmissionNeverPlaysLate() async throws {
        let app=try launch(admissionDelay:true)
        app.buttons["dictation-prepare"].tap()
        let transport=app.buttons["dictation-play"]
        wait(transport,"enabled == true")
        app.tabBars.buttons["Coach"].tap();transport.tap()
        wait(app.buttons["dictation-player-open"],"value == 'Loading…'")
        XCTAssertEqual(transport.label,"Stop and return to beginning")
        capture(app,"stop-loading-real-admission-no-waveform")
        transport.tap();waitClock(app,"0:00")
        try await Task.sleep(for:.seconds(7))
        XCTAssertEqual(clock(app),"0:00")
        XCTAssertEqual(app.buttons["dictation-player-open"].value as? String,"Stopped")
        capture(app,"stop-after-late-admission-still-silent")
        app.buttons["dictation-player-open"].tap()
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].waitForExistence(timeout:5))
        transport.tap();waitClock(app,"0:01")
        XCTAssertTrue(app.staticTexts["Whole-text starts: 2 of 4"].exists)
        transport.tap();waitClock(app,"0:00");app.terminate()
    }

    @MainActor func testStopDuringAutomaticGapRestartsFirstSentence() throws {
        let app=try launch()
        app.segmentedControls["dictation-mode"].buttons["By sentences"].tap()
        app.buttons["dictation-prepare"].tap()
        let transport=app.buttons["dictation-play"]
        wait(transport,"enabled == true");transport.tap()
        let body=app.buttons["dictation-player-open"]
        wait(body,"value == 'Waiting'")
        XCTAssertEqual(transport.label,"Stop and return to beginning")
        capture(app,"stop-automatic-gap-no-waveform")
        transport.tap();waitClock(app,"0:00")
        transport.tap();waitClock(app,"0:01")
        XCTAssertEqual(clock(app,remaining:true),"0:18")
        XCTAssertTrue(app.staticTexts["Whole-text starts: 0 of 4"].exists)
        transport.tap();app.terminate()
    }

    @MainActor func testReducedMotionKeepsStaticWaveformAndPlayingLabel() async throws {
        let settings=XCUIApplication(bundleIdentifier:"com.apple.Preferences")
        settings.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"]
        settings.launch()
        if !settings.switches["Reduce Motion"].exists {
            let accessibility=settings.staticTexts["Accessibility"].firstMatch
            for _ in 0..<6 {if accessibility.exists && accessibility.isHittable {break};settings.swipeUp()}
            XCTAssertTrue(accessibility.isHittable);accessibility.tap()
            let motion=settings.staticTexts["Motion"].firstMatch
            XCTAssertTrue(motion.waitForExistence(timeout:5));motion.tap()
        }
        let reduce=settings.switches["Reduce Motion"].firstMatch
        XCTAssertTrue(reduce.waitForExistence(timeout:5))
        let wasOn=reduce.value as? String == "1"
        if !wasOn {reduce.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()}
        wait(reduce,"value == '1'")
        capture(settings,"stop-system-reduce-motion-enabled")
        defer { restoreMotionSetting(wasOn) }
        let app=try launch(theme:"Dark")
        app.buttons["dictation-prepare"].tap()
        let transport=app.buttons["dictation-play"]
        wait(transport,"enabled == true")
        app.tabBars.buttons["Coach"].tap();transport.tap();waitClock(app,"0:01")
        XCTAssertEqual(app.buttons["dictation-player-open"].value as? String,"Playing")
        capture(app,"stop-reduce-motion-playing-a")
        try await Task.sleep(for:.milliseconds(600))
        capture(app,"stop-reduce-motion-playing-b")
        transport.tap();waitClock(app,"0:00");app.terminate()
    }

    @MainActor private func restoreMotionSetting(_ enabled:Bool) {
        // A background Settings AX tree can survive an ineffective activate().
        // Relaunch and verify foreground before interacting with the real switch.
        let settings=XCUIApplication(bundleIdentifier:"com.apple.Preferences")
        settings.terminate()
        settings.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"]
        settings.launch()
        XCTAssertTrue(settings.wait(for:.runningForeground,timeout:10))
        if !settings.switches["Reduce Motion"].exists {
            let accessibility=settings.staticTexts["Accessibility"].firstMatch
            for _ in 0..<6 {if accessibility.exists && accessibility.isHittable {break};settings.swipeUp()}
            XCTAssertTrue(accessibility.isHittable);accessibility.tap()
            let motion=settings.staticTexts["Motion"].firstMatch
            XCTAssertTrue(motion.waitForExistence(timeout:5));motion.tap()
        }
        let toggle=settings.switches["Reduce Motion"].firstMatch
        wait(toggle,"hittable == true")
        let target=enabled ? "1" : "0"
        if toggle.value as? String != target {toggle.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()}
        wait(toggle,"value == '\(target)'")
        capture(settings,"stop-system-reduce-motion-restored-\(target)")
        settings.terminate()
    }

    @MainActor func testMinimalLeftTitleWithoutTimeline() throws {
        for theme in ["Light", "Dark"] {
            let app = try launch(theme:theme)
            let title = app.navigationBars.firstMatch.identifier
            app.buttons["dictation-prepare"].tap()
            wait(app.buttons["dictation-play"], "enabled == true")
            app.tabBars.buttons["Coach"].tap()
            assertBarGeometry(app, title:title)
            XCTAssertEqual(clock(app),"0:00", "Navigation does not admit playback")
            capture(app,"layout-\(theme)-minimal-ready")
            app.buttons["dictation-player-open"].press(forDuration:1)
            let faster = app.buttons["1.25×"]
            if !faster.exists { app.buttons["Speed"].tap() }
            XCTAssertTrue(faster.waitForExistence(timeout:5)); faster.tap()
            XCTAssertEqual(clock(app),"0:00","Speed menu must not admit playback")
            app.terminate()
        }
    }

    @MainActor func testLongLocalizedTitleAtAccessibilitySize() throws {
        for theme in ["Light", "Dark"] {
            let title = "Ein Spaziergang im Park"
            let app = try launch(theme:theme,locale:"de",large:true,title:title)
            app.buttons["dictation-prepare"].tap()
            wait(app.buttons["dictation-play"], "enabled == true")
            app.tabBars.buttons["Coach"].tap()
            assertBarGeometry(app,title:title)
            let body = app.buttons["dictation-player-open"]
            capture(app,"layout-\(theme)-localized-accessibility")
            body.tap()
            XCTAssertEqual(app.navigationBars.firstMatch.identifier,title)
            XCTAssertEqual(clock(app),"0:00","Body navigation never admits playback, including maximum text size")
            app.tabBars.buttons["Coach"].tap()
            body.press(forDuration:1)
            app.buttons["dictation-player-details"].tap()
            let fullTitle = app.staticTexts["dictation-expanded-title"]
            XCTAssertTrue(fullTitle.waitForExistence(timeout:5))
            XCTAssertEqual(fullTitle.label,title)
            XCTAssertGreaterThan(fullTitle.frame.height,44,"Expanded title honors accessibility text instead of shrinking")
            let expandedElapsed = app.staticTexts["dictation-expanded-elapsed"]
            XCTAssertGreaterThan(expandedElapsed.frame.height,30)
            XCTAssertEqual(expandedElapsed.value as? String,"0:00")
            let done = app.buttons["Fertig"]
            XCTAssertTrue(done.exists)
            XCTAssertLessThanOrEqual(done.frame.maxX,app.frame.maxX)
            capture(app,"layout-\(theme)-expanded-accessibility")
            done.tap()
            XCTAssertTrue(body.waitForExistence(timeout:5)); body.press(forDuration:1)
            app.buttons["dictation-player-details"].tap()
            app.buttons["dictation-expanded-open"].tap()
            XCTAssertTrue(app.textFields["dictation-draft"].waitForExistence(timeout:5))
            XCTAssertEqual(app.navigationBars.firstMatch.identifier,title)
            app.terminate()
        }
    }

    @MainActor private func assertBarGeometry(_ app:XCUIApplication, title:String) {
        let bar = app.otherElements["dictation-player"]
        XCTAssertLessThanOrEqual(bar.frame.height,48,"Content must fit inside the actual 48pt native glass accessory; overflowing AX frames can hide the track")
        let body = app.buttons["dictation-player-open"]
        let titleText = body.staticTexts["dictation-player-title"]
        XCTAssertEqual(body.label,title)
        XCTAssertTrue(titleText.exists)
        // SwiftUI merges the label's AX frame with its source icon. Measure the
        // actual title ink, not that combined accessibility bounding rectangle.
        assertLeadingTitlePixels(app,body:body)
        XCTAssertEqual(titleText.frame.midY,bar.frame.midY,accuracy:2,"One vertically centered row")
        XCTAssertFalse(bar.progressIndicators.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["dictation-elapsed"].exists)
        XCTAssertFalse(app.staticTexts["dictation-remaining"].exists)
        XCTAssertFalse(app.otherElements["dictation-timeline"].exists)
        XCTAssertFalse(bar.buttons["dictation-audio-info"].exists)
        let play = app.buttons["dictation-play"]
        XCTAssertGreaterThanOrEqual(play.frame.minX,body.frame.maxX)
        XCTAssertEqual(play.frame.midY,body.frame.midY,accuracy:1)
        XCTAssertGreaterThanOrEqual(play.frame.width,44)
        XCTAssertGreaterThanOrEqual(play.frame.height,44)
        XCTAssertFalse(app.buttons["dictation-speed"].exists)
        let receipt = XCTAttachment(string:"bar=\(bar.frame); title=\(titleText.frame); body=\(body.frame); transport=\(play.frame)")
        receipt.name="player-layout-geometry"; receipt.lifetime = .keepAlways; add(receipt)
        XCTAssertFalse(app.sliders.firstMatch.exists)
    }

    @MainActor private func assertLeadingTitlePixels(_ app:XCUIApplication,body:XCUIElement) {
        guard let image = UIImage(data:app.screenshot().pngRepresentation)?.cgImage else { return XCTFail("Missing native screenshot") }
        let scale = CGFloat(image.width) / app.frame.width
        let expectedX = body.frame.minX + 34 // 24pt icon + 10pt gap
        let crop = CGRect(x:expectedX * scale,y:(body.frame.midY - 10) * scale,
                          width:(body.frame.maxX - expectedX) * scale,height:20 * scale).integral
        guard let title = image.cropping(to:crop) else { return XCTFail("Missing title pixels") }
        let width = title.width, height = title.height
        var pixels = [UInt8](repeating:0,count:width * height * 4)
        guard let context = CGContext(data:&pixels,width:width,height:height,bitsPerComponent:8,bytesPerRow:width * 4,
                                      space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return XCTFail("Cannot decode screenshot") }
        context.draw(title,in:CGRect(x:0,y:0,width:width,height:height))
        let lightBackground = pixels[0] > 128
        let firstInk = (0..<width).first { x in
            (0..<height).filter { y in
                let i = (y * width + x) * 4
                let luminance = (Int(pixels[i]) + Int(pixels[i+1]) + Int(pixels[i+2])) / 3
                return lightBackground ? luminance < 80 : luminance > 180
            }.count >= Int(scale * 2)
        }
        XCTAssertNotNil(firstInk,"Native screenshot must contain title ink")
        if let firstInk {
            XCTAssertLessThanOrEqual(CGFloat(firstInk) / scale,4,"Title ink must begin beside the source icon, never centered in the remaining bar")
        }
    }

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
        XCTAssertFalse(app.otherElements["dictation-player"].exists, "No permanent empty accessory before explicit preparation")
        XCTAssertTrue(app.buttons["dictation-audio-info"].exists, "Cost/details remain available before explicit preparation")
        app.buttons["dictation-prepare"].tap()
        let play = app.buttons["dictation-play"]
        wait(play, "enabled == true")
        waitClock(app,"0:08",remaining:true)
        play.tap()
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].waitForExistence(timeout: 10))
        waitClock(app,"0:00",different:true)
        XCTAssertNotEqual(clock(app,remaining:true),"0:08")
        capture(app,"player-real-elapsed-remaining-advancing")
        waitClock(app,"0:00",remaining:true)
        XCTAssertEqual(clock(app), "0:08")
        XCTAssertFalse(app.buttons["dictation-pause"].exists)
        app.segmentedControls["dictation-mode"].buttons["By sentences"].tap()
        wait(play, "enabled == true")
        waitClock(app,"0:19",remaining:true) // 8 + real 3-second gap + 8-second repeat.
        play.tap()
        wait(play, "label == 'Optional final reading' AND enabled == true")
        XCTAssertEqual(clock(app,remaining:true), "0:00")
        XCTAssertEqual(clock(app), "0:19")
        capture(app,"player-sentences-natural-end-including-gap")
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
        play.tap()
        XCTAssertTrue(app.staticTexts["Whole-text starts: 2 of 4"].waitForExistence(timeout: 5))
        wait(play, "label == 'Optional final reading' AND enabled == false")
        XCTAssertEqual(clock(app), "0:08")
    }

    @MainActor func testActiveWAVPlaysAcrossAllTabsAndReturnsToExactAttempt() async throws {
        let app = try launch()
        let title = app.navigationBars.firstMatch.identifier
        app.buttons["dictation-prepare"].tap()
        let play = app.buttons["dictation-play"]
        wait(play, "enabled == true")
        play.tap()
        waitClock(app,"0:01",different:false)
        capture(app,"global-dictation-playing")
        app.tabBars.buttons["Translator"].tap()
        XCTAssertTrue(app.otherElements["dictation-player"].exists)
        let before = clock(app)
        try await Task.sleep(for: .seconds(1))
        XCTAssertNotEqual(clock(app), before)
        XCTAssertTrue(play.isEnabled)
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
        waitClock(app,"0:00",remaining:true)
        XCTAssertEqual(clock(app),"0:08")
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
            waitClock(app,"0:00",different:true)
            capture(app,"global-\(theme)-translator-playing")
            for tab in ["Podcasts", "Coach", "Dictation"] {
                let before = clock(app)
                app.tabBars.buttons[tab].tap()
                if tab == "Dictation" { app.buttons["dictation-player-open"].tap() }
                XCTAssertTrue(app.otherElements["dictation-player"].exists)
                XCTAssertNotEqual(clock(app),before,"The single clock keeps advancing across tabs")
                XCTAssertTrue(play.isEnabled,"Explicit Stop is available; there is still no Pause")
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
            waitClock(app,"0:00",remaining:true)
            XCTAssertEqual(clock(app),"0:19")
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
        waitClock(app,"0:01",different:false)
        XCUIDevice.shared.press(.home)
        try await Task.sleep(for:.seconds(1))
        app.activate()
        wait(play,"label == 'Continue' AND enabled == true")
        let frozen = clock(app)
        try await Task.sleep(for:.seconds(1))
        XCTAssertEqual(clock(app),frozen)
        play.tap()
        XCTAssertTrue(app.tabBars.buttons["Translator"].isSelected)
        app.buttons["dictation-player-open"].tap()
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
        waitClock(app,"0:00",remaining:true)
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

    @MainActor private func launch(theme: String = "Light", locale:String = "en", large:Bool = false, title fixtureTitle:String? = nil, admissionDelay:Bool = false) throws -> XCUIApplication {
        let root = URL(fileURLWithPath: "/Users/tinyserve/.hermes/cache/scratch/dictation-camera-player")
        guard let data = try? Data(contentsOf: root.appendingPathComponent("fixture/fixture.json")),
              let info = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let token = info["native"] else { throw XCTSkip("Start the isolated generated-WAV fixture described in Fixtures/generate_dictation_player_wav.py") }
        let duration = try AVAudioPlayer(contentsOf: root.appendingPathComponent("clock-fixture.wav")).duration
        XCTAssertEqual(duration, 8, accuracy: 0.001)
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "dictation-local"
        app.launchEnvironment["KM_DICTATION_UI_APPEARANCE"] = theme
        app.launchEnvironment["KM_DICTATION_CLOCK_PROBE"] = "1"
        if admissionDelay {app.launchEnvironment["KM_DICTATION_ADMISSION_DELAY"] = "1"}
        app.launchEnvironment["KM_DICTATION_FIXTURE_TOKEN"] = token
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let tab = locale == "de" ? "Diktat" : "Dictation"
        XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 10))
        app.tabBars.buttons[tab].tap()
        app.buttons["dictation-add"].tap()
        let title = app.textFields["dictation-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText(fixtureTitle ?? ("Player " + UUID().uuidString.prefix(6)))
        let original = app.textViews["dictation-original"]
        original.tap(); original.typeText("Heute scheint die Sonne.")
        app.buttons["dictation-create"].tap()
        XCTAssertTrue(app.buttons["dictation-prepare"].waitForExistence(timeout: 10))
        let prepare = app.buttons["dictation-prepare"]
        wait(prepare,"enabled == true")
        // XCTest's implicit scroll-to-tap can land on the tab bar on a small
        // phone. Bring the entire entry above native chrome before tapping.
        for _ in 0..<6 {
            if prepare.frame.maxY < app.tabBars.firstMatch.frame.minY - 8 { break }
            app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.7))
                .press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)))
        }
        XCTAssertLessThan(prepare.frame.maxY,app.tabBars.firstMatch.frame.minY)
        wait(prepare,"hittable == true")
        return app
    }
    // Opt-in simulator telemetry is sampled from the real coordinator, not a
    // visible clock or a synthetic counter. Shipping device UI has no probe.
    @MainActor private func clock(_ app:XCUIApplication,remaining:Bool = false) -> String {
        let fields = (app.otherElements["dictation-player"].value as? String ?? "").split(separator:"|",omittingEmptySubsequences:false)
        return fields.count == 2 ? String(fields[remaining ? 1 : 0]) : "unavailable"
    }
    @MainActor private func waitClock(_ app:XCUIApplication,_ value:String,remaining:Bool = false,different:Bool = false) {
        let predicate = NSPredicate { _, _ in
            MainActor.assumeIsolated {
                let current = self.clock(app,remaining:remaining)
                return current != "unavailable" && (different ? current != value : current == value)
            }
        }
        expectation(for:predicate,evaluatedWith:app)
        waitForExpectations(timeout:25)
    }
    @MainActor private func wait(_ element: XCUIElement, _ predicate: String) {
        expectation(for: NSPredicate(format: predicate), evaluatedWith: element)
        waitForExpectations(timeout: 25)
    }
    @MainActor private func capture(_ app:XCUIApplication,_ name:String) {
        let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
}
