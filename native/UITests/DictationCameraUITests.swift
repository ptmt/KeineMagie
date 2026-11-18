import XCTest

/// Synthetic camera transport, real on-device Vision. Physical camera still needs an iPhone.
final class DictationCameraUITests: XCTestCase {
    @MainActor func testPhotographPreviewExplicitAppendCancelAndUnavailableCamera() throws {
        let app = try launch()
        let draft = app.textFields["dictation-draft"]
        XCTAssertTrue(draft.waitForExistence(timeout:15))
        draft.tap(); draft.typeText("My existing answer")
        let camera = app.buttons["dictation-camera"]
        XCTAssertGreaterThanOrEqual(camera.frame.width,44)
        XCTAssertGreaterThanOrEqual(camera.frame.height,44)
        camera.tap()
        let capture = app.buttons["dictation.camera.simulatorFixture"]
        XCTAssertTrue(capture.waitForExistence(timeout:5)); capture.tap()
        let preview = app.textViews["dictation-camera-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout:30))
        XCTAssertFalse((preview.value as? String ?? "").isEmpty)
        screenshot(app,"camera-real-Vision-editable-preview")
        preview.tap(); preview.typeText(" Edited")
        app.buttons["dictation-camera-insert"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout:5))
        let appended = try XCTUnwrap(draft.value as? String)
        XCTAssertTrue(appended.hasPrefix("My existing answer\n"))
        XCTAssertTrue(appended.contains("Edited"))
        XCTAssertFalse(app.staticTexts["Exact text comparison, not a language-level assessment."].exists)
        XCTAssertFalse(app.staticTexts["dictation-revealed"].exists)
        screenshot(app,"camera-explicit-append-preserves-answer")
        camera.tap(); capture.tap()
        XCTAssertTrue(preview.waitForExistence(timeout:30))
        app.buttons["dictation-camera-cancel"].tap()
        XCTAssertEqual(draft.value as? String,appended)
        camera.tap();capture.tap()
        XCTAssertTrue(preview.waitForExistence(timeout:30))
        let replacement=try XCTUnwrap(preview.value as? String)
        app.switches["dictation-camera-replace"].tap()
        app.buttons["dictation-camera-insert"].tap()
        XCTAssertEqual(draft.value as? String,replacement)
        screenshot(app,"camera-explicit-replace-only-after-toggle")
        camera.tap()
        app.buttons["dictation-camera-take-photo"].tap()
        XCTAssertTrue(app.staticTexts["dictation.camera.error"].waitForExistence(timeout:5))
        screenshot(app,"camera-unavailable-safe-simulator")
        app.buttons["dictation-camera-cancel"].tap()
        XCTAssertEqual(draft.value as? String,replacement)
    }
    @MainActor private func launch() throws -> XCUIApplication {
        let url=URL(fileURLWithPath:"/Users/tinyserve/.hermes/cache/scratch/dictation-camera-player/fixture/fixture.json")
        let data=try Data(contentsOf:url)
        let info=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:String])
        let app=XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"]="dictation-local"
        app.launchEnvironment["KM_DICTATION_FIXTURE_TOKEN"]=info["native"]
        app.launchEnvironment["KM_DICTATION_CAMERA_FIXTURE"]="1"
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"]=UUID().uuidString
        app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        let tab=app.tabBars.buttons["Dictation"]
        XCTAssertTrue(tab.waitForExistence(timeout:15));tab.tap()
        app.buttons["dictation-add"].tap()
        let title=app.textFields["dictation-title"]
        XCTAssertTrue(title.waitForExistence(timeout:5));title.tap();title.typeText("Photo answer")
        app.textViews["dictation-original"].tap();app.textViews["dictation-original"].typeText("Heute scheint die Sonne.")
        app.buttons["dictation-create"].tap()
        return app
    }
    @MainActor private func screenshot(_ app:XCUIApplication,_ name:String) {
        let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
}
