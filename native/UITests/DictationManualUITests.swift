import XCTest
import UIKit

/// Actual loopback Go handler and cached generated PCM. Provider transport alone
/// is synthetic; this is not a live-account or speech-quality acceptance test.
final class DictationManualUITests:XCTestCase {
    @MainActor private func launch(locale:String="en", large:Bool=false, titlePrefix:String="Manual", theme:String?=nil) throws -> XCUIApplication {
        let path=ProcessInfo.processInfo.environment["KM_DICTATION_NATIVE_FIXTURE_PATH"] ?? "/Users/tinyserve/.hermes/cache/scratch/dictation-acceptance-resume/fixture.json"
        let config=try JSONDecoder().decode([String:String].self,from:Data(contentsOf:URL(fileURLWithPath:path)))
        let app=XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"]="dictation-local"
        app.launchEnvironment["KM_DICTATION_FIXTURE_TOKEN"]=config["native"]
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"]=UUID().uuidString
        app.launchEnvironment["KM_DICTATION_CLOCK_PROBE"]="1"
        if let theme {app.launchEnvironment["KM_DICTATION_UI_APPEARANCE"]=theme}
        app.launchArguments=["-AppleLanguages","(\(locale))","-AppleLocale",locale]
        if large {app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]}
        app.launch()
        let tab=["en":"Dictation","de":"Diktat","ru":"Диктант","es":"Dictado","fr":"Dictée"][locale]!
        XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout:10));app.tabBars.buttons[tab].tap()
        app.buttons["dictation-add"].tap()
        let title=app.textFields["dictation-title"];XCTAssertTrue(title.waitForExistence(timeout:5));title.tap();title.typeText(titlePrefix+" "+UUID().uuidString.prefix(5))
        let original=app.textViews["dictation-original"];original.tap();original.typeText("Die kleine Katze schläft, weil sie sehr müde ist. Der Hund wartet.")
        app.buttons["dictation-create"].tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"dictation-pacing-timeline").firstMatch.waitForExistence(timeout:10))
        return app
    }
    @MainActor private func wait(_ element:XCUIElement,_ predicate:String,timeout:Double=15) {
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:predicate),object:element)],timeout:timeout),.completed)
    }
    @MainActor private func visible(_ app:XCUIApplication,_ element:XCUIElement) {
        // AX hittability includes thin/offscreen portions behind the glass player.
        // Require the complete target inside content before synthesizing a tap.
        func bounds() -> (CGFloat,CGFloat) {
            let top=app.navigationBars.firstMatch.frame.maxY+2
            var bottom=app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY-8 : app.frame.maxY-8
            let player=app.otherElements["dictation-player"]
            if player.exists {bottom=min(bottom,player.frame.minY-8)}
            if app.keyboards.firstMatch.exists {bottom=min(bottom,app.keyboards.firstMatch.frame.minY-2)}
            return (top,bottom)
        }
        for _ in 0..<12 {
            let (top,bottom)=bounds()
            if element.exists && element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom {return}
            let downward=element.exists && element.frame.minY < top
            if downward {app.scrollViews.firstMatch.swipeDown()}
            else {app.scrollViews.firstMatch.swipeUp()}
        }
        let (top,bottom)=bounds()
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.minY,top)
        XCTAssertLessThanOrEqual(element.frame.maxY,bottom)
    }
    @MainActor private func shot(_ app:XCUIApplication,_ name:String) {
        XCTAssertFalse(app.buttons["Show timeline"].exists)
        XCTAssertFalse(app.buttons["dictation-extra-replay"].exists)
        let buttons=app.buttons.allElementsBoundByIndex.filter { $0.isHittable }.map { "\($0.identifier)|\($0.label)|\($0.frame)" }
        let inventory=XCTAttachment(string:buttons.joined(separator:"\n"));inventory.name=name+"-buttons-\(buttons.count)";inventory.lifetime = .keepAlways;add(inventory)
        let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
    @MainActor private func readableTransport(_ app:XCUIApplication,_ button:XCUIElement) throws {
        let image=try XCTUnwrap(app.screenshot().image.cgImage)
        let scale=CGFloat(image.width)/app.frame.width
        let inner=button.frame.insetBy(dx:button.frame.width*0.35,dy:button.frame.height*0.25)
        let pixels=CGRect(x:inner.minX*scale,y:inner.minY*scale,width:inner.width*scale,height:inner.height*scale)
        let crop=try XCTUnwrap(image.cropping(to:pixels))
        let context=try XCTUnwrap(CGContext(data:nil,width:crop.width,height:crop.height,bitsPerComponent:8,bytesPerRow:crop.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(crop,in:CGRect(x:0,y:0,width:crop.width,height:crop.height))
        let data=try XCTUnwrap(context.data).assumingMemoryBound(to:UInt8.self)
        var darkest=255,lightest=0
        for offset in stride(from:0,to:crop.width*crop.height*4,by:4) {
            let light=(Int(data[offset])+Int(data[offset+1])+Int(data[offset+2]))/3
            darkest=min(darkest,light);lightest=max(lightest,light)
        }
        XCTAssertGreaterThan(lightest-darkest,100,"Next label must contrast with its real rendered button, not only exist in AX")
    }
    @MainActor func testManualNextExtraReplayAndProgressiveHybrid() throws {
        let app=try launch(titlePrefix:"Timeline")
        let transport=app.buttons["dictation-manual-transport"]
        XCTAssertTrue(transport.waitForExistence(timeout:5))
        XCTAssertEqual(transport.label,"Prepare audio")
        XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"dictation-rules").firstMatch.exists)
        XCTAssertFalse(app.buttons["Show timeline"].exists)
        XCTAssertTrue(app.staticTexts["Sentence 1"].exists)
        XCTAssertTrue(app.staticTexts["Fragment 1.1"].exists)
        XCTAssertTrue(app.staticTexts["Fragment 1.2"].exists)
        XCTAssertTrue(app.staticTexts["Sentence 2"].exists)
        XCTAssertTrue(app.staticTexts["Fragment 2.1"].exists)
        XCTAssertFalse(app.segmentedControls["dictation-pacing-repeats"].exists)
        app.buttons["dictation-menu"].tap()
        app.buttons["Plays per fragment"].tap()
        app.buttons["3×"].tap()
        wait(transport,"enabled == true")
        app.buttons["dictation-menu"].tap()
        app.buttons["dictation-pacing-long"].tap()
        wait(transport,"enabled == true")
        transport.tap();wait(transport,"label == 'Play' AND enabled == true")
        transport.tap();wait(transport,"label == 'Stop' AND enabled == true")
        XCTAssertFalse(app.otherElements["dictation-player"].exists)
        shot(app,"native-compact-playing")
        wait(transport,"label == 'Next' AND enabled == true")
        sleep(2);XCTAssertEqual(transport.label,"Next","Introduction must not auto-next")
        XCTAssertTrue(app.staticTexts["Whole text first"].exists,"Writing wait belongs to the stage actually heard")
        XCTAssertTrue(app.staticTexts["Fragment 1.1"].exists)
        try readableTransport(app,transport)
        shot(app,"native-manual-introduction-next")
        transport.tap()
        let gap=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","Gap before repeat")).firstMatch
        XCTAssertTrue(gap.waitForExistence(timeout:15))
        XCTAssertFalse(app.otherElements["dictation-player"].exists)
        shot(app,"native-compact-gap")
        wait(transport,"label == 'Next' AND enabled == true",timeout:35)
        sleep(2);XCTAssertEqual(transport.label,"Next","Fragment completion must not auto-next")
        XCTAssertTrue(app.staticTexts["Fragment 1.1"].exists)
        XCTAssertTrue(app.staticTexts["Fragment 2.1"].exists)
        try readableTransport(app,transport)
        XCTAssertLessThanOrEqual(app.buttons["dictation-check"].frame.maxY, app.tabBars.firstMatch.frame.minY, "Compact first viewport must keep Check above native tabs without hiding the timeline")
        shot(app,"native-manual-fragment-next")
        app.buttons["dictation-menu"].tap()
        let replay=app.buttons["dictation-extra-replay"];XCTAssertTrue(replay.waitForExistence(timeout:5));replay.tap()
        wait(transport,"label == 'Next' AND enabled == true")
        let draft=app.textFields["dictation-draft"];visible(app,draft);draft.tap();draft.typeText("Die Katze schläft.")
        let check=app.buttons["dictation-check"];visible(app,check);wait(check,"enabled == true");check.tap()
        let state=app.staticTexts["dictation-assessment-state"]
        XCTAssertTrue(state.waitForExistence(timeout:10));visible(app,state)
        XCTAssertTrue(state.label.contains("Preparing explanation"),state.label)
        shot(app,"native-manual-hybrid-pending")
        wait(state,"label == 'AI explanation of the saved comparison'",timeout:15)
        let explanation=app.staticTexts["Synthetic explanation for native testing. The source remains unchanged."]
        XCTAssertTrue(explanation.exists)
        visible(app,explanation)
        shot(app,"native-manual-hybrid-completed")
        app.terminate()
    }
    @MainActor func testOptionalFinalWholeReadingEndToEnd() throws {
        continueAfterFailure = false
        let app = try launch(titlePrefix:"FinalWhole")
        defer { app.terminate() }
        let transport = app.buttons["dictation-manual-transport"]
        wait(transport,"label == 'Prepare audio' AND enabled == true")
        transport.tap(); wait(transport,"label == 'Play' AND enabled == true")
        transport.tap(); wait(transport,"label == 'Next' AND enabled == true")
        // Three actual fragments, two planned readings each, default 3-second gaps.
        for fragment in 0..<3 {
            transport.tap()
            wait(transport,"label == 'Stop' AND enabled == true")
            wait(transport,fragment == 2 ? "label == 'Optional final reading' AND enabled == true" : "label == 'Next' AND enabled == true",timeout:25)
        }
        XCTAssertTrue(app.staticTexts["Optional final reading"].exists)
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
        sleep(2)
        XCTAssertEqual(transport.label,"Optional final reading","Final whole reading must await explicit activation")
        transport.tap()
        wait(transport,"label == 'Optional final reading' AND enabled == false",timeout:25)
        XCTAssertTrue(app.staticTexts["Whole-text starts: 2 of 4"].exists)
        XCTAssertFalse(app.otherElements["dictation-player"].exists)
        shot(app,"native-optional-final-whole-ended")
        let draft = app.textFields["dictation-draft"]
        visible(app,draft); draft.tap(); draft.typeText("Die kleine Katze schläft, weil sie sehr müde ist. Der Hund wartet.")
        app.buttons["dictation-menu"].tap()
        app.buttons["dictation-complete"].tap()
        let check = app.buttons["dictation-check"]
        visible(app,check); wait(check,"enabled == true"); check.tap()
        let state = app.staticTexts["dictation-assessment-state"]
        XCTAssertTrue(state.waitForExistence(timeout:10))
        wait(state,"label == 'AI explanation of the saved comparison'",timeout:20)
        shot(app,"native-optional-final-whole-checked")
    }
    @MainActor func testTransportContrastInLightAndDark() throws {
        for theme in ["Light","Dark"] {
            let app=try launch(titlePrefix:"Contrast",theme:theme)
            let transport=app.buttons["dictation-manual-transport"]
            wait(transport,"label == 'Prepare audio' AND enabled == true")
            try readableTransport(app,transport)
            transport.tap();wait(transport,"label == 'Play' AND enabled == true")
            try readableTransport(app,transport)
            transport.tap();wait(transport,"label == 'Next' AND enabled == true")
            try readableTransport(app,transport)
            shot(app,"native-transport-contrast-"+theme.lowercased())
            app.buttons["dictation-menu"].tap()
            app.buttons["Mode"].tap()
            app.buttons["Whole text"].tap()
            wait(transport,"label == 'Play' AND enabled == true")
            for count in 2...4 {
                transport.tap()
                wait(app.staticTexts["Whole-text starts: \(count) of 4"],"exists == true")
                wait(transport,"label == 'Play'")
            }
            wait(transport,"enabled == false")
            transport.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
            XCTAssertFalse(transport.isEnabled,"Exhausted transport must remain disabled")
            XCTAssertTrue(app.staticTexts["Whole-text starts: 4 of 4"].exists)
            shot(app,"native-transport-disabled-"+theme.lowercased())
            app.terminate()
        }
    }
    @MainActor func testFiveLocaleManualSurfaceAndUnknownSpend() throws {
        for locale in ["en","de","ru","es","fr"] {
            let app=try launch(locale:locale)
            XCTAssertTrue(app.buttons["dictation-manual-transport"].isEnabled)
            XCTAssertFalse(app.staticTexts["pacing.hint"].exists)
            XCTAssertFalse(app.staticTexts["assessment.finished"].exists)
            shot(app,"native-manual-"+locale)
            app.navigationBars.buttons.firstMatch.tap()
            let footer=app.descendants(matching:.any).matching(identifier:"dictation-speech-spend").firstMatch
            for _ in 0..<8 {if footer.exists && footer.isHittable {break};app.swipeUp()}
            XCTAssertTrue(footer.exists)
            let unknown=["en":"No data","de":"Keine Daten","ru":"Нет данных","es":"Sin datos","fr":"Pas de données"][locale]!
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@",unknown)).firstMatch.exists)
            shot(app,"native-spend-"+locale)
            app.terminate()
        }
    }
    @MainActor func testHybridFailurePreservesComparisonAndGetRecovery() throws {
        let app=try launch()
        let draft=app.textFields["dictation-draft"];visible(app,draft);draft.tap();draft.typeText("Fehler Katze.")
        let check=app.buttons["dictation-check"];visible(app,check);wait(check,"enabled == true");check.tap()
        let state=app.staticTexts["dictation-assessment-state"];XCTAssertTrue(state.waitForExistence(timeout:10));visible(app,state)
        wait(state,"label == 'Explanation unavailable.'")
        XCTAssertTrue(app.staticTexts["Your answer and comparison are saved. This is not a language error. No automatic new AI request."].exists)
        let recover=app.buttons["Get saved result"];visible(app,recover);recover.tap()
        wait(state,"label == 'Explanation unavailable.'")
        shot(app,"native-manual-hybrid-failed-recovered");app.terminate()
    }

    @MainActor func testPendingCancellationRetainsComparisonAfterLateProvider() throws {
        let app=try launch()
        let draft=app.textFields["dictation-draft"];visible(app,draft);draft.tap();draft.typeText("Cancel Katze.")
        let check=app.buttons["dictation-check"];visible(app,check);wait(check,"enabled == true");check.tap()
        let state=app.staticTexts["dictation-assessment-state"]
        XCTAssertTrue(state.waitForExistence(timeout:10));visible(app,state)
        XCTAssertTrue(state.label.contains("Preparing explanation"))
        let cancel=app.buttons["Cancel"];visible(app,cancel);cancel.tap()
        wait(state,"label == 'Explanation canceled. Comparison remains saved.'")
        sleep(9);XCTAssertEqual(state.label,"Explanation canceled. Comparison remains saved.")
        XCTAssertTrue(app.staticTexts["Cancel Katze."].exists)
        shot(app,"native-hybrid-canceled");app.terminate()
    }

    @MainActor func testLargestFiveLocaleKeyboardAndDraftReturn() throws {
        continueAfterFailure = false
        for locale in ["en","de","ru","es","fr"] {
            let app=try launch(locale:locale,large:true)
            let title=app.navigationBars.firstMatch.identifier
            let draft=app.textFields["dictation-draft"];visible(app,draft);draft.tap();draft.typeText("Mein Entwurf.")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
            XCTAssertLessThanOrEqual(draft.frame.maxY,app.keyboards.firstMatch.frame.minY)
            XCTAssertGreaterThanOrEqual(draft.frame.minY,app.navigationBars.firstMatch.frame.maxY,"The typed first line must not scroll behind navigation")
            XCTAssertLessThanOrEqual(app.buttons["dictation-check"].frame.maxY,app.keyboards.firstMatch.frame.minY)
            shot(app,"native-manual-largest-keyboard-"+locale)
            app.navigationBars.buttons.firstMatch.tap()
            let row=app.buttons.matching(identifier:"dictation-row").matching(NSPredicate(format:"label CONTAINS %@",title)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
            XCTAssertEqual(app.textFields["dictation-draft"].value as? String,"Mein Entwurf.")
            XCTAssertTrue(app.buttons["dictation-check"].exists)
            app.terminate()
        }
    }

    @MainActor func testGlobalPolicyTwoStopAndDraftAcrossAllTabs() throws {
        let app=try launch(titlePrefix:"Global")
        let title=app.navigationBars.firstMatch.identifier
        let draft=app.textFields["dictation-draft"];visible(app,draft);draft.tap();draft.typeText("Mein Entwurf.")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons.matching(identifier:"dictation-row").matching(NSPredicate(format:"label CONTAINS %@",title)).firstMatch.tap()
        let transport=app.buttons["dictation-manual-transport"];visible(app,transport);wait(transport,"enabled == true");transport.tap()
        wait(transport,"label == 'Play' AND enabled == true")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["dictation-player-open"].waitForExistence(timeout:5))
        shot(app,"native-compact-back-player")
        XCTAssertGreaterThanOrEqual(app.buttons["dictation-play"].frame.height,44)
        XCTAssertGreaterThanOrEqual(app.buttons["dictation-player-open"].frame.height,44)
        app.buttons["dictation-player-open"].tap()
        XCTAssertFalse(app.otherElements["dictation-player"].exists)
        transport.tap()
        sleep(2)
        XCTAssertFalse(app.otherElements["dictation-player"].exists,"Detail must remove the actual accessory")
        XCTAssertFalse(app.buttons["dictation-player-open"].exists)
        for tab in ["Translator","Podcasts","Coach"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertEqual(app.buttons["dictation-player-open"].value as? String,"Playing")
        }
        let before=app.otherElements["dictation-player"].value as? String
        sleep(2)
        XCTAssertNotEqual(app.otherElements["dictation-player"].value as? String,before)
        shot(app,"native-policy-two-global-coach")
        let beforeDetail=app.otherElements["dictation-player"].value as? String
        app.buttons["dictation-player-open"].tap()
        XCTAssertFalse(app.otherElements["dictation-player"].exists)
        XCTAssertEqual(transport.label,"Stop")
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
        XCTAssertEqual(app.textFields["dictation-draft"].value as? String,"Mein Entwurf.")
        sleep(2)
        app.tabBars.buttons["Coach"].tap()
        XCTAssertEqual(app.buttons["dictation-player-open"].value as? String,"Playing")
        XCTAssertNotEqual(app.otherElements["dictation-player"].value as? String,beforeDetail)
        app.buttons["dictation-play"].tap()
        wait(app.buttons["dictation-player-open"],"value == 'Stopped'")
        XCTAssertTrue((app.otherElements["dictation-player"].value as? String ?? "").hasPrefix("0:00|"))
        app.buttons["dictation-player-open"].tap()
        XCTAssertEqual(app.navigationBars.firstMatch.identifier,title)
        XCTAssertFalse(app.otherElements["dictation-player"].exists)
        XCTAssertFalse(app.buttons["dictation-player-open"].exists)
        XCTAssertEqual(app.textFields["dictation-draft"].value as? String,"Mein Entwurf.")
        XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
        visible(app,transport);transport.tap();wait(transport,"label == 'Stop' AND enabled == true")
        XCTAssertTrue(app.staticTexts["Whole-text starts: 2 of 4"].exists)
        transport.tap();wait(transport,"label == 'Play' AND enabled == true")
        shot(app,"native-policy-two-stopped-draft");app.terminate()
    }
}
