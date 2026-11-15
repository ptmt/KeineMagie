import XCTest

final class TranslationFeedbackUITests: XCTestCase {
    @MainActor func testPendingFeedbackFiveLocalesAndStableOutput() {
        for locale in ["en", "de", "ru", "es", "fr"] {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "translation-pending"
            app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
            app.launch()
            let input = app.textViews["translator-input"]
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            input.tap(); input.typeText("Synthetic pending feedback")
            let submit = app.buttons["translator-submit"]
            let output = app.descendants(matching: .any).matching(identifier: "translation-output").firstMatch
            let before = submit.frame
            let outputBefore = output.frame
            submit.tap()
            XCTAssertFalse(submit.isEnabled)
            XCTAssertFalse(app.buttons["translation-copy"].isEnabled)
            XCTAssertEqual(submit.frame.minY, before.minY, accuracy: 1)
            XCTAssertEqual(submit.frame.height, before.height, accuracy: 1)
            XCTAssertEqual(output.frame.minY, outputBefore.minY, accuracy: 1)
            XCTAssertEqual(output.frame.height, outputBefore.height, accuracy: 1)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "translate-pending-" + locale
            attachment.lifetime = .keepAlways; add(attachment)
            print("TRANSLATE_PENDING \(locale) submit=\(submit.frame) output=\(output.frame)")
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            let completed = NSPredicate(format: "enabled == true")
            expectation(for: completed, evaluatedWith: submit)
            waitForExpectations(timeout: 15)
            app.swipeUp()
            XCTAssertTrue(app.buttons["translation-copy"].isEnabled)
            app.terminate()
        }
    }
}
