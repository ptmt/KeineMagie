import XCTest

final class DatasetLoadingUITests: XCTestCase {
    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testInitialLoadingIsLocalAndDoesNotClaimDisconnectedProvider() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "delayed-populated"
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.textViews["translator-input"].waitForExistence(timeout: 8))
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "native-provider-loading"; before.lifetime = .keepAlways; add(before)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "history.loading").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "provider.loading").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["No translations yet."].exists)
        screenshot(app, "history-slow-quiet-initial")
        // Deliberately stay pending beyond the old requested three-second threshold.
        let quietUntil = Date().addingTimeInterval(4)
        while Date() < quietUntil {
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "history.loading").firstMatch.exists)
            XCTAssertFalse(app.staticTexts["No translations yet."].exists)
        }
        screenshot(app, "history-slow-quiet-after-three-seconds")
        XCTAssertFalse(app.buttons["Connect ChatGPT"].exists, "Unknown provider status is not disconnected")
        XCTAssertTrue(app.buttons["translator-submit"].exists)
        app.tabBars.buttons["Coach"].tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "history.loading").firstMatch.exists)
        app.tabBars.buttons["Translator"].tap()
        XCTAssertTrue(app.staticTexts["No translations yet."].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "history.loading").firstMatch.exists)
        screenshot(app, "history-verified-empty-after-slow-load")
    }

    @MainActor func testFastHistoryAndTabReturnStayQuiet() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "history-populated"
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "history-row-synthetic-history-1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "history.loading").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "provider.loading").firstMatch.exists)
        screenshot(app, "history-fast-populated-quiet")
        app.tabBars.buttons["Coach"].tap(); app.tabBars.buttons["Translator"].tap()
        XCTAssertTrue(row.exists)
        XCTAssertFalse(app.staticTexts["No translations yet."].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "history.loading").firstMatch.exists)
    }
    @MainActor func testPendingPreparationSurvivesBackNavigationAndForeground() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "podcast-prepare"
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Podcasts"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Podcasts"].tap()
        let feed = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic language podcast")).firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 8)); feed.tap()
        let prepare = app.buttons["podcast-prepare-episode-one"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5)); prepare.doubleTap()
        XCTAssertFalse(prepare.isEnabled)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(feed.waitForExistence(timeout: 3)); feed.tap()
        XCTAssertFalse(prepare.isEnabled)
        let pending = XCTAttachment(screenshot: app.screenshot()); pending.lifetime = .keepAlways; pending.name = "pending-after-navigation"; add(pending)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Transcribing")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(prepare.exists)
        let accepted = XCTAttachment(screenshot: app.screenshot()); accepted.lifetime = .keepAlways; accepted.name = "one-accept-after-foreground"; add(accepted)
    }
    @MainActor func testEpisodePrepareImmediatelyDisablesAndStaysAssociated() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "podcast-prepare"
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Podcasts"].waitForExistence(timeout: 10)); app.tabBars.buttons["Podcasts"].tap()
        let feed = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic language podcast")).firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 8)); feed.tap()
        let prepare = app.buttons["podcast-prepare-episode-one"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5)); prepare.tap()
        XCTAssertFalse(prepare.isEnabled)
        XCTAssertTrue(app.staticTexts["Queued"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Transcribing")).firstMatch.waitForExistence(timeout: 12))
        XCTAssertFalse(prepare.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; shot.name = "synthetic-associated-episode"; add(shot)
    }
    @MainActor func testProtectedCacheRelaunchRetainsRowsDuringDelayAndAfterError() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "cache-populated"
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        let row = app.cells.containing(.other, identifier: "history-row-synthetic-history-1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeRight()
        app.buttons["history-favorite-synthetic-history-1"].tap()
        XCTAssertTrue(app.images["history-star-synthetic-history-1"].waitForExistence(timeout: 5))
        let deleted = app.cells.containing(.other, identifier: "history-row-synthetic-history-2").firstMatch
        deleted.swipeLeft(); app.buttons["history-delete-synthetic-history-2"].tap()
        XCTAssertTrue(deleted.waitForNonExistence(timeout: 5))
        app.tabBars.buttons["Podcasts"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic latest episode"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Subscribed podcasts"].exists)
        XCTAssertTrue(app.navigationBars["Podcasts"].exists)
        app.terminate()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "cache-delayed-error"
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["history-star-synthetic-history-1"].exists)
        XCTAssertFalse(deleted.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "history.loading").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "provider.loading").firstMatch.exists)
        screenshot(app, "history-cached-relaunch-during-refresh")
        app.tabBars.buttons["Podcasts"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic latest episode"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No podcasts yet"].exists)
        let cached = XCTAttachment(screenshot: app.screenshot()); cached.lifetime = .keepAlways; cached.name = "protected-cache-before-network"; add(cached)
        XCTAssertTrue(app.staticTexts["podcast.error"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Synthetic latest episode"].exists)
        let failure = XCTAttachment(screenshot: app.screenshot()); failure.lifetime = .keepAlways; failure.name = "protected-cache-retained-on-error"; add(failure)
        app.tabBars.buttons["Translator"].tap()
        XCTAssertTrue(row.exists)
        XCTAssertTrue(app.images["history-star-synthetic-history-1"].exists)
        XCTAssertFalse(deleted.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "history.loading").firstMatch.exists)
        screenshot(app, "history-cached-retained-after-error")
    }
    @MainActor func testDelayedFirstLoadsNeverShowEmptyStates() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "delayed-populated"
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "history.loading").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["No translations yet."].exists)
        app.tabBars.buttons["Podcasts"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "podcast.loading").firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["No podcasts yet"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic latest episode"].waitForExistence(timeout: 20))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; shot.name = "synthetic-loaded-after-delay"; add(shot)
    }
}
