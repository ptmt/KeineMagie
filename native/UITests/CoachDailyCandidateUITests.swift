import XCTest

final class CoachDailyCandidateUITests: XCTestCase {
    @MainActor private func launch(_ mode: String, tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = mode
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 10))
        app.tabBars.buttons[tab].tap()
        return app
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    @MainActor func testCheckSkipTargetsAndSuccessKeyboard() {
        let app = launch("coach", tab: "Coach")
        let field = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        let check = app.buttons["coach-check-synthetic-coach"]
        let skip = app.buttons["Skip"]
        XCTAssertGreaterThanOrEqual(check.frame.height, 44)
        XCTAssertGreaterThanOrEqual(skip.frame.height, 44)
        XCTAssertGreaterThanOrEqual(skip.frame.minX - check.frame.maxX, 12)
        shot(app, "daily-native-exercise-targets")
        field.tap(); field.typeText("auf")
        XCTAssertTrue(check.isHittable)
        check.tap()
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 8))
        shot(app, "daily-native-green-success")
        let composer = app.textFields["coach-composer"]
        composer.tap(); composer.typeText("Question")
        XCTAssertLessThanOrEqual(app.buttons["coach-send"].frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        shot(app, "daily-native-keyboard")
    }
    @MainActor func testCheckingIntervalsNormalAndReducedMotion() {
        for reduced in [false, true] {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-assessment"
            app.launchEnvironment["KM_SIMULATOR_COACH_CHECK_CAPTURE"] = "1"
            if reduced { app.launchEnvironment["KM_SIMULATOR_COACH_REDUCE_MOTION"] = "1" }
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch(); XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
            let answer = app.textFields["coach-answer-synthetic-coach"]
            XCTAssertTrue(answer.waitForExistence(timeout: 8)); answer.tap(); answer.typeText("beim")
            app.buttons["coach-check-synthetic-coach"].tap()
            let pending = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Checking…")).firstMatch
            XCTAssertTrue(pending.waitForExistence(timeout: 2))
            XCTAssertFalse(app.staticTexts["AI check pending…"].exists)
            shot(app, reduced ? "checking-static-a" : "checking-animated-a")
            Thread.sleep(forTimeInterval: 0.25)
            shot(app, reduced ? "checking-static-b" : "checking-animated-b")
            XCTAssertTrue(app.staticTexts["Incorrect"].waitForExistence(timeout: 8))
            shot(app, reduced ? "incorrect-reduced" : "incorrect-normal")
            app.terminate()
        }
    }
    @MainActor func testManualOlderReadingSurvivesEntryReadback() {
        let app = launch("coach-scroll", tab: "Coach")
        let last = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic saved message 23.")).firstMatch
        XCTAssertTrue(last.waitForExistence(timeout: 8)); XCTAssertTrue(last.isHittable)
        let initial = last.frame
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(last.frame.minY, initial.minY, accuracy: 1)
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertTrue(app.buttons["coach-latest"].waitForExistence(timeout: 5))
        let reading = last.frame
        app.tabBars.buttons["Translator"].tap(); app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.buttons["coach-latest"].waitForExistence(timeout: 5))
        XCTAssertEqual(last.frame.minY, reading.minY, accuracy: 2)
        shot(app, "daily-manual-history-return")
    }
    @MainActor func testDictationPullRefreshChangesActualHistoryWithoutAudio() {
        let app = launch("dictation-refresh", tab: "Dictation")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["dictation-empty-create"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Refresh"].exists)
        for read in 2...3 {
            // Pull from inside the actual short history row. A generic full-List
            // swipe can start in its empty background and never cross the refresh threshold.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.8))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
            let row = app.buttons["dictation-row"]
            XCTAssertTrue(row.waitForExistence(timeout: 8))
            let title = "Synthetic refreshed dictation · read \(read)"
            let changed = NSPredicate(format: "label CONTAINS %@", title)
            expectation(for: changed, evaluatedWith: row)
            waitForExpectations(timeout: 8)
            XCTAssertFalse(app.buttons["dictation-empty-create"].exists)
            XCTAssertFalse(app.buttons["Refresh"].exists)
            shot(app, "daily-dictation-pull-refresh-\(read)")
        }
    }
    @MainActor func testEmptyDictationHasPrimaryCreateAndNoRefresh() {
        let app = launch("dictation-empty", tab: "Dictation")
        XCTAssertTrue(app.staticTexts["No dictations yet."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Refresh"].exists)
        let create = app.buttons["dictation-empty-create"]
        XCTAssertTrue(create.exists)
        shot(app, "daily-dictation-empty")
        create.tap()
        XCTAssertTrue(app.textFields["dictation-title"].waitForExistence(timeout: 5))
        app.textFields["dictation-title"].tap(); app.textFields["dictation-title"].typeText("Saved creation draft")
        shot(app, "daily-dictation-existing-create")
        app.buttons["Cancel"].tap()
        let resume = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Saved creation draft")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No dictations yet."].exists)
        shot(app, "daily-dictation-saved-create-draft")
        resume.tap()
        XCTAssertEqual(app.textFields["dictation-title"].value as? String, "Saved creation draft")
    }
}
