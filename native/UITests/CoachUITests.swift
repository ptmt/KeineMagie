import XCTest
import UIKit

final class CoachUITests: XCTestCase {
    @MainActor func testLargestRussianNativeComposerPlaceholderFits() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach"
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Тренер"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Тренер"].tap()
        let composer = app.textFields["coach-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        let required = ("Сообщение" as NSString).size(withAttributes: [.font: font]).width
        XCTAssertGreaterThanOrEqual(composer.frame.width, ceil(required) + 4, "Native placeholder must fit without ellipsis")
        shot(app, "coach-russian-native-placeholder-largest")
        composer.tap(); composer.typeText("draft")
        XCTAssertEqual(composer.value as? String, "draft")
        XCTAssertTrue(app.buttons["coach-send"].isHittable)
    }
    @MainActor private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Coach"].tap()
        return app
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    // Run on the released-source baseline before changing CoachView. These
    // assertions describe the requested compact chat controls, not model policy.
    @MainActor func testChatDesignCompactAnswerControls() {
        let app = launch()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8))
        let check = app.buttons["coach-check-synthetic-coach"]
        let skip = app.buttons["Skip"]
        shot(app, "coach-design-active-before-or-after")
        XCTAssertFalse(app.staticTexts["Awaiting answer"].exists,
                       "The editable answer already communicates the awaiting state")
        XCTAssertGreaterThanOrEqual(answer.frame.height, 44)
        XCTAssertGreaterThanOrEqual(check.frame.height, 44)
        XCTAssertLessThanOrEqual(check.frame.height, 52,
                                 "Check should have a compact 44-point target, not a padded oversized pill")
        XCTAssertGreaterThanOrEqual(skip.frame.height, 44)
        XCTAssertGreaterThanOrEqual(skip.frame.minX - check.frame.maxX, 32,
                                    "Quiet Skip belongs at the trailing edge, separate from Check")
        XCTAssertEqual(app.buttons.matching(identifier: "coach-reveal").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "coach-progress").count, 1)
        XCTAssertFalse(check.isEnabled)
        answer.tap(); answer.typeText("auf")
        XCTAssertTrue(check.isEnabled)
        XCTAssertLessThanOrEqual(check.frame.maxY, app.buttons["coach-reveal"].frame.minY - 8, "The whole Check target must remain above the contextual controls after keyboard presentation")
        XCTAssertLessThanOrEqual(skip.frame.maxY, app.buttons["coach-reveal"].frame.minY - 8)
        shot(app, "coach-design-filled-keyboard-before-or-after")
        XCTAssertEqual(answer.value as? String, "auf")
        XCTAssertEqual(app.textFields["coach-composer"].label, "Message",
                       "Discussion stays distinct from the exercise answer")
        check.tap()
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["coach-explanation"].exists)
        shot(app, "coach-design-correct-before-or-after")
    }

    @MainActor func testDesignEmptyEntryAndAssessmentError() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach"
        app.launchEnvironment["KM_SIMULATOR_COACH_DESIGN_ENTRY"] = "1"
        app.launchEnvironment["KM_SIMULATOR_COACH_DESIGN_ERROR"] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        let pending = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Checking…")).firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 3))
        shot(app, "coach-design-empty-daily-loading")
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        answer.tap(); answer.typeText("literal answer")
        app.buttons["coach-check-synthetic-coach"].tap()
        XCTAssertTrue(app.staticTexts["coach-error"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["literal answer"].exists)
        XCTAssertFalse(app.staticTexts["Incorrect"].exists)
        shot(app, "coach-design-assessment-error")
    }

    @MainActor func testContextualChipsAndProgressRetainDraft() {
        let app = launch()
        XCTAssertTrue(app.buttons["coach-progress"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["coach-practice"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "coach-reveal").count, 1)
        let answer = app.textFields["coach-answer-synthetic-coach"]
        answer.tap(); answer.typeText("für"); app.buttons["coach-check-synthetic-coach"].tap()
        XCTAssertTrue(app.buttons["coach-more"].waitForExistence(timeout: 8))
        shot(app, "coach-contextual-after-feedback-release")
        let composer = app.textFields["coach-composer"]; composer.tap(); composer.typeText("keep my draft")
        app.buttons["coach-progress"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic progress:")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(composer.value as? String, "keep my draft")
        let summary = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic progress:")).firstMatch
        XCTAssertLessThanOrEqual(summary.frame.maxY, composer.frame.minY - 44)
        XCTAssertEqual(composer.value as? String, "keep my draft")
        shot(app, "coach-contextual-progress-release")
    }
    @MainActor func testContextualAIAssessmentPendingAndCorrection() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-assessment"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8)); answer.tap(); answer.typeText("beim")
        app.buttons["coach-check-synthetic-coach"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Checking…")).firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["AI check pending…"].exists)
        XCTAssertTrue(app.staticTexts["Checking…"].exists, "Checking must be visible, not only a spinner accessibility label")
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Checking…")).count, 1)
        shot(app, "coach-assessment-pending-synthetic")
        XCTAssertTrue(app.staticTexts["Incorrect"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["beim"].exists)
        XCTAssertTrue(app.staticTexts["bei"].exists)
        XCTAssertTrue(app.staticTexts["coach-explanation"].exists)
        shot(app, "coach-assessment-corrected-synthetic")
    }
    @MainActor func testPopulatedChatExerciseAndKeyboard() {
        let app = launch()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8))
        shot(app, "coach-release-synthetic-chat")
        answer.tap(); answer.typeText("auf")
        let check = app.buttons["coach-check-synthetic-coach"]
        if !check.isHittable { app.scrollViews.firstMatch.swipeUp() }
        check.tap()
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["coach-explanation"].exists)
        XCTAssertFalse(app.buttons["Review observation"].exists)
        shot(app, "coach-release-synthetic-feedback")
        let composer = app.textFields["coach-composer"]
        composer.tap(); composer.typeText("Can you clarify this?")
        XCTAssertTrue(app.buttons["coach-send"].isHittable)
        if app.keyboards.firstMatch.exists { XCTAssertLessThanOrEqual(app.buttons["coach-send"].frame.maxY, app.keyboards.firstMatch.frame.minY + 1) }
        shot(app, "coach-release-keyboard")
        app.buttons["coach-send"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic clarification, not live AI."].waitForExistence(timeout: 8))
        shot(app, "coach-release-clarification")
    }
    @MainActor func testWrongAmbiguousSkipAndCancel() {
        for (answer, feedback) in [("für", "Needs practice"), ("perhaps", "I can’t check this confidently"), ("", "Skipped")] {
            let app = launch()
            if answer.isEmpty { app.buttons["Skip"].tap() }
            else {
                let field = app.textFields["coach-answer-synthetic-coach"]
                XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); field.typeText(answer)
                app.buttons["coach-check-synthetic-coach"].tap()
            }
            XCTAssertTrue(app.staticTexts[feedback].waitForExistence(timeout: 8))
            app.terminate()
        }
        let app = launch()
        let composer = app.textFields["coach-composer"]; composer.tap(); composer.typeText("pending")
        app.buttons["coach-send"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8)); cancel.tap()
        XCTAssertTrue(app.staticTexts["Canceled"].waitForExistence(timeout: 8))
        shot(app, "coach-cancel")
    }
    @MainActor func testSourceControlsAreAbsent() {
        let app = launch()
        XCTAssertTrue(app.textFields["coach-answer-synthetic-coach"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["coach-reveal"].exists)
        app.buttons["coach-reveal"].tap()
        XCTAssertTrue(app.staticTexts["Ich warte auf den Bus."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Source"].exists)
        XCTAssertFalse(app.buttons["coach-source-synthetic-coach"].exists)
    }
    @MainActor func testFiveLocaleCompactFeedback() {
        let samples = [("de", "Richtig"), ("en", "Correct"), ("ru", "Верно"), ("es", "Correcto"), ("fr", "Correct")]
        for (locale, feedback) in samples {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach"
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
            app.launch()
            let tab = app.tabBars.buttons[locale == "ru" ? "Тренер" : locale == "es" ? "Entrenador" : "Coach"]
            XCTAssertTrue(tab.waitForExistence(timeout: 10))
            tab.tap()
            let field = app.textFields["coach-answer-synthetic-coach"]
            XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); field.typeText("auf")
            app.buttons["coach-check-synthetic-coach"].tap()
            XCTAssertTrue(app.staticTexts[feedback].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["coach-explanation"].exists)
            shot(app, "coach-compact-\(locale)")
            app.terminate()
        }
    }
    @MainActor func testFiveLocaleLargestContextActions() {
        for locale in ["en", "de", "ru", "es", "fr"] {
            let app = XCUIApplication()
            app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach"
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            let tab = app.tabBars.buttons[locale == "ru" ? "Тренер" : locale == "es" ? "Entrenador" : "Coach"]
            XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
            let progress = app.buttons["coach-progress"]
            XCTAssertTrue(progress.waitForExistence(timeout: 8))
            XCTAssertGreaterThanOrEqual(progress.frame.height, 44)
            XCTAssertLessThanOrEqual(progress.frame.height, 70, "Context actions must not fragment into syllables at largest type")
            XCTAssertGreaterThanOrEqual(progress.frame.minX, 0)
            XCTAssertLessThanOrEqual(progress.frame.maxX, app.frame.maxX)
            let composer = app.textFields["coach-composer"]
            composer.tap(); composer.typeText("exact draft")
            XCTAssertEqual(composer.value as? String, "exact draft")
            XCTAssertTrue(progress.isHittable)
            shot(app, "coach-largest-context-\(locale)")
            app.terminate()
        }
    }
    @MainActor func testProfileCorrectionAndExclusionReachable() {
        let app = launch()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8)); answer.tap(); answer.typeText("beim")
        app.buttons["coach-check-synthetic-coach"].tap()
        XCTAssertTrue(app.staticTexts["I can’t check this confidently"].waitForExistence(timeout: 8))
        app.buttons["coach-profile"].tap()
        let review = app.buttons["Review observation"]
        for _ in 0..<5 { if review.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(review.isHittable); review.tap()
        XCTAssertTrue(app.buttons["Count as correct"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Count as needs practice"].exists)
        XCTAssertTrue(app.buttons["Exclude"].exists)
        shot(app, "coach-profile-correction-exclusion")
    }
    @MainActor func testOldAnswerCollapsesAndExplicitRevealRestores() {
        let app = launch()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8)); answer.tap(); answer.typeText("auf")
        app.buttons["coach-check-synthetic-coach"].tap()
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 8))
        let composer = app.textFields["coach-composer"]; composer.tap(); composer.typeText("question")
        app.buttons["coach-send"].tap()
        let reveal = app.buttons["Show answer & feedback"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Correct"].exists)
        if !reveal.isHittable { app.scrollViews.firstMatch.swipeDown() }; reveal.tap()
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 8))
        shot(app, "coach-old-answer-revealed")
    }
    @MainActor func testLongHistoryOpensAtBottomWithoutResettingReceipts() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-scroll"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        let last = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic saved message 23.")).firstMatch
        XCTAssertTrue(last.waitForExistence(timeout: 8)); XCTAssertTrue(last.isHittable)
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertTrue(app.buttons["coach-latest"].waitForExistence(timeout: 5))
        app.buttons["coach-latest"].tap(); XCTAssertTrue(last.isHittable)
    }
    @MainActor func testBackgroundReturnConsultsServerAdmissionAndKeepsDraft() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-entry-lifecycle"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic entry count: 1"].waitForExistence(timeout: 8))
        let composer = app.textFields["coach-composer"]; composer.tap(); composer.typeText("keep this draft")
        XCUIDevice.shared.press(.home); sleep(1); app.activate()
        XCTAssertTrue(app.staticTexts["Synthetic entry count: 2"].waitForExistence(timeout: 8))
        XCTAssertEqual(composer.value as? String, "keep this draft")
        shot(app, "coach-background-draft")
    }
    @MainActor func testAccessibilityReadingOrderAndLabels() {
        let app = launch()
        XCTAssertTrue(app.textFields["coach-answer-synthetic-coach"].waitForExistence(timeout: 8))
        let snapshot = app.debugDescription
        let expected = ["Ich warte ___ den Bus.", "coach-answer-synthetic-coach", "coach-check-synthetic-coach", "label: 'Skip'", "coach-progress", "coach-composer", "coach-send"]
        var previous = snapshot.startIndex
        for key in expected {
            guard let range = snapshot.range(of: key, range: previous..<snapshot.endIndex) else { XCTFail("Missing/out-of-order accessible element: \(key)"); continue }
            previous = range.upperBound
        }
        XCTAssertEqual(app.textFields["coach-answer-synthetic-coach"].label, "Answer")
        XCTAssertEqual(app.textFields["coach-composer"].label, "Message")
        XCTAssertEqual(app.buttons["coach-send"].label, "Send")
        let tree = XCTAttachment(string: snapshot); tree.name = "coach-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
        shot(app, "coach-accessibility-order")
    }
    @MainActor private func arrival(reduced: Bool) {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-arrival"
        if reduced { app.launchEnvironment["KM_SIMULATOR_COACH_REDUCE_MOTION"] = "1" }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic exercise, not live AI."].waitForExistence(timeout: 8))
        shot(app, reduced ? "coach-reduced-initial" : "coach-motion-initial")
        sleep(2)
        app.buttons["coach-progress"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic progress:")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["New messages"].waitForNonExistence(timeout: 8))
        sleep(2)
        shot(app, reduced ? "coach-reduced-arrived-seen" : "coach-motion-arrived-seen")
        if reduced { XCTAssertEqual(app.buttons["coach-progress"].value as? String, "static;system=false;injected=true") }
        app.tabBars.buttons["Translator"].tap(); app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic progress:")).firstMatch.waitForExistence(timeout: 8))
        shot(app, reduced ? "coach-reduced-return" : "coach-motion-return")
    }
    @MainActor func testArrivalSurvivesImmediateSeenReceipt() { arrival(reduced: false) }
    @MainActor func testReducedMotionUsesStaticProductionBranch() { arrival(reduced: true) }
    @MainActor func testDarkAccessibilityChatAndProfile() {
        let app = launch(large: true)
        XCTAssertTrue(app.staticTexts["Synthetic exercise, not live AI."].waitForExistence(timeout: 8))
        shot(app, "coach-release-dark-accessibility")
        XCTAssertTrue(app.buttons["coach-profile"].waitForExistence(timeout: 5))
        app.buttons["coach-profile"].tap()
        XCTAssertTrue(app.buttons["profile-cefr"].waitForExistence(timeout: 8))
        app.swipeUp()
        shot(app, "coach-release-profile-accessibility")
    }
}
