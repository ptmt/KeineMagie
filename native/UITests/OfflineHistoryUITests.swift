import XCTest

final class OfflineHistoryUITests: XCTestCase {
    @MainActor func testColdRelaunchUnreachableShowsSavedOwnerHistoryAndAllTabs() { exercise(mode: "cache-offline") }
    @MainActor func testColdRelaunchBlackholeShowsHistoryBeforeBoundedTimeoutAndForegroundKeepsTab() { exercise(mode: "cache-blackhole") }
    @MainActor private func exercise(mode: String) {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "cache-populated"
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "history-row-synthetic-history-1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        app.tabBars.buttons["Podcasts"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic latest episode"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = mode
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Local history must not await session network")
        XCTAssertFalse(app.buttons["translator-submit"].isEnabled)
        let before = XCTAttachment(screenshot: app.screenshot()); before.name = "\(mode)-saved-before-network"; before.lifetime = .keepAlways; add(before)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "offline.saved-history").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(row.exists)
        let copy = app.buttons["history-copy-synthetic-history-1"]
        if !copy.isHittable { app.swipeUp() }
        XCTAssertTrue(copy.exists); copy.tap()
        for tab in ["Dictation", "Coach", "Podcasts"] {
            XCTAssertTrue(app.tabBars.buttons[tab].isEnabled); app.tabBars.buttons[tab].tap()
        }
        XCTAssertTrue(app.staticTexts["Synthetic latest episode"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["podcast-add"].isEnabled)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.navigationBars["Podcasts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic latest episode"].exists)
        let after = XCTAttachment(screenshot: app.screenshot()); after.name = "\(mode)-podcasts-after-foreground"; after.lifetime = .keepAlways; add(after)
    }
}
