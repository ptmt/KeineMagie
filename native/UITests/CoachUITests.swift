import XCTest
import UIKit

final class CoachUITests: XCTestCase {
    @MainActor func testComposerMenuOpensWithoutSendingOrRevealing() {
        let app = launch()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8))
        let composer = app.textFields["coach-composer"]
        composer.tap(); composer.typeText("keep my draft")
        let actions = app.buttons["coach-actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(actions.frame.width, 44)
        XCTAssertGreaterThanOrEqual(actions.frame.height, 44)
        XCTAssertLessThanOrEqual(actions.frame.maxX, composer.frame.minX)
        XCTAssertFalse(app.buttons["coach-reveal"].exists)
        shot(app, "coach-composer-menu-closed-keyboard")
        actions.tap()
        XCTAssertTrue(app.buttons["coach-reveal"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["coach-progress"].exists)
        XCTAssertFalse(app.staticTexts["Ich warte auf den Bus."].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic progress:")).firstMatch.exists)
        XCTAssertEqual(composer.value as? String, "keep my draft")
        shot(app, "coach-composer-menu-open-keyboard")
    }
    @MainActor func testMenuSelectionUsesOriginalRoutesExactlyOnceAndKeepsFocus() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-menu-probe"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        let receipt = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic commands:")).firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 8))
        let composer = app.textFields["coach-composer"]
        composer.tap(); composer.typeText("draft")
        let before = receipt.label
        let actions = app.buttons["coach-actions"]
        actions.tap()
        XCTAssertTrue(app.buttons["coach-reveal"].waitForExistence(timeout: 3))
        XCTAssertEqual(receipt.label, before)
        app.navigationBars.staticTexts["Coach"].tap() // Dismiss without selecting.
        XCTAssertTrue(app.buttons["coach-reveal"].waitForNonExistence(timeout: 3))
        composer.typeText("!") // No second tap: native focus must survive dismissal.
        XCTAssertEqual(composer.value as? String, "draft!")
        XCTAssertEqual(receipt.label, before)
        actions.tap(); app.buttons["coach-reveal"].tap()
        XCTAssertTrue(app.staticTexts["Ich warte auf den Bus."].waitForExistence(timeout: 8))
        XCTAssertEqual(receipt.label, before + ";reveal|source|synthetic-coach")
        XCTAssertEqual(composer.value as? String, "draft!")
        actions.tap(); app.buttons["coach-progress"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic progress:")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(receipt.label, before + ";reveal|source|synthetic-coach;progress|My progress|")
        XCTAssertEqual(composer.value as? String, "draft!")
        let log = XCTAttachment(string: receipt.label); log.name = "coach-menu-transport-receipt"; log.lifetime = .keepAlways; add(log)
    }
    @MainActor func testMenuIncludesEveryAvailableAction() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach"
        app.launchEnvironment["KM_SIMULATOR_COACH_ALL_ACTIONS"] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.buttons["coach-actions"].waitForExistence(timeout: 8))
        app.buttons["coach-actions"].tap()
        for action in ["reveal", "progress", "explain", "more", "practice"] {
            XCTAssertTrue(app.buttons["coach-" + action].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["coach-" + action].isHittable)
            XCTAssertEqual(app.buttons.matching(identifier: "coach-" + action).count, 1)
        }
        shot(app, "coach-menu-all-available-actions")
    }
    @MainActor func testMenuDisabledDuringAssessmentAndOffline() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-assessment"
        app.launchEnvironment["KM_SIMULATOR_COACH_CHECK_CAPTURE"] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        let answer = app.textFields["coach-answer-synthetic-coach"]
        XCTAssertTrue(answer.waitForExistence(timeout: 8)); answer.tap(); answer.typeText("beim")
        app.buttons["coach-check-synthetic-coach"].tap()
        XCTAssertTrue(app.staticTexts["Checking…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["coach-actions"].isEnabled, "Keep the menu discoverable; disable its commands")
        app.buttons["coach-actions"].tap()
        XCTAssertTrue(app.buttons["coach-progress"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["coach-progress"].isEnabled)
        XCTAssertFalse(app.buttons["coach-reveal"].isEnabled)
        app.navigationBars.staticTexts["Coach"].tap()
        XCTAssertFalse(app.buttons["coach-send"].isEnabled)
        XCTAssertTrue(app.staticTexts["Incorrect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["coach-actions"].isEnabled)
        app.terminate()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-menu-offline"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.textFields["coach-answer-synthetic-coach"].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home); sleep(1); app.activate()
        XCTAssertTrue(app.staticTexts["Offline. Showing saved history"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["coach-actions"].isEnabled, "Keep the menu discoverable; disable its commands")
        app.buttons["coach-actions"].tap()
        XCTAssertTrue(app.buttons["coach-progress"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["coach-progress"].isEnabled)
        XCTAssertFalse(app.buttons["coach-reveal"].isEnabled)
        app.navigationBars.staticTexts["Coach"].tap()
        XCTAssertFalse(app.buttons["coach-send"].isEnabled)
        shot(app, "coach-menu-offline-disabled")
    }
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
        XCTAssertTrue(app.buttons["coach-actions"].exists)
        XCTAssertFalse(app.buttons["coach-reveal"].exists)
        XCTAssertFalse(app.buttons["coach-progress"].exists)
        XCTAssertFalse(check.isEnabled)
        answer.tap(); answer.typeText("auf")
        XCTAssertTrue(check.isEnabled)
        XCTAssertLessThanOrEqual(check.frame.maxY, app.otherElements["coach-composer-container"].frame.minY - 8, "The whole Check target must remain above the contextual controls after keyboard presentation")
        XCTAssertLessThanOrEqual(skip.frame.maxY, app.otherElements["coach-composer-container"].frame.minY - 8)
        shot(app, "coach-design-filled-keyboard-before-or-after")
        app.buttons["coach-actions"].tap()
        XCTAssertTrue(app.buttons["coach-reveal"].waitForExistence(timeout: 3))
        app.navigationBars.staticTexts["Coach"].tap()
        answer.typeText(XCUIKeyboardKey.delete.rawValue); answer.typeText("f")
        XCTAssertEqual(answer.value as? String, "auf")
        XCTAssertLessThanOrEqual(check.frame.maxY, app.otherElements["coach-composer-container"].frame.minY - 8)
        XCTAssertLessThanOrEqual(skip.frame.maxY, app.otherElements["coach-composer-container"].frame.minY - 8)
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

    @MainActor func testContextualMenuAndProgressRetainDraft() {
        let app = launch()
        XCTAssertTrue(app.buttons["coach-actions"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["coach-progress"].exists)
        XCTAssertFalse(app.buttons["coach-reveal"].exists)
        let answer = app.textFields["coach-answer-synthetic-coach"]
        answer.tap(); answer.typeText("für"); app.buttons["coach-check-synthetic-coach"].tap()
        XCTAssertTrue(app.staticTexts["Needs practice"].waitForExistence(timeout: 8))
        shot(app, "coach-contextual-after-feedback-release")
        let composer = app.textFields["coach-composer"]; composer.tap(); composer.typeText("keep my draft")
        app.buttons["coach-actions"].tap()
        XCTAssertTrue(app.buttons["coach-progress"].waitForExistence(timeout: 3))
        app.buttons["coach-progress"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic progress:")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(composer.value as? String, "keep my draft")
        let summary = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic progress:")).firstMatch
        XCTAssertLessThanOrEqual(summary.frame.maxY, composer.frame.minY - 8)
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
        app.buttons["coach-actions"].tap()
        XCTAssertTrue(app.buttons["coach-reveal"].waitForExistence(timeout: 3))
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
            let actionLabels = ["en": "Coach actions", "de": "Coach-Aktionen", "ru": "Действия тренера", "es": "Acciones del entrenador", "fr": "Actions du coach"]
            let actions = app.buttons["coach-actions"]
            XCTAssertTrue(actions.waitForExistence(timeout: 8))
            XCTAssertEqual(actions.label, actionLabels[locale])
            actions.tap()
            XCTAssertTrue(app.buttons["coach-reveal"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["coach-progress"].isHittable)
            shot(app, "coach-menu-normal-\(locale)")
            app.navigationBars.firstMatch.staticTexts.firstMatch.tap()
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
            let actions = app.buttons["coach-actions"]
            XCTAssertTrue(actions.waitForExistence(timeout: 8))
            XCTAssertGreaterThanOrEqual(actions.frame.width, 44)
            XCTAssertGreaterThanOrEqual(actions.frame.height, 44)
            let composer = app.textFields["coach-composer"]
            let placeholder = composer.label
            let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
            XCTAssertGreaterThanOrEqual(composer.frame.width, ceil((placeholder as NSString).size(withAttributes: [.font: font]).width) + 4)
            shot(app, "coach-largest-native-placeholder-\(locale)")
            composer.tap(); composer.typeText("exact draft")
            XCTAssertEqual(composer.value as? String, "exact draft")
            XCTAssertTrue(actions.isHittable)
            XCTAssertLessThanOrEqual(actions.frame.maxY, app.keyboards.firstMatch.frame.minY)
            actions.tap()
            let progress = app.buttons["coach-progress"]
            XCTAssertTrue(progress.waitForExistence(timeout: 3))
            XCTAssertGreaterThanOrEqual(progress.frame.height, 44)
            // Native menus include system vertical padding, unlike the removed chips.
            // Bound to ONE full-size line plus native padding, not an arbitrary chip height.
            XCTAssertLessThanOrEqual(progress.frame.height, ceil(font.lineHeight) + 64, "Short menu title must remain one line at maximum type")
            XCTAssertGreaterThanOrEqual(progress.frame.minY, app.frame.minY)
            XCTAssertLessThanOrEqual(progress.frame.maxY, app.frame.maxY)
            XCTAssertGreaterThanOrEqual(progress.frame.minX, 0)
            XCTAssertLessThanOrEqual(progress.frame.maxX, app.frame.maxX)
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
    @MainActor func testOfflineRecoveryDoesNotAdmitEntryButNextNavigationDoes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-recovery-lifecycle"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic entry count: 1; validations: 1"].waitForExistence(timeout: 8))
        let composer = app.textFields["coach-composer"]
        composer.tap(); composer.typeText("keep recovery draft")
        // Explicit synthetic timeout retains the draft and dismisses the keyboard.
        // Never tap an occluded tab-bar AX node: its coordinate can hit emoji keys.
        app.buttons["coach-send"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCUIDevice.shared.press(.home); sleep(1); app.activate()
        sleep(3) // The fixture's second identity check times out after two seconds.
        XCTAssertFalse(app.buttons["coach-send"].isEnabled)
        func visitTranslatorThenCoach() {
            app.tabBars.buttons["Translator"].tap()
            shot(app, "recovery-translator-navigation")
            let visible = NSPredicate(format: "isHittable == true")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: app.textViews["translator-input"])], timeout: 5), .completed)
            app.tabBars.buttons["Coach"].tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: composer)], timeout: 5), .completed)
        }
        visitTranslatorThenCoach()
        XCTAssertTrue(app.staticTexts["Synthetic entry count: 1; validations: 3"].waitForExistence(timeout: 10))
        XCTAssertEqual(composer.value as? String, "keep recovery draft")
        visitTranslatorThenCoach()
        XCTAssertTrue(app.staticTexts["Synthetic entry count: 2; validations: 3"].waitForExistence(timeout: 8))
        XCTAssertEqual(composer.value as? String, "keep recovery draft")
        shot(app, "coach-readonly-recovery-no-entry")
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
        let expected = ["Ich warte ___ den Bus.", "coach-answer-synthetic-coach", "coach-check-synthetic-coach", "label: 'Skip'", "identifier: 'coach-composer'", "coach-actions", "coach-send"]
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
        app.buttons["coach-actions"].tap()
        XCTAssertTrue(app.buttons["coach-progress"].waitForExistence(timeout: 3))
        app.buttons["coach-progress"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Synthetic progress:")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["New messages"].waitForNonExistence(timeout: 8))
        sleep(2)
        shot(app, reduced ? "coach-reduced-arrived-seen" : "coach-motion-arrived-seen")
        if reduced { XCTAssertEqual(app.buttons["coach-actions"].value as? String, "static;system=false;injected=true") }
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
