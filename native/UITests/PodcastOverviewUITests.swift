import XCTest

final class PodcastOverviewUITests: XCTestCase {
    @MainActor private func launch(_ mode: String = "podcast-overview", locale: String = "en", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = mode
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let tab = app.tabBars.buttons[locale == "ru" ? "Подкасты" : "Podcasts"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
        return app
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    @MainActor func testInlineThreeReaderBackAndFullFeed() {
        let app = launch()
        let prefix = "podcast-overview-synthetic-feed-000000001-"
        let first = app.buttons[prefix + "overview-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[prefix + "overview-1"].exists)
        XCTAssertTrue(app.buttons[prefix + "overview-2"].exists)
        XCTAssertFalse(app.buttons[prefix + "overview-3"].exists)
        XCTAssertTrue(first.label.contains("Translated passages 1 / 2"))
        XCTAssertTrue(first.label.contains("Starred passages: 1"))
        XCTAssertFalse(app.buttons[prefix + "overview-1"].label.contains("0 / 0"))
        XCTAssertFalse(app.buttons[prefix + "overview-2"].label.contains("Starred"))
        XCTAssertGreaterThanOrEqual(first.frame.height, 44)
        shot(app, "overview-three-saved-zero-unknown")
        first.tap()
        XCTAssertTrue(app.staticTexts["Synthetic saved passage at zero"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0:00–0:08"].exists)
        shot(app, "overview-reader-zero-timestamp")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let all = app.buttons["podcast-all-synthetic-feed-000000001"]
        XCTAssertTrue(all.exists); XCTAssertGreaterThanOrEqual(all.frame.height, 44); all.tap()
        XCTAssertTrue(app.staticTexts["Older fourth episode"].waitForExistence(timeout: 5))
        shot(app, "overview-all-four")
    }
    @MainActor func testReadOnlyRefreshUpdatesStarsAndRetainsRowsOnFailure() {
        for mode in ["podcast-overview", "podcast-overview-error"] {
            let app = launch(mode)
            let row = app.buttons["podcast-overview-synthetic-feed-000000001-overview-0"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue(row.label.contains("Starred passages: 1"))
            let list = app.collectionViews.firstMatch
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            start.press(forDuration: 0.1, thenDragTo: end)
            if mode.hasSuffix("error") {
                XCTAssertTrue(app.staticTexts["podcast.error"].waitForExistence(timeout: 5))
                XCTAssertTrue(row.label.contains("Starred passages: 1"))
            } else {
                expectation(for: NSPredicate(format: "label CONTAINS %@", "Starred passages: 2"), evaluatedWith: row)
                waitForExpectations(timeout: 5)
            }
            shot(app, mode + "-refresh")
            app.terminate()
        }
    }
    @MainActor func testSameEpisodeIDInSecondFeedOpensUnpreparedDetail() {
        let app = launch()
        let second = app.buttons["podcast-overview-synthetic-feed-000000002-overview-0"]
        for _ in 0..<4 { if second.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(second.label.contains("Not prepared"))
        XCTAssertFalse(second.label.contains("Starred passages"))
        second.tap()
        XCTAssertTrue(app.buttons["podcast-prepare-overview-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["podcast-prepare-overview-0"].isEnabled)
        XCTAssertFalse(app.staticTexts["Synthetic saved passage at zero"].exists)
        shot(app, "overview-duplicate-id-unprepared")
    }
    @MainActor func testActualStageExplicitCancelAndRetry() {
        let app = launch("podcast-overview-actions")
        let row = app.buttons["podcast-overview-synthetic-feed-000000001-overview-0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Transcribing"))
        XCTAssertTrue(app.progressIndicators.firstMatch.exists)
        shot(app, "overview-active-stage")
        app.buttons["Cancel"].firstMatch.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Cancelled"), evaluatedWith: row)
        waitForExpectations(timeout: 5)
        app.buttons["Retry"].firstMatch.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Queued"), evaluatedWith: row)
        waitForExpectations(timeout: 5)
        shot(app, "overview-explicit-retry")
    }
    @MainActor func testReaderKeyboardAndProfile() {
        let app = launch()
        let row = app.buttons["podcast-overview-synthetic-feed-000000001-overview-0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let search = app.textFields["episode-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("second")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        shot(app, "overview-reader-keyboard")
        app.buttons["episode-next-match"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic second passage"].exists)
        app.buttons["episode-profile"].tap()
        XCTAssertTrue(app.buttons["profile-cefr"].waitForExistence(timeout: 5))
        shot(app, "overview-reader-profile")
        app.buttons["Done"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }
    @MainActor func testFiveLocalesAndLargeType() {
        for locale in ["de", "en", "ru", "es", "fr"] {
            let app = launch(locale: locale, large: true)
            let row = app.buttons["podcast-overview-synthetic-feed-000000001-overview-0"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(row.frame.height, 44)
            XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX)
            XCTAssertFalse(row.label.contains("podcast.coverage"))
            shot(app, "overview-large-\(locale)")
            app.terminate()
        }
    }
}
