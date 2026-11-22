import XCTest

final class CoachGlassUITests: XCTestCase {
    @MainActor func testLargestComposerKeyboardAndTargets() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-stable"
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Тренер"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Тренер"].tap()
        let composer = app.textFields["coach-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        composer.tap(); composer.typeText("Draft")
        XCTAssertEqual(composer.value as? String, "Draft")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let container = app.otherElements["coach-composer-container"]
        XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX)
        XCTAssertLessThanOrEqual(container.frame.maxY, keyboard.frame.minY)
        for id in ["coach-actions", "coach-send"] {
            let button = app.buttons[id]
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertLessThanOrEqual(button.frame.maxY, keyboard.frame.minY)
            XCTAssertTrue(button.isHittable)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "glass-russian-AXXXL-keyboard"; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "glass-russian-AXXXL-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    @MainActor func testSystemReduceTransparencyComposer() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        settings.launch()
        // Settings activation can return during the SpringBoard transition;
        // its AX tree exists before it can receive a physical tap.
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        let toggle = settings.switches["Reduce Transparency"]
        if !toggle.exists {
            let accessibility = settings.cells.containing(.staticText, identifier: "Accessibility").firstMatch
            for _ in 0..<6 {
                if accessibility.isHittable { break }
                settings.swipeUp()
            }
            XCTAssertTrue(accessibility.waitForExistence(timeout: 5))
            accessibility.tap()
            let display = settings.cells.containing(.staticText, identifier: "Display & Text Size").firstMatch
            XCTAssertTrue(display.waitForExistence(timeout: 5)); display.tap()
        }
        for _ in 0..<4 {
            if toggle.isHittable { break }
            settings.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        func setToggle(_ value: String) {
            if toggle.value as? String != value {
                // Settings exposes the whole labeled row as the switch; tap its
                // actual trailing thumb rather than the noninteractive label.
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            XCTAssertTrue(toggle.waitForExistence(timeout: 3))
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: toggle)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        }
        let original = toggle.value as? String ?? "0"
        defer {
            settings.activate()
            XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5))
            Thread.sleep(forTimeInterval: 2)
            setToggle(original)
        }
        // Exercise both directions even when the borrowed device starts enabled.
        setToggle("0")
        setToggle("1")
        let settingShot = XCTAttachment(screenshot: settings.screenshot())
        settingShot.name = "reduce-transparency-system-setting-on"; settingShot.lifetime = .keepAlways; add(settingShot)
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "coach-stable"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10)); app.tabBars.buttons["Coach"].tap()
        let composer = app.textFields["coach-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        composer.tap(); composer.typeText("Opaque draft")
        XCTAssertEqual(composer.value as? String, "Opaque draft")
        XCTAssertTrue(app.buttons["coach-send"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "glass-system-reduce-transparency-keyboard"; shot.lifetime = .keepAlways; add(shot)
    }
}
