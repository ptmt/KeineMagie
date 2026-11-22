import XCTest

final class CoachStableChatUITests: XCTestCase {
    @MainActor func testSubmittedAnswerPendingAndResultStaySeparate() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-assessment"
        app.launchEnvironment["KM_SIMULATOR_COACH_CHECK_CAPTURE"] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Coach"].tap()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        answer.tap(); answer.typeText("  beim  ")
        app.buttons["coach-check-synthetic-coach"].tap()
        XCTAssertTrue(app.staticTexts["coach-submitted-synthetic-coach"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["coach-submitted-synthetic-coach"].label, "  beim  ")
        XCTAssertTrue(app.buttons["coach-stop"].exists)
        XCTAssertFalse(app.buttons["coach-send"].exists)
        XCTAssertTrue(app.staticTexts["Ich war einmal ___ diesem Kurs dabei."].exists)
        capture(app, "stable-pending")
        XCTAssertTrue(app.staticTexts["coach-feedback"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["coach-submitted-synthetic-coach"].exists)
        XCTAssertTrue(app.staticTexts["bei"].exists)
        XCTAssertTrue(app.buttons["coach-send"].exists)
        let composer = app.otherElements["coach-composer-container"]
        let boundary = composer.exists ? composer.frame.minY : app.textFields["coach-composer"].frame.minY
        for id in ["coach-feedback", "coach-correction", "coach-explanation"] {
            let text = app.staticTexts[id]
            XCTAssertTrue(text.exists)
            XCTAssertGreaterThanOrEqual(text.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(text.frame.maxX, app.frame.maxX)
            XCTAssertLessThan(text.frame.maxY, boundary)
        }
        capture(app, "stable-result")
    }
    @MainActor func testContextTargetCorrectAlternativeAndCollapsedHistory() {
        let app = launchStable(correct: true)
        let prompt = app.staticTexts["coach-prompt-stable-word"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        XCTAssertEqual(prompt.value as? String, "abholen")
        XCTAssertFalse(app.staticTexts["Archived synthetic conversation remains collapsed."].exists)
        let composer = app.textFields["coach-composer"]
        composer.tap(); composer.typeText("Discussion draft")
        let answer = app.textFields["coach-answer-stable-word"]
        answer.tap(); answer.typeText("collect")
        app.buttons["coach-check-stable-word"].tap()
        XCTAssertTrue(app.buttons["coach-stop"].waitForExistence(timeout: 2))
        XCTAssertTrue(prompt.exists)
        XCTAssertFalse(app.staticTexts["Archived synthetic conversation remains collapsed."].exists)
        capture(app, "context-pending")
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 15))
        XCTAssertEqual(composer.value as? String, "Discussion draft")
        XCTAssertEqual(app.staticTexts["coach-submitted-stable-word"].label, "collect")
        XCTAssertLessThan(app.staticTexts["coach-feedback"].frame.maxY, composer.frame.minY)
        capture(app, "context-correct")
        app.buttons["coach-send"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic discussion response, not an answer check."].waitForExistence(timeout: 8))
    }
    @MainActor func testStopPreservesAnswerAndDiscussionDraft() {
        let app = launchStable()
        let answer = app.textFields["coach-answer-stable-word"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        let composer = app.textFields["coach-composer"]
        composer.tap(); composer.typeText("Discussion draft")
        answer.tap(); answer.typeText("  collect  ")
        app.buttons["coach-check-stable-word"].tap()
        let stop = app.buttons["coach-stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 2)); stop.tap()
        XCTAssertTrue(app.staticTexts["coach-feedback"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["coach-submitted-stable-word"].label, "  collect  ")
        XCTAssertEqual(composer.value as? String, "Discussion draft")
        XCTAssertTrue(app.buttons["coach-send"].exists)
        XCTAssertFalse(app.staticTexts["Archived synthetic conversation remains collapsed."].exists)
        capture(app, "context-canceled")
    }
    @MainActor func testTransportErrorPreservesAnswerAndDraft() {
        let app = launchStable(error: true)
        let answer = app.textFields["coach-answer-stable-word"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        let composer = app.textFields["coach-composer"]
        composer.tap(); composer.typeText("Discussion draft")
        answer.tap(); answer.typeText("collect")
        app.buttons["coach-check-stable-word"].tap()
        XCTAssertTrue(app.staticTexts["coach-error"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["coach-submitted-stable-word"].label, "collect")
        XCTAssertEqual(composer.value as? String, "Discussion draft")
        XCTAssertFalse(app.staticTexts["Correct"].exists)
        capture(app, "context-error")
    }
    @MainActor private func launchStable(correct: Bool = false, error: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-stable"
        if correct { app.launchEnvironment["KM_COACH_STABLE_CORRECT"] = "1" }
        if error { app.launchEnvironment["KM_COACH_STABLE_ERROR"] = "1" }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
