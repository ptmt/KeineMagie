import XCTest

final class CoachUITests: XCTestCase {
    @MainActor private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Coach"].tap()
        return app
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    @MainActor func testContextualAIAssessmentPendingAndCorrection() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-assessment"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8)); answer.tap(); answer.typeText("beim")
        app.buttons["coach-check-synthetic-coach"].tap()
        XCTAssertTrue(app.staticTexts["AI check pending…"].waitForExistence(timeout: 2))
        shot(app, "coach-assessment-pending-synthetic")
        XCTAssertTrue(app.staticTexts["Incorrect"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["beim"].exists)
        XCTAssertTrue(app.staticTexts["bei"].exists)
        XCTAssertTrue(app.staticTexts["coach-explanation"].exists)
        shot(app, "coach-assessment-corrected-synthetic")
    }
    @MainActor func testPopulatedChatExerciseAndKeyboard() {
        let app = launch()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8))
        shot(app, "coach-release-synthetic-chat")
        answer.tap(); answer.typeText("auf")
        let check = app.buttons["coach-check-synthetic-coach"]
        if !check.isHittable { app.scrollViews.firstMatch.swipeUp() }
        check.tap()
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["coach-explanation"].exists)
        XCTAssertFalse(app.buttons["Review observation"].exists)
        shot(app, "coach-release-synthetic-feedback")
        let composer = app.textFields["coach-composer"]
        composer.tap(); composer.typeText("Can you clarify this?")
        XCTAssertTrue(app.buttons["coach-send"].isHittable)
        if app.keyboards.firstMatch.exists { XCTAssertLessThanOrEqual(app.buttons["coach-send"].frame.maxY, app.keyboards.firstMatch.frame.minY + 1) }
        shot(app, "coach-release-keyboard")
        app.buttons["coach-send"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic clarification, not live AI."].waitForExistence(timeout: 8))
        shot(app, "coach-release-clarification")
    }
    @MainActor func testWrongAmbiguousSkipAndCancel() {
        for (answer, feedback) in [("für", "Needs practice"), ("perhaps", "I can’t check this confidently"), ("", "Skipped")] {
            let app = launch()
            if answer.isEmpty { app.buttons["Skip"].tap() }
            else {
                let field = app.textFields["coach-answer-synthetic-coach"]
                XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); field.typeText(answer)
                app.buttons["coach-check-synthetic-coach"].tap()
            }
            XCTAssertTrue(app.staticTexts[feedback].waitForExistence(timeout: 8))
            app.terminate()
        }
        let app = launch()
        let composer = app.textFields["coach-composer"]; composer.tap(); composer.typeText("pending")
        app.buttons["coach-send"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8)); cancel.tap()
        XCTAssertTrue(app.staticTexts["Canceled"].waitForExistence(timeout: 8))
        shot(app, "coach-cancel")
    }
    @MainActor func testCitationOpensOriginalAndReturns() {
        let app = launch()
        let source = app.buttons["Hint"]
        XCTAssertTrue(source.waitForExistence(timeout: 8)); source.tap()
        let original = app.buttons["coach-source-synthetic-coach"]
        if !original.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(original.waitForExistence(timeout: 8)); original.tap()
        XCTAssertTrue(app.staticTexts["Synthetic original translation"].waitForExistence(timeout: 8))
        shot(app, "coach-original-source")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["coach-source-synthetic-coach"].waitForExistence(timeout: 8))
    }
    @MainActor func testFiveLocaleCompactFeedback() {
        let samples = [("de", "Richtig"), ("en", "Correct"), ("ru", "Верно"), ("es", "Correcto"), ("fr", "Correct")]
        for (locale, feedback) in samples {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach"
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
            app.launch()
            let tab = app.tabBars.buttons[locale == "ru" ? "Тренер" : locale == "es" ? "Entrenador" : "Coach"]
            XCTAssertTrue(tab.waitForExistence(timeout: 10))
            tab.tap()
            let field = app.textFields["coach-answer-synthetic-coach"]
            XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); field.typeText("auf")
            app.buttons["coach-check-synthetic-coach"].tap()
            XCTAssertTrue(app.staticTexts[feedback].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["coach-explanation"].exists)
            shot(app, "coach-compact-\(locale)")
            app.terminate()
        }
    }
    @MainActor func testProfileCorrectionAndExclusionReachable() {
        let app = launch()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8)); answer.tap(); answer.typeText("beim")
        app.buttons["coach-check-synthetic-coach"].tap()
        XCTAssertTrue(app.staticTexts["I can’t check this confidently"].waitForExistence(timeout: 8))
        app.buttons["coach-profile"].tap()
        let review = app.buttons["Review observation"]
        for _ in 0..<5 { if review.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(review.isHittable); review.tap()
        XCTAssertTrue(app.buttons["Count as correct"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Count as needs practice"].exists)
        XCTAssertTrue(app.buttons["Exclude"].exists)
        shot(app, "coach-profile-correction-exclusion")
    }
    @MainActor func testOldAnswerCollapsesAndExplicitRevealRestores() {
        let app = launch()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8)); answer.tap(); answer.typeText("auf")
        app.buttons["coach-check-synthetic-coach"].tap()
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 8))
        let composer = app.textFields["coach-composer"]; composer.tap(); composer.typeText("question")
        app.buttons["coach-send"].tap()
        let reveal = app.buttons["Show answer & feedback"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Correct"].exists)
        if !reveal.isHittable { app.scrollViews.firstMatch.swipeDown() }; reveal.tap()
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 8))
        shot(app, "coach-old-answer-revealed")
    }
    @MainActor func testOffscreenUnreadSurvivesBackgroundAndJumpAcknowledges() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-scroll"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        let jump = app.buttons["New messages"]
        XCTAssertTrue(jump.waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home); sleep(1); app.activate()
        XCTAssertTrue(jump.waitForExistence(timeout: 8))
        shot(app, "coach-scrolled-up-unread")
        jump.tap()
        XCTAssertTrue(jump.waitForNonExistence(timeout: 8))
        shot(app, "coach-jump-seen")
    }
    @MainActor func testBackgroundReturnConsultsServerAdmissionAndKeepsDraft() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-entry-lifecycle"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic entry count: 1"].waitForExistence(timeout: 8))
        let composer = app.textFields["coach-composer"]; composer.tap(); composer.typeText("keep this draft")
        XCUIDevice.shared.press(.home); sleep(1); app.activate()
        XCTAssertTrue(app.staticTexts["Synthetic entry count: 2"].waitForExistence(timeout: 8))
        XCTAssertEqual(composer.value as? String, "keep this draft")
        shot(app, "coach-background-draft")
    }
    @MainActor func testAccessibilityReadingOrderAndLabels() {
        let app = launch()
        XCTAssertTrue(app.textFields["coach-answer-synthetic-coach"].waitForExistence(timeout: 8))
        let snapshot = app.debugDescription
        let expected = ["Ich warte ___ den Bus.", "coach-answer-synthetic-coach", "coach-check-synthetic-coach", "label: 'Skip'", "label: 'Hint'", "coach-practice", "coach-composer", "coach-send"]
        var previous = snapshot.startIndex
        for key in expected {
            guard let range = snapshot.range(of: key, range: previous..<snapshot.endIndex) else { XCTFail("Missing/out-of-order accessible element: \(key)"); continue }
            previous = range.upperBound
        }
        XCTAssertEqual(app.textFields["coach-answer-synthetic-coach"].label, "Answer")
        XCTAssertEqual(app.textFields["coach-composer"].label, "Message")
        XCTAssertEqual(app.buttons["coach-send"].label, "Send")
        let tree = XCTAttachment(string: snapshot); tree.name = "coach-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
        shot(app, "coach-accessibility-order")
    }
    @MainActor private func arrival(reduced: Bool) {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-arrival"
        if reduced { app.launchEnvironment["KM_SIMULATOR_COACH_REDUCE_MOTION"] = "1" }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic exercise, not live AI."].waitForExistence(timeout: 8))
        shot(app, reduced ? "coach-reduced-initial" : "coach-motion-initial")
        sleep(2)
        app.buttons["coach-practice"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic clarification, not live AI."].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["New messages"].waitForNonExistence(timeout: 8))
        sleep(2)
        shot(app, reduced ? "coach-reduced-arrived-seen" : "coach-motion-arrived-seen")
        if reduced { XCTAssertEqual(app.buttons["coach-practice"].value as? String, "static;system=false;injected=true") }
        app.tabBars.buttons["Translator"].tap(); app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic clarification, not live AI."].waitForExistence(timeout: 8))
        shot(app, reduced ? "coach-reduced-return" : "coach-motion-return")
    }
    @MainActor func testArrivalSurvivesImmediateSeenReceipt() { arrival(reduced: false) }
    @MainActor func testReducedMotionUsesStaticProductionBranch() { arrival(reduced: true) }
    @MainActor func testDarkAccessibilityChatAndProfile() {
        let app = launch(large: true)
        XCTAssertTrue(app.staticTexts["Synthetic exercise, not live AI."].waitForExistence(timeout: 8))
        shot(app, "coach-release-dark-accessibility")
        XCTAssertTrue(app.buttons["coach-profile"].waitForExistence(timeout: 5))
        app.buttons["coach-profile"].tap()
        XCTAssertTrue(app.buttons["profile-cefr"].waitForExistence(timeout: 8))
        app.swipeUp()
        shot(app, "coach-release-profile-accessibility")
    }
}
