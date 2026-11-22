import XCTest

/// Synthetic transport only; exercises the actual Release view and recheck confirmation.
final class CoachClueReleaseUITests: XCTestCase {
    @MainActor func testClueRemainsVisibleAcrossCheckAndExplicitRecheck() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-stable"
        app.launchEnvironment["KM_COACH_STABLE_CLUE"] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Coach"].tap()
        let clue = app.staticTexts["coach-clue-stable-word"]
        XCTAssertTrue(clue.waitForExistence(timeout: 10))
        guard clue.exists else { return }
        XCTAssertEqual(clue.label, "a period of practical work experience")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", clue.label)).count, 1)
        let answer = app.textFields["coach-answer-stable-word"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        answer.tap(); answer.typeText("  Traineeship  ")
        app.buttons["coach-check-stable-word"].tap()
        XCTAssertTrue(app.buttons["coach-stop"].waitForExistence(timeout: 3))
        XCTAssertTrue(clue.exists)
        XCTAssertTrue(app.staticTexts["coach-feedback"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["coach-submitted-stable-word"].label, "  Traineeship  ")
        XCTAssertTrue(clue.exists)
        capture(app, "clue-checked")
        let recheck = app.buttons["Check again with AI"]
        XCTAssertTrue(recheck.waitForExistence(timeout: 5))
        recheck.tap()
        app.buttons.matching(identifier: "Check again with AI").allElementsBoundByIndex.last!.tap()
        let confirmation = app.buttons.matching(identifier: "Check again with AI").allElementsBoundByIndex.last!
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(app.buttons["coach-stop"].waitForExistence(timeout: 3))
        XCTAssertTrue(clue.exists)
        XCTAssertTrue(app.staticTexts["Recheck kept the exact answer and clue."].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["coach-submitted-stable-word"].label, "  Traineeship  ")
        XCTAssertTrue(clue.exists)
        capture(app, "clue-rechecked")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
