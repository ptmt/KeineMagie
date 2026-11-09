import XCTest

final class ForegroundUITests: XCTestCase {
    func testKnownSessionKeepsTranslatorAndDraftAcrossForegroundCycles() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "valid"
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        let draft = app.textViews["Text zum Übersetzen"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Verbinden – in Planung"].exists)
        draft.tap()
        draft.typeText("Synthetic foreground fixture")
        for cycle in 1...3 {
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(draft.exists, "Translator disappeared during foreground cycle \(cycle)")
            XCTAssertEqual(draft.value as? String, "Synthetic foreground fixture")
            XCTAssertFalse(app.progressIndicators["Sitzung wird geprüft …"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "synthetic-translator-foreground-\(cycle)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    func testAccountChangeClearsContentAndRejectsPendingTranslation() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "account-change"
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        let draft = app.textViews["Text zum Übersetzen"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Synthetic account A history"].waitForExistence(timeout: 5))
        draft.tap()
        draft.typeText("Account A private draft")
        app.swipeUp()
        app.buttons["Übersetzen"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        let emptyHistory = app.staticTexts["Noch keine Übersetzungen."]
        XCTAssertTrue(emptyHistory.waitForExistence(timeout: 10))
        app.swipeDown()
        XCTAssertEqual(draft.value as? String, "")
        XCTAssertTrue(app.staticTexts["ChatGPT nicht verbunden"].exists)
        // Wait beyond the deliberately late account A translation response.
        XCTAssertFalse(app.staticTexts["Synthetic stale account A result"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Synthetic account A history"].exists)
        XCTAssertEqual(draft.value as? String, "")
        XCTAssertTrue(app.textViews.firstMatch.exists, "Account B stays signed in; generation (not phase) must reset the model")
    }

    func testSettingsDisplaysInstalledVersionAndBuild() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "valid"
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10))
        app.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.staticTexts["app-version-build"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["app-version-build"].label.contains("1.0 (1)"))
    }

    func testRevokedSessionLeavesTranslatorOnForeground() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "revoked"
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Mit Apple anmelden"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textViews.firstMatch.exists)
    }
}
