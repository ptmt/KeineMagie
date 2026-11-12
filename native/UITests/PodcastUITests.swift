import XCTest

final class PodcastUITests: XCTestCase {
    @MainActor private func launch(_ mode: String = "podcast-populated") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = mode
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Podcasts"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Podcasts"].tap()
        return app
    }
    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func section(_ key: String, in app: XCUIApplication) {
        let button = app.buttons["episode-section-" + key]
        let strip = app.scrollViews.containing(.button, identifier: "episode-section-summary").firstMatch
        for _ in 0..<5 {
            if button.frame.minX >= 0 && button.frame.maxX <= app.frame.maxX - 52 { break }
            if key == "transcript" { strip.swipeLeft() } else { strip.swipeRight() }
        }
        XCTAssertTrue(button.isHittable); button.tap()
    }
    @MainActor func testTimelineSearchSummaryCitationAndProfile() {
        let app = launch("podcast-timeline")
        let episode = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "episode-1.mp3")).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 8)); episode.tap()
        XCTAssertTrue(app.buttons["episode-section-summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["episode-timeline"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["episode-profile"].frame.height, 43.99)
        app.sliders["episode-timeline"].adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertFalse(app.staticTexts["Synthetic segment 0"].isHittable)
        screenshot(app, "synthetic-timeline-initial")
        section("summary", in: app)
        XCTAssertTrue(app.staticTexts["Synthetic saved summary"].waitForExistence(timeout: 5))
        app.buttons["episode-citation-2012"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Synthetic segment 2012"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["335:20"].exists)
        screenshot(app, "synthetic-timeline-citation")
        section("transcript", in: app)
        let search = app.textFields["episode-search"]
        search.tap(); search.typeText("Перевод 2050")
        app.buttons["episode-next-match"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic segment 2050"].waitForExistence(timeout: 5))
        screenshot(app, "synthetic-timeline-search")
        let time = app.textFields["episode-time"]
        time.tap(); time.typeText("335:29")
        app.buttons["episode-jump"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic segment 2012"].waitForExistence(timeout: 5))
        section("vocabulary", in: app)
        XCTAssertTrue(app.staticTexts["Alltag"].waitForExistence(timeout: 5))
        screenshot(app, "synthetic-timeline-vocabulary")
        app.buttons["episode-profile"].tap()
        XCTAssertTrue(app.buttons["profile-cefr"].waitForExistence(timeout: 5))
        app.buttons["profile-cefr"].tap()
        app.buttons["B2"].tap()
        XCTAssertTrue(app.buttons["profile-save"].isEnabled)
        app.buttons["profile-save"].tap()
        let assessment = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "B2, ")).firstMatch
        for _ in 0..<4 { if assessment.exists { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(assessment.waitForExistence(timeout: 5))
        screenshot(app, "synthetic-timeline-profile")
    }
    @MainActor func testSavedEpisodeSummaryAndProfileSurviveOfflineRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "cache-populated"
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Podcasts"].waitForExistence(timeout: 10)); app.tabBars.buttons["Podcasts"].tap()
        let episode = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "episode-1.mp3")).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 5)); episode.tap()
        section("summary", in: app)
        XCTAssertTrue(app.staticTexts["Synthetic saved summary"].waitForExistence(timeout: 5))
        app.buttons["episode-profile"].tap()
        XCTAssertTrue(app.buttons["profile-cefr"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.terminate()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "cache-offline"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Podcasts"].waitForExistence(timeout: 5)); app.tabBars.buttons["Podcasts"].tap()
        for _ in 0..<5 {
            if episode.exists && episode.frame.minY < 700 { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(episode.waitForExistence(timeout: 5)); episode.tap()
        section("summary", in: app)
        XCTAssertTrue(app.staticTexts["Synthetic saved summary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Retry"].exists)
        screenshot(app, "synthetic-offline-saved-summary")
        app.buttons["episode-profile"].tap()
        XCTAssertTrue(app.buttons["profile-cefr"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profile-cefr"].isEnabled)
        screenshot(app, "synthetic-offline-saved-profile")
    }
    @MainActor func testPopulatedListFeedDetailAndBottomSafeArea() {
        let app = launch()
        let feed = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic language podcast")).firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Synthetic latest episode"].exists)
        XCTAssertTrue(app.navigationBars["Podcasts"].exists)
        XCTAssertFalse(app.navigationBars["Keine Magie"].exists)
        screenshot(app, "synthetic-podcasts-populated")
        feed.tap()
        XCTAssertTrue(app.staticTexts["Synthetic episode one"].waitForExistence(timeout: 5))
        screenshot(app, "synthetic-podcasts-feed-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<5 { app.swipeUp() }
        let last = app.staticTexts["episode-18.mp3"]
        XCTAssertTrue(last.waitForExistence(timeout: 3))
        XCTAssertLessThan(last.frame.maxY, app.tabBars.firstMatch.frame.minY)
        screenshot(app, "synthetic-podcasts-bottom")
    }
    @MainActor func testEpisodeDetailIdentifiesEpisodeAndActiveProgress() {
        let app = launch()
        let ready = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "episode-1.mp3")).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 8)); ready.tap()
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "native-episode-ready"; before.lifetime = .keepAlways; add(before)
        XCTAssertTrue(app.staticTexts["podcast-detail-title"].exists)
        XCTAssertFalse(app.progressIndicators["podcast-detail-progress"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic transcript"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let active = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "episode-2.mp3")).firstMatch
        XCTAssertTrue(active.exists); active.tap()
        XCTAssertTrue(app.progressIndicators["podcast-detail-progress"].exists)
        let processing = XCTAttachment(screenshot: app.screenshot())
        processing.name = "native-episode-processing"; processing.lifetime = .keepAlways; add(processing)
    }

    @MainActor func testDetailRefreshUpdatesInPlaceAndShowsFailure() {
        let app = launch()
        let feed = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic language podcast")).firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 8)); feed.tap()
        app.buttons["Refresh feed"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic refreshed episode"].waitForExistence(timeout: 8))
        screenshot(app, "synthetic-podcasts-refreshed-detail")
        app.terminate()
        let failure = launch("podcast-refresh-failure")
        let failedFeed = failure.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic language podcast")).firstMatch
        XCTAssertTrue(failedFeed.waitForExistence(timeout: 8)); failedFeed.tap()
        failure.buttons["Refresh feed"].tap()
        XCTAssertTrue(failure.staticTexts["podcast.error"].waitForExistence(timeout: 8))
        XCTAssertTrue(failure.staticTexts["Synthetic episode one"].exists)
        screenshot(failure, "synthetic-podcasts-refresh-error")
    }
    @MainActor func testEmptyPlusGuardAndFailedImportStaysVisible() {
        let app = launch("podcast-failure")
        XCTAssertTrue(app.staticTexts["No podcasts yet"].waitForExistence(timeout: 8))
        screenshot(app, "synthetic-podcasts-empty")
        app.buttons["podcast-add"].tap()
        let submit = app.buttons["podcast-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        XCTAssertFalse(submit.isEnabled)
        screenshot(app, "synthetic-podcasts-add-sheet")
        let url = app.textFields["podcast-url"]
        url.tap(); url.typeText("file:///private/test")
        XCTAssertFalse(submit.isEnabled)
        // Clear the whole field without depending on a localized edit menu.
        url.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 100))
        url.typeText("https://audio.example/episode.mp3")
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: submit)
        waitForExpectations(timeout: 8)
        submit.tap()
        XCTAssertTrue(app.staticTexts["podcast-add-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(url.exists)
        screenshot(app, "synthetic-podcasts-failed-import")
    }
    @MainActor func testAccountReplacementDismissesDraftAndRejectsLateImport() {
        let app = launch("account-change")
        XCTAssertTrue(app.staticTexts["No podcasts yet"].waitForExistence(timeout: 8))
        app.buttons["podcast-add"].tap()
        let url = app.textFields["podcast-url"]
        XCTAssertTrue(url.waitForExistence(timeout: 3))
        url.tap(); url.typeText("https://audio.example/old-account.mp3")
        app.buttons["podcast-submit"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.tabBars.buttons["Translator"].waitForExistence(timeout: 10))
        // Root identity epoch reconstructs the tab subtree, including its presented sheet.
        let dismissed = NSPredicate(format: "exists == false")
        expectation(for: dismissed, evaluatedWith: app.textFields["podcast-url"])
        waitForExpectations(timeout: 12)
        app.tabBars.buttons["Podcasts"].tap()
        XCTAssertTrue(app.staticTexts["No podcasts yet"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["episode-1.mp3"].exists)
        XCTAssertFalse(app.staticTexts["podcast.error"].exists)
        screenshot(app, "synthetic-podcasts-account-replacement")
    }
    @MainActor func testPodcastLabelsAndSheetInFiveLocales() {
        for (locale, title, add) in [("de", "Podcasts", "Podcast hinzufügen"), ("en", "Podcasts", "Add podcast"), ("ru", "Подкасты", "Добавить подкаст"), ("es", "Podcasts", "Añadir podcast"), ("fr", "Podcasts", "Ajouter un podcast")] {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "valid"
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
            app.launch()
            XCTAssertTrue(app.tabBars.buttons[title].waitForExistence(timeout: 10))
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].exists)
            app.buttons["podcast-add"].tap()
            XCTAssertTrue(app.navigationBars[add].waitForExistence(timeout: 5))
            screenshot(app, "synthetic-podcasts-add-\(locale)")
            app.terminate()
        }
    }
    @MainActor func testAllTabsHaveCompactTabNameHeaders() {
        let app = launch("valid")
        for title in ["Translator", "Dictation", "Podcasts", "Coach"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
            XCTAssertFalse(app.navigationBars["Keine Magie"].exists)
            screenshot(app, "synthetic-compact-header-\(title)")
        }
    }
}
