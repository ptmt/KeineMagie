import XCTest

final class CoachPresentationUITests: XCTestCase {
    @MainActor func testFiveLocaleLargestDarkHistory() {
        for (locale, label) in [("en", "Awaiting answer"), ("de", "Antwort ausstehend"), ("ru", "Ожидает ответа"), ("es", "Esperando respuesta"), ("fr", "En attente de réponse")] {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-history"
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            let tab = app.tabBars.buttons[locale == "ru" ? "Тренер" : locale == "es" ? "Entrenador" : "Coach"]
            XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 8))
            XCTAssertTrue(app.textFields["coach-answer-history-waiting"].isHittable)
            XCTAssertLessThanOrEqual(app.textFields["coach-composer"].frame.maxX, app.frame.maxX)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "coach-history-largest-dark-" + locale; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }
    @MainActor func testHistoryBottomEarlierAndOwnSend() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-history"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        let waiting = app.textFields["coach-answer-history-waiting"]
        XCTAssertTrue(waiting.waitForExistence(timeout: 10))
        XCTAssertTrue(waiting.isHittable, "Initial long history must open at actual bottom")
        XCTAssertFalse(app.staticTexts["Archived synthetic exercise 0"].exists)
        XCTAssertFalse(app.buttons["Source"].exists)
        XCTAssertTrue(app.buttons["coach-reveal"].exists)
        let initial = XCTAttachment(screenshot: app.screenshot()); initial.name = "coach-history-initial-bottom"; initial.lifetime = .keepAlways; add(initial)
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertTrue(app.buttons["coach-latest"].waitForExistence(timeout: 5))
        let composer = app.textFields["coach-composer"]; composer.tap(); composer.typeText("preserve draft")
        XCTAssertTrue(app.buttons["coach-latest"].exists, "Typing while reading must not jump")
        app.buttons["coach-send"].tap()
        let arrival = app.staticTexts["Synthetic arrival at the actual bottom."]
        XCTAssertTrue(arrival.waitForExistence(timeout: 8)); XCTAssertTrue(arrival.isHittable)
        let sent = XCTAttachment(screenshot: app.screenshot()); sent.name = "coach-history-own-send-bottom"; sent.lifetime = .keepAlways; add(sent)
        for _ in 0..<18 { if app.buttons["coach-earlier"].isHittable { break }; app.scrollViews.firstMatch.swipeDown() }
        let earlier = app.buttons["coach-earlier"]; XCTAssertTrue(earlier.isHittable); earlier.tap()
        XCTAssertTrue(app.staticTexts["Archived synthetic exercise 0"].waitForExistence(timeout: 5))
        let archived = XCTAttachment(screenshot: app.screenshot()); archived.name = "coach-history-earlier-revealed"; archived.lifetime = .keepAlways; add(archived)
        app.buttons["coach-latest"].tap(); XCTAssertTrue(arrival.isHittable)
    }
    @MainActor func testLargeArchiveHasBoundedRenderedPage() {
        for count in [200, 1000] {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-history"
            app.launchEnvironment["KM_COACH_ARCHIVE_COUNT"] = String(count)
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            let start = Date()
            app.launch(); XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
            XCTAssertTrue(app.textFields["coach-answer-history-waiting"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.textFields["coach-answer-history-waiting"].isHittable)
            print("COACH_UI_BENCH count=\(count) initial_seconds=\(Date().timeIntervalSince(start))")
            for _ in 0..<20 { if app.buttons["coach-earlier"].isHittable { break }; app.scrollViews.firstMatch.swipeDown() }
            let reveal = Date(); app.buttons["coach-earlier"].tap()
            XCTAssertTrue(app.staticTexts["Archived synthetic exercise \(count - 50)"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Archived synthetic exercise 0"].exists)
            XCTAssertTrue(app.textFields["coach-answer-history-archived-\(count - 50)"].exists)
            print("COACH_UI_BENCH count=\(count) reveal_seconds=\(Date().timeIntervalSince(reveal)) page=50")
            app.terminate()
        }
    }
}
