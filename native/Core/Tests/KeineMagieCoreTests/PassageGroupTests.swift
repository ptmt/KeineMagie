import XCTest
@testable import KeineMagieCore

final class PassageGroupTests: XCTestCase {
    func testActualGoStudyReceipt() throws {
        guard let path = ProcessInfo.processInfo.environment["PODCAST_STUDY_WIRE_PATH"] else { throw XCTSkip("Explicit Go handler receipt required") }
        let value = try JSONDecoder().decode(PassageGroups.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertNotNil(value.studiedAt)
        XCTAssertEqual(value.favoriteSegmentIDs, [0])
        XCTAssertEqual(value.groups.count, 1)
    }
    func testStudyDateSurvivesOwnerCacheRoundTrip() throws {
        let wire = #"{"version":1,"revision":9,"job_id":"job","favorite_segment_ids":[],"groups":[],"studied_at":"2026-11-22T12:00:00Z"}"#
        let value = try JSONDecoder().decode(PassageGroups.self, from: Data(wire.utf8))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        XCTAssertEqual(saved["studied_at"] as? String, "2026-11-22T12:00:00Z")
    }
    func testExplicitStudyRequestIsOwnerScoped() throws {
        let api = PodcastAPI(endpoint: try ServerEndpoint("https://example.com"), token: "synthetic")
        let job = String(repeating: "a", count: 24)
        let request = try api.studyRequest(id: job, owner: "owner-A")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/v1/learning/episodes/\(job)/studied")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Passage-Owner"), "owner-A")
        XCTAssertEqual(request.httpBody, Data("{}".utf8))
        XCTAssertThrowsError(try api.studyRequest(id: "../foreign", owner: "owner-A"))
    }
    func testPassageProtocolAndLegacyCache() throws {
        let api = PodcastAPI(endpoint: try ServerEndpoint("https://example.com"), token: "synthetic")
        let job = String(repeating: "a", count: 24)
        let request = try api.passageRequest(id: job, segment: 2112, favorite: true, owner: "owner-A")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/v1/learning/episodes/\(job)/passages/2112")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Passage-Owner"), "owner-A")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String:Bool], ["favorite":true])
        XCTAssertThrowsError(try api.passageRequest(id: "../foreign", segment: 0, favorite: true, owner: "A"))
        XCTAssertThrowsError(try api.passageRequest(id: job, segment: -1, favorite: true, owner: "A"))
        let old = try JSONDecoder().decode(EpisodeLearning.self, from: Data("{}".utf8))
        XCTAssertNil(old.passageGroups)
    }
    func testGroupsRoundTripRetainsOriginalIndicesAndRevision() throws {
        let wire = #"{"version":1,"revision":8,"job_id":"job","favorite_segment_ids":[0,2,3],"groups":[{"id":"g0","job_id":"job","segment_ids":[0],"start":2,"end":9},{"id":"g2","job_id":"job","segment_ids":[2,3],"start":1,"end":4}]}"#
        let groups = try JSONDecoder().decode(PassageGroups.self, from: Data(wire.utf8))
        XCTAssertEqual(groups.starredIDs, Set([0,2,3]))
        XCTAssertEqual(groups.groups.map(\.segmentIDs), [[0],[2,3]])
        let newer = try JSONDecoder().decode(PodcastCoverage.self, from: Data(#"{"favorite_passages":4,"passage_revision":9}"#.utf8))
        let older = try JSONDecoder().decode(PodcastCoverage.self, from: Data(#"{"favorite_passages":1,"passage_revision":7}"#.utf8))
        XCTAssertEqual(newer.favoritePassageCount(groups: groups), 4)
        XCTAssertEqual(older.favoritePassageCount(groups: groups), 3)
        XCTAssertEqual(try JSONDecoder().decode(PassageGroups.self, from: JSONEncoder().encode(groups)).revision, 8)
    }
    func testCoachGroupLinkKeepsOriginalAnchor() {
        let hash = "pg_" + String(repeating: "a", count: 64)
        XCTAssertEqual(CoachSourceTarget("passage-group:job_A:12:\(hash)"), .passage("job_A",12))
        XCTAssertNil(CoachSourceTarget("passage-group:job_A:012:\(hash)"))
        XCTAssertNil(CoachSourceTarget("passage-group:job_A:12:bad"))
    }
}
