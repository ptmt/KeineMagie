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
    func testStatusesDoNotConfuseAttemptWithIncorrectOrWaiting() throws {
        XCTAssertEqual(try turn().presentationStatus, "awaiting")
        for outcome in ["correct", "wrong", "ambiguous"] { XCTAssertEqual(try turn(attempt: ["outcome":outcome]).presentationStatus, "completed") }
        XCTAssertEqual(try turn(attempt: ["assessment_state":"pending"]).presentationStatus, "working")
        XCTAssertEqual(try turn(attempt: ["outcome":"skipped"]).presentationStatus, "unanswered")
    }
}
