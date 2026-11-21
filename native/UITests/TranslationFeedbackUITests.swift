import XCTest

final class TranslationFeedbackUITests: XCTestCase {
    @MainActor func testDelayedStoreRendersAndAcceptsInputBeforeCompletion() {
        let app = XCUIApplication()
        // The delayed-store fixture already creates a unique protected probe root.
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "translation-delayed-store"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let input = app.textViews["translator-input"]
        XCTAssertTrue(input.waitForExistence(timeout:10))
        input.tap(); input.typeText("Snapshot")
        let submit = app.buttons["translator-submit"]
        let start = Date()
        submit.tap()
        XCTAssertFalse(submit.isEnabled)
        XCTAssertTrue(submit.label.contains("Translat"))
        input.typeText(" responsive")
        XCTAssertEqual(input.value as? String,"Snapshot responsive")
        XCTAssertLessThan(Date().timeIntervalSince(start),7.5,"UI must respond during the actual eight-second storage stall")
        XCTAssertFalse(submit.isEnabled)
        let pending = XCTAttachment(screenshot:app.screenshot()); pending.name = "pre-disk-completion-responsive-input"; pending.lifetime = .keepAlways; add(pending)
        let tree = XCTAttachment(string:app.debugDescription); tree.name = "pre-disk-AX"; tree.lifetime = .keepAlways; add(tree)
        print("PRE_DISK_RENDER_AND_INPUT elapsed=\(Date().timeIntervalSince(start))")
        let output = app.descendants(matching:.any).matching(identifier:"translation-output").firstMatch
        expectation(for:NSPredicate(format:"value == ''"),evaluatedWith:output)
        waitForExpectations(timeout:20)
        app.terminate()
    }
    @MainActor func testDelayedStoreFailureClearsPendingWithoutResult() {
        let app = XCUIApplication()
        // The delayed-store fixture already creates a unique protected probe root.
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "translation-delayed-store-failure"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let input = app.textViews["translator-input"]
        XCTAssertTrue(input.waitForExistence(timeout:10))
        input.tap(); input.typeText("Storage failure")
        let submit = app.buttons["translator-submit"]; submit.tap()
        XCTAssertFalse(submit.isEnabled)
        let error = app.staticTexts["outbox-storage-error"]
        XCTAssertTrue(error.waitForExistence(timeout:15))
        XCTAssertTrue(submit.isEnabled)
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        let bottom = submit.frame.minY - 8
        for _ in 0..<6 {
            let frame = error.frame
            if frame.minY >= top && frame.maxY <= bottom { break }
            let shift = frame.minY < top ? top - frame.minY : bottom - frame.maxY
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width - 4, dy: (top + bottom) / 2))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: max(-140, min(140, shift)))))
        }
        XCTAssertGreaterThanOrEqual(error.frame.minY, top - 1)
        XCTAssertLessThanOrEqual(error.frame.maxY, bottom + 1)
        let attachment = XCTAttachment(screenshot:app.screenshot()); attachment.name = "storage-failure-clears-pending"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate()
    }
    @MainActor func testPendingFeedbackFiveLocalesAndStableOutput() {
        for locale in ["en", "de", "ru", "es", "fr"] {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "translation-pending"
            app.launchEnvironment["KM_SIMULATOR_PENDING_GEOMETRY"] = "1"
            app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
            app.launch()
            let input = app.textViews["translator-input"]
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            input.tap(); input.typeText("Synthetic pending feedback")
            let submit = app.buttons["translator-submit"]
            let output = app.descendants(matching: .any).matching(identifier: "translation-output").firstMatch
            let before = submit.frame
            let outputBefore = output.frame
            submit.tap()
            XCTAssertFalse(submit.isEnabled)
            XCTAssertFalse(app.buttons["translation-copy"].exists, "No copy control without completed output")
            XCTAssertEqual(submit.frame.minY, before.minY, accuracy: 1)
            XCTAssertEqual(submit.frame.height, before.height, accuracy: 1)
            XCTAssertEqual(output.frame.minY, outputBefore.minY, accuracy: 1)
            XCTAssertEqual(output.frame.height, outputBefore.height, accuracy: 1)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "translate-pending-" + locale
            attachment.lifetime = .keepAlways; add(attachment)
            print("TRANSLATE_PENDING \(locale) submit=\(submit.frame) output=\(output.frame)")
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            let completed = NSPredicate(format: "enabled == true")
            expectation(for: completed, evaluatedWith: submit)
            waitForExpectations(timeout: 30)
            app.swipeUp()
            XCTAssertTrue(app.buttons["translation-copy"].isEnabled)
            app.terminate()
        }
    }
}
