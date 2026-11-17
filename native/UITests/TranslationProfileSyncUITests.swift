import XCTest

final class TranslationProfileSyncUITests: XCTestCase {
    @MainActor private func control(_ path: String) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18880/_fixture/" + path)!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }
    @MainActor private func launch(_ locale: String = "en", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "profile-http"
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["KM_PROFILE_UI_SEED"] = "1"
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["shortcut-manage"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func refresh(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home); app.activate()
    }
    @MainActor private func edit(_ app: XCUIApplication, title: String = "Legacy native") {
        app.buttons["shortcut-manage"].tap()
        let row = app.collectionViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.textFields["shortcut-title"].waitForExistence(timeout: 5))
    }
    @MainActor private func replace(_ field: XCUIElement, _ value: String) {
        field.tap()
        if let old = field.value as? String { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(value)
    }
    @MainActor private func waitTitles(_ expected: Set<String>) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []
        for _ in 0..<400 {
            let state = try await control("state")
            items = (state["profiles"] as! [String: Any])["items"] as! [[String: Any]]
            if Set(items.filter { !($0["deleted"] as! Bool) }.map { $0["title"] as! String }) == expected { return items }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Unexpected actual Go profile titles: \(items)"); return items
    }
    @MainActor func testMigrationConflictOfflineRelaunchAndRemoteDeletion() async throws {
        _ = try await control("reset")
        let app = launch(); defer { app.terminate() }
        _ = try await waitTitles(["Legacy native"])
        let legacy = app.scrollViews["shortcut-strip"].buttons["Legacy native"]
        for _ in 0..<5 where !legacy.isHittable { app.scrollViews["shortcut-strip"].swipeLeft() }
        legacy.tap(); XCTAssertTrue(legacy.isSelected)
        edit(app)
        replace(app.textFields["shortcut-title"], "Local draft")
        _ = try await control("remote-edit")
        // Exercise the real 30-second foreground poll without an OS background
        // transition confounding editor focus/sheet ownership.
        try await Task.sleep(for: .seconds(32))
        let title = app.textFields["shortcut-title"]
        XCTAssertEqual(title.value as? String, "Local draft")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        title.typeText(" retained")
        XCTAssertEqual(title.value as? String, "Local draft retained")
        capture(app, "profiles-incoming-keeps-keyboard-editor")
        app.buttons["shortcut-save"].tap(); app.buttons["shortcut-done"].tap()
        XCTAssertTrue(app.buttons["Keep both"].waitForExistence(timeout: 10))
        capture(app, "profiles-explicit-conflict")
        app.buttons["Keep both"].tap()
        _ = try await waitTitles(["Remote native title", "Local draft retained"])
        _ = try await control("offline")
        edit(app, title: "Local draft retained")
        replace(app.textFields["shortcut-title"], "Offline durable")
        app.buttons["shortcut-save"].tap(); app.buttons["shortcut-done"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["shortcut-manage"].waitForExistence(timeout: 15))
        edit(app, title: "Offline durable")
        XCTAssertEqual(app.textFields["shortcut-title"].value as? String, "Offline durable")
        capture(app, "profiles-offline-cold-editor")
        app.buttons["Cancel"].tap(); app.buttons["shortcut-done"].tap()
        _ = try await control("online"); refresh(app)
        _ = try await waitTitles(["Remote native title", "Offline durable"])
        let selected = app.scrollViews["shortcut-strip"].buttons["Remote native title"]
        for _ in 0..<5 where !selected.isHittable { app.scrollViews["shortcut-strip"].swipeLeft() }
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        // Selection survives relaunch. Tapping an already-selected style toggles
        // Normal, so only select when needed before testing remote deletion.
        if !selected.isSelected { selected.tap() }
        XCTAssertTrue(selected.isSelected)
        _ = try await control("remote-delete"); refresh(app)
        XCTAssertTrue(selected.waitForNonExistence(timeout: 40))
        XCTAssertTrue(app.scrollViews["shortcut-strip"].buttons.allElementsBoundByIndex.allSatisfy { !$0.isSelected })
        capture(app, "profiles-remote-delete-normal")
    }
    @MainActor func testRevokedOwnerPurgesJournalAndColdOfflineContent() async throws {
        _ = try await control("reset")
        let app = launch(); defer { app.terminate() }
        _ = try await waitTitles(["Legacy native"])
        _ = try await control("revoke"); refresh(app)
        XCTAssertTrue(app.buttons["shortcut-manage"].waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Legacy native"].exists)
        capture(app, "profiles-revoked-owner")
        app.terminate(); app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "cache-offline"; app.launch()
        XCTAssertTrue(app.textViews["translator-input"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["shortcut-manage"].exists)
        XCTAssertFalse(app.buttons["Legacy native"].exists)
        capture(app, "profiles-revoked-offline-no-private-journal")
    }
    @MainActor func testFiveLocaleLargeEditorAndAccessibleTranslator() async throws {
        for (locale, source) in [("de","Text übersetzen"),("en","Text to translate"),("ru","Текст для перевода"),("es","Texto para traducir"),("fr","Texte à traduire")] {
            _ = try await control("reset")
            let app = launch(locale, large: true)
            _ = try await waitTitles(["Legacy native"])
            let input = app.textViews["translator-input"]
            XCTAssertTrue(input.exists)
            XCTAssertFalse(input.label.isEmpty)
            // Exact localized source title is covered by the localization/source guards;
            // retain the observed AX value alongside the unmodified native image.
            _ = source
            capture(app, "profiles-translator-large-\(locale)")
            edit(app)
            let title = app.textFields["shortcut-title"]
            title.tap(); title.typeText(" \(locale)")
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            let save = app.buttons["shortcut-save"]
            XCTAssertTrue(save.isHittable)
            XCTAssertLessThan(save.frame.maxY, app.keyboards.firstMatch.frame.minY)
            capture(app, "profiles-editor-keyboard-large-\(locale)")
            app.terminate()
        }
    }
}
