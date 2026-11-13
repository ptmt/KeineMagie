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
        for (answer, feedback) in [("für", "Needs practice"), ("perhaps", "Not assessed"), ("", "Skipped")] {
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
        let source = app.buttons["Show source / hint"]
        XCTAssertTrue(source.waitForExistence(timeout: 8)); source.tap()
        let original = app.buttons["coach-source-synthetic-coach"]
        if !original.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(original.waitForExistence(timeout: 8)); original.tap()
        XCTAssertTrue(app.staticTexts["Synthetic original translation"].waitForExistence(timeout: 8))
        shot(app, "coach-original-source")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["coach-source-synthetic-coach"].waitForExistence(timeout: 8))
    }
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
