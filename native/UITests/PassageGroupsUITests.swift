import XCTest

final class PassageGroupsUITests: XCTestCase {
    @MainActor private func control(_ path: String) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18879/_fixture/" + path)!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }
    @MainActor private func launch(_ locale: String = "en", xxxl: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "passage-http"
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
        if xxxl { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] }
        app.launch()
        return app
    }
    @MainActor private func openEpisode(_ app: XCUIApplication, locale: String = "en") {
        let tab = app.tabBars.buttons[locale == "ru" ? "Подкасты" : "Podcasts"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
        let episode = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic passage acceptance")).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 10)); episode.tap()
        XCTAssertTrue(app.textFields["episode-time"].waitForExistence(timeout: 5))
    }
    @MainActor private func jump(_ app: XCUIApplication, _ index: Int) {
        let field = app.textFields["episode-time"]
        field.tap()
        if let value = field.value as? String, value != "00:00" { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        field.typeText("\(index * 10 / 60):\(String(format: "%02d", index * 10 % 60))")
        app.buttons["episode-jump"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Synthetic segment \(index)")).firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor private func star(_ app: XCUIApplication, _ index: Int, label: String) {
        jump(app, index)
        let row = app.cells.containing(.staticText, identifier: "Synthetic segment \(index)" + ([2012,2014].contains(index) ? " needle" : "")).firstMatch
        XCTAssertTrue(row.exists)
        row.swipeLeft()
        let button = app.buttons["episode-star-\(index)"]
        XCTAssertTrue(button.waitForExistence(timeout: 4)); XCTAssertEqual(button.label, label)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        capture(app, "passage-swipe-\(index)-\(label)")
        button.tap()
    }
    @MainActor private func assertGroups(_ expected: [[Int]], puts: Int) async throws {
        var state: [String: Any] = [:]
        for _ in 0..<40 {
            state = try await control("state")
            let groups = state["groups"] as! [String: Any]
            if (groups["groups"] as! [[String: Any]]).map({ $0["segment_ids"] as! [Int] }) == expected { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let snapshot = state["groups"] as! [String: Any]
        XCTAssertEqual((snapshot["groups"] as! [[String: Any]]).map { $0["segment_ids"] as! [Int] }, expected)
        XCTAssertEqual(snapshot["favorite_segment_ids"] as! [Int], expected.flatMap { $0 })
        let requests = state["requests"] as! [[String: Any]]
        let mutations = requests.filter { $0["method"] as? String == "PUT" }
        XCTAssertEqual(mutations.count, puts)
        let readOwner = requests.first { ($0["path"] as? String)?.hasSuffix("/passage-groups") == true }?["owner"] as? String
        XCTAssertFalse((readOwner ?? "").isEmpty)
        XCTAssertTrue(mutations.allSatisfy { $0["owner"] as? String == readOwner })
        XCTAssertEqual(state["segment_count"] as? Int, 2113)
        XCTAssertEqual(state["source_unchanged"] as? Bool, true)
        if let last = mutations.last, last["status"] as? Int == 200 {
            let response = try JSONSerialization.jsonObject(with: Data((last["response"] as! String).utf8)) as! [String: Any]
            XCTAssertEqual((response["passage_groups"] as! [String: Any])["favorite_segment_ids"] as! [Int], expected.flatMap { $0 })
        }
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        let a = XCTAttachment(data: data, uniformTypeIdentifier: "public.json"); a.name = "HTTP-groups-\(puts)"; a.lifetime = .keepAlways; add(a)
    }
    @MainActor func testBridgeSplitSearchRelaunchOwnerAndNavigation() async throws {
        _ = try await control("reset")
        let app = launch(); defer { app.terminate() }
        openEpisode(app)
        star(app, 2012, label: "Save"); try await assertGroups([[2012]], puts: 1)
        star(app, 2014, label: "Save"); try await assertGroups([[2012], [2014]], puts: 2)
        // Search visits visually adjacent matches, but original 2013 remains the gap.
        let search = app.textFields["episode-search"]
        search.tap(); search.typeText("needle"); app.buttons["episode-next-match"].tap()
        XCTAssertTrue(app.staticTexts["1 / 2"].exists)
        app.buttons["episode-next-match"].tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].exists)
        capture(app, "passage-nonadjacent-search")
        try await assertGroups([[2012], [2014]], puts: 2)
        search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        star(app, 2013, label: "Save"); try await assertGroups([[2012,2013,2014]], puts: 3)
        star(app, 2013, label: "Unsave"); try await assertGroups([[2012],[2014]], puts: 4)
        star(app, 2015, label: "Save"); try await assertGroups([[2012],[2014,2015]], puts: 5)
        star(app, 2015, label: "Unsave"); try await assertGroups([[2012],[2014]], puts: 6)
        star(app, 2112, label: "Save"); try await assertGroups([[2012],[2014],[2112]], puts: 7)
        capture(app, "passage-last-original-index")
        app.sliders["episode-timeline"].adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertFalse(app.staticTexts["Synthetic segment 2112"].isHittable)
        app.buttons["episode-section-summary"].tap()
        XCTAssertTrue(app.buttons["episode-citation-2012"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["episode-citation-2012"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Synthetic segment 2012 needle"].waitForExistence(timeout: 5))
        capture(app, "passage-original-citation")
        // Return control is at the beginning of the bounded window, not pinned.
        let list = app.collectionViews.firstMatch
        for _ in 0..<20 { if app.buttons["Back to source"].isHittable { break }; list.swipeDown() }
        XCTAssertTrue(app.buttons["Back to source"].isHittable); app.buttons["Back to source"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic saved summary"].exists)
        for _ in 0..<2 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let episode = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic passage acceptance")).firstMatch
            XCTAssertTrue(episode.waitForExistence(timeout: 5))
            XCTAssertTrue(episode.label.contains("Starred passages: 3"))
            XCTAssertTrue(episode.label.contains("Translated passages 2,113 / 2,113"))
            XCTAssertTrue(episode.label.contains("Ready"))
            capture(app, "passage-library-three-stars-not-groups")
            episode.tap()
            jump(app, 2012)
            XCTAssertTrue(app.images["Favorite"].firstMatch.exists)
        }
        app.terminate(); app.launch(); openEpisode(app); jump(app, 2012)
        XCTAssertTrue(app.images["Favorite"].firstMatch.exists)
        capture(app, "passage-cold-online")
        try await assertGroups([[2012],[2014],[2112]], puts: 7)
        app.terminate(); app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "cache-offline"
        app.launch(); openEpisode(app); jump(app, 2012)
        XCTAssertTrue(app.images["Favorite"].firstMatch.exists)
        let row = app.cells.containing(.staticText, identifier: "Synthetic segment 2012 needle").firstMatch
        row.swipeLeft()
        XCTAssertFalse(app.buttons["episode-star-2012"].exists)
        XCTAssertTrue(app.images["Favorite"].firstMatch.exists)
        capture(app, "passage-cold-offline-owner-cache")
        app.terminate(); _ = try await control("owner-b")
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "passage-http"; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Podcasts"].waitForExistence(timeout: 10)); app.tabBars.buttons["Podcasts"].tap()
        XCTAssertTrue(app.staticTexts["No podcasts yet"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Synthetic passage acceptance"].exists)
        capture(app, "passage-different-owner-empty")
        try await assertGroups([[2012],[2014],[2112]], puts: 7)
        let finalState = try await control("state")
        let reads = (finalState["requests"] as! [[String: Any]]).filter { ($0["path"] as? String)?.hasSuffix("/passage-groups") == true }
        XCTAssertEqual(reads.count, 4) // initial entry, two returns, online cold relaunch
        XCTAssertTrue(reads.allSatisfy { $0["status"] as? Int == 200 })
    }
    @MainActor func testFailedWriteRetainsStateAndRevocationPurges() async throws {
        _ = try await control("reset")
        let app = launch(); defer { app.terminate() }
        openEpisode(app)
        star(app, 2012, label: "Save"); try await assertGroups([[2012]], puts: 1)
        _ = try await control("fail-next")
        star(app, 2012, label: "Unsave")
        try await assertGroups([[2012]], puts: 2)
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 5))
        capture(app, "passage-failed-write-retains-star")
        app.buttons["Retry"].tap()
        try await assertGroups([[2012]], puts: 2)
        _ = try await control("revoke")
        star(app, 2012, label: "Unsave")
        try await assertGroups([[2012]], puts: 3)
        let denied = try await control("state")
        XCTAssertEqual((denied["requests"] as! [[String: Any]]).last?["status"] as? Int, 401)
        XCTAssertTrue(app.textViews["translator-input"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["episode-time"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic segment 2012 needle"].exists)
        capture(app, "passage-401-purged")
        app.terminate(); app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "cache-offline"; app.launch()
        XCTAssertTrue(app.textViews["translator-input"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["Podcasts"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic passage acceptance"].exists)
        capture(app, "passage-revoked-offline-no-private-data")
    }
    @MainActor func testFiveLocaleXXXLContextMenu() async throws {
        for (locale, save, unsave) in [("de","Speichern","Entfernen"),("en","Save","Unsave"),("ru","Сохранить","Убрать"),("es","Guardar","Quitar"),("fr","Enregistrer","Retirer")] {
            _ = try await control("reset")
            let app = launch(locale, xxxl: true)
            openEpisode(app, locale: locale)
            star(app, 2012, label: save); try await assertGroups([[2012]], puts: 1)
            let row = app.cells.containing(.staticText, identifier: "Synthetic segment 2012 needle").firstMatch
            row.press(forDuration: 1.1)
            let action = app.buttons["episode-star-2012"]
            XCTAssertTrue(action.waitForExistence(timeout: 5)); XCTAssertEqual(action.label, unsave)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            capture(app, "passage-context-XXXL-\(locale)")
            action.tap(); try await assertGroups([], puts: 2)
            capture(app, "passage-XXXL-\(locale)")
            app.terminate()
        }
    }
    @MainActor func testNativeSwipeUsesProductionHTTP() async throws {
        _ = try await control("reset")
        let app = launch(); defer { app.terminate() }
        openEpisode(app)
        star(app, 2012, label: "Save")
        let state = try await control("state")
        let puts = (state["requests"] as! [[String: Any]]).filter { $0["method"] as? String == "PUT" }
        XCTAssertEqual(puts.count, 1)
        XCTAssertEqual(puts.first?["body"] as? String, "{\"favorite\":true}")
        XCTAssertEqual((state["groups"] as? [String: Any])?["favorite_segment_ids"] as? [Int], [2012])
    }
}
