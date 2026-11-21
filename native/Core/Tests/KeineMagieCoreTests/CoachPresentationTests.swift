import XCTest
@testable import KeineMagieCore

final class CoachPresentationTests: XCTestCase {
    private func turn(_ at: String? = nil, attempt: [String: Any]? = nil, state: String = "completed") throws -> CoachTurn {
        var row: [String: Any] = ["id":"fixture", "text":"", "state":state, "assisted":false, "language":"de"]
        if let at { row["at"] = at }
        if let attempt { row["attempt"] = ["id":"a", "answer":"literal", "outcome":"wrong", "original_outcome":"wrong", "assisted":false, "at":"2026-10-25T11:00:00Z", "excluded":false].merging(attempt) { _, new in new } }
        return try JSONDecoder().decode(CoachTurn.self, from: JSONSerialization.data(withJSONObject: row))
    }
    func testRollingDayBoundaryDSTUnknownFutureAndRecentAttempt() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
        XCTAssertFalse(try turn("2026-10-24T11:59:59Z").isRecent(now: now))
        XCTAssertTrue(try turn("2026-10-24T14:00:00+02:00").isRecent(now: now))
        XCTAssertTrue(try turn("2026-10-20T00:00:00Z", attempt: [:]).isRecent(now: now))
        XCTAssertTrue(try turn().isRecent(now: now))
        XCTAssertTrue(try turn("now").isRecent(now: now))
        XCTAssertTrue(try turn("2027-01-01T00:00:00Z").isRecent(now: now))
        XCTAssertFalse(try turn("2026-10-20T00:00:00Z", state: "pending").isRecent(now: now))
    }
    func testPendingOldTurnStaysVisibleWithoutOpeningEarlier() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
        var archived = try turn("2020-01-01T00:00:00Z"); archived.id = "archived"
        let pending = try turn("2020-01-02T00:00:00Z", state: "pending")
        XCTAssertEqual(CoachTurn.historyWindow([archived, pending], now: now, earlierLimit: 0).map(\.id), ["fixture"])
    }
    func testExplicitPinnedTurnDoesNotExpandOldHistory() throws {
        let old = try turn("2020-01-01T00:00:00Z")
        var other = old; other.id = "other"
        XCTAssertEqual(CoachTurn.historyWindow([other, old], now: Date(), earlierLimit: 0, pinnedID: old.id).map(\.id), [old.id])
    }
    func testInstructionSurvivesAnswerSubmission() throws {
        let row = #"{"id":"exercise","text":"","state":"completed","assisted":false,"language":"de","kind":"short_rephrase","prompt":"Say it politely.","message":"Use a request."}"#
        var exercise = try JSONDecoder().decode(CoachTurn.self, from: Data(row.utf8))
        exercise.attempt = try turn(attempt: [:]).attempt
        XCTAssertTrue(exercise.showsInstruction)
    }
    func testContextTranslationTargetAndLanguageDecodeWithoutChangingLegacy() throws {
        let row = #"{"id":"word","text":"","state":"completed","assisted":false,"language":"de","kind":"context_translation","prompt":"Ich muss das Paket abholen.","target_text":"abholen","answer_language":"en"}"#
        let exercise = try JSONDecoder().decode(CoachTurn.self, from: Data(row.utf8))
        XCTAssertEqual(exercise.targetText, "abholen")
        XCTAssertEqual(exercise.answerLanguage, "en")
        XCTAssertNil(try turn().targetText)
        XCTAssertNil(try turn().answerLanguage)
    }
    func testEarlierBoundsRenderingWithoutDroppingSavedGroups() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
        let old = try turn("2020-01-01T00:00:00Z")
        let older = (0..<1000).map { index in var value = old; value.id = "old-\(index)"; return value }
        let turns = older + [try turn("2026-10-25T11:00:00Z")]
        XCTAssertEqual(CoachTurn.historyWindow(turns, now: now, earlierLimit: 0).count, 1)
        XCTAssertEqual(CoachTurn.historyWindow(turns, now: now, earlierLimit: 50).count, 51)
        XCTAssertEqual(CoachTurn.historyWindow(turns, now: now, earlierLimit: 100).count, 51)
        XCTAssertEqual(CoachTurn.historyWindow(turns, now: now, earlierLimit: 100).first?.id, "old-900")
        XCTAssertEqual(turns.count, 1001)
    }
    func testSyntheticHistoryPresentationBenchmark() throws {
        let now = Date()
        for count in [200, 1000] {
            let old = try turn("2020-01-01T00:00:00Z")
            let turns = (0..<count).map { index in var value = old; value.id = "bench-\(index)"; return value }
            let start = ContinuousClock.now
            for _ in 0..<3 { XCTAssertEqual(CoachTurn.historyWindow(turns, now: now, earlierLimit: 50).count, 50) }
            print("COACH_PRESENTATION_BENCH count=\(count) iterations=3 elapsed=\(start.duration(to: .now)) rendered=50")
        }
    }
    func testEntryTimeZoneIsOptionalAndLegacyCodingSurvives() throws {
        let entry = CoachAction(action: "entry", locale: "en", timeZone: "Europe/Berlin")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as! [String: Any]
        XCTAssertEqual(object["time_zone"] as? String, "Europe/Berlin")
        let legacy = CoachAction(action: "entry", locale: "en")
        let data = try JSONEncoder().encode(legacy)
        XCTAssertNil((try JSONSerialization.jsonObject(with: data) as! [String: Any])["time_zone"])
        XCTAssertNil(try JSONDecoder().decode(CoachAction.self, from: data).timeZone)
    }
    func testLegacyGreetingsAreFilteredWithoutMutatingHistory() throws {
        var offer = try turn(); offer.id = "offer"; offer.isOffer = true
        let nudge = try JSONDecoder().decode(CoachTurn.self, from: Data(#"{"id":"nudge","text":"","state":"completed","assisted":false,"language":"de","kind":"nudge"}"#.utf8))
        let turns = [offer, nudge, try turn()]
        XCTAssertEqual(CoachTurn.historyWindow(turns, now: Date(), earlierLimit: 50).map(\.id), ["fixture"])
        XCTAssertEqual(turns.count, 3)
    }
    func testFailedAssessmentIsNeutralEvenWithOldCorrectOutcome() throws {
        XCTAssertEqual(try turn(attempt: ["outcome":"correct", "assessment_state":"failed"]).presentationStatus, "completed")
    }
    func testStatusesDoNotConfuseAttemptWithIncorrectOrWaiting() throws {
        XCTAssertEqual(try turn().presentationStatus, "awaiting")
        for (outcome, status) in [("correct", "success"), ("wrong", "incorrect"), ("ambiguous", "completed")] { XCTAssertEqual(try turn(attempt: ["outcome":outcome]).presentationStatus, status) }
        XCTAssertEqual(try turn(attempt: ["assessment_state":"pending"]).presentationStatus, "working")
        XCTAssertEqual(try turn(attempt: ["outcome":"skipped"]).presentationStatus, "unanswered")
    }
}
