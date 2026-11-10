import XCTest

final class HistoryUITests: XCTestCase {
    @MainActor func testNativeHistorySwipesAndPersistenceReadback() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "history-populated"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let row = app.cells.containing(.other, identifier: "history-row-synthetic-history-1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        if !row.isHittable { app.swipeUp() }
        row.swipeRight()
        let favorite = app.buttons["history-favorite-synthetic-history-1"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 3))
        screenshot(app, "synthetic-history-right-favorite")
        favorite.tap()
        let star = app.images["history-star-synthetic-history-1"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        screenshot(app, "synthetic-history-star")
        // Returning to translator performs another GET from the fixture's backing state.
        app.tabBars.buttons["Coach"].tap(); app.tabBars.buttons["Translator"].tap()
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        row.swipeRight()
        XCTAssertTrue(app.buttons["Remove favorite"].waitForExistence(timeout: 3))
        app.buttons["Remove favorite"].tap()
        XCTAssertTrue(star.waitForNonExistence(timeout: 5))
        row.swipeLeft()
        let deletion = app.buttons["history-delete-synthetic-history-1"]
        XCTAssertTrue(deletion.waitForExistence(timeout: 3))
        screenshot(app, "synthetic-history-left-delete")
        deletion.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        app.tabBars.buttons["Coach"].tap(); app.tabBars.buttons["Translator"].tap()
        XCTAssertFalse(row.exists)
        XCTAssertTrue(app.cells.containing(.other, identifier: "history-row-synthetic-history-2").firstMatch.exists)
    }
    @MainActor func testDirectionSwitchKeepsDraftAndUsesFullAccessibleNames() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "valid"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let editor = app.textViews["translator-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("Ich hat Zeit")
        let picker = app.segmentedControls["translator-direction"]
        for title in ["Russian to German", "Polish German", "German to Russian"] {
            picker.buttons[title].tap()
            XCTAssertEqual(editor.value as? String, "Ich hat Zeit")
        }
        screenshot(app, "synthetic-direction-compact-preserved-draft")
    }

    @MainActor func testFailedDeleteRetainsRowAndShowsLocalizedError() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "history-failure"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let row = app.cells.containing(.other, identifier: "history-row-synthetic-history-1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["history-delete-synthetic-history-1"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '503'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(row.exists)
        screenshot(app, "synthetic-history-delete-failure-retains-row")
    }

    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
