import XCTest
@testable import KeineMagieCore

final class PodcastOverviewTests: XCTestCase {
    private func feed(_ episodes: String) throws -> PodcastSubscription {
        try JSONDecoder().decode(PodcastSubscription.self, from: Data("{\"id\":\"feed\",\"url\":\"https://example.com/feed\",\"title\":\"Feed\",\"author\":\"Source author\",\"episodes\":\(episodes)}".utf8))
    }
    func testCoverageIsServerMetadataAndZeroUnknownDenominatorIsOmitted() throws {
        let base = #"{"id":"job","url":"https://example.com/a","feed_id":"feed","episode_id":"same","source_language":"de","target_language":"ru","state":"completed","progress":100,"segments":[],"coverage":{"recognized_segments":3,"translated_segments":0,"favorite_passages":2}}"#
        let job = try JSONDecoder().decode(PodcastJob.self, from: Data(base.utf8))
        XCTAssertEqual(job.coverage?.recognizedSegments, 3)
        XCTAssertEqual(job.coverage?.translatedSegments, 0)
        XCTAssertEqual(job.coverage?.favoritePassages, 2)
        XCTAssertEqual(job.coverage?.knownTotal, 3)
        let zero = try JSONDecoder().decode(PodcastJob.self, from: Data(base.replacingOccurrences(of: "\"recognized_segments\":3", with: "\"recognized_segments\":0").utf8))
        XCTAssertNil(zero.coverage?.knownTotal)
        let missing = try JSONDecoder().decode(PodcastJob.self, from: Data(base.replacingOccurrences(of: ",\"recognized_segments\":3", with: "").replacingOccurrences(of: "\"recognized_segments\":3,", with: "").utf8))
        XCTAssertNil(missing.coverage?.knownTotal)
        let roundtrip = try JSONDecoder().decode(PodcastJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(roundtrip.coverage?.favoritePassages, 2)
        let ep = try feed(#"[{"id":"same","title":"Same ID","url":"https://example.com/a"}]"#).episodes[0]
        XCTAssertTrue(job.belongs(to: ep, feedID: "feed"))
        XCTAssertFalse(job.belongs(to: ep, feedID: "other"))
    }
    func testLatestThreeArePerFeedAndStableWithInvalidDates() throws {
        let episodes = #"[{"id":"undated","title":"Unknown","url":"https://example.com/0"},{"id":"old","title":"Old","url":"https://example.com/1","published":"2026-01-01"},{"id":"new","title":"New","url":"https://example.com/2","published":"2026-11-16T12:00:00Z"},{"id":"tie","title":"Tie","url":"https://example.com/3","published":"2026-11-16T12:00:00Z"},{"id":"invalid","title":"Invalid","url":"https://example.com/4","published":"not a date"}]"#
        let value = try feed(episodes)
        XCTAssertEqual(value.latestEpisodes.map(\.id), ["new", "tie", "old"])
        XCTAssertEqual(value.author, "Source author")
        for n in [0, 1, 3, 5] {
            let data = try JSONEncoder().encode(Array(value.episodes.prefix(n)))
            XCTAssertEqual(try feed(String(decoding: data, as: UTF8.self)).latestEpisodes.count, min(n, 3))
        }
        XCTAssertEqual(try feed(#"[{"id":"b","title":"B","url":"https://example.com/b"},{"id":"a","title":"A","url":"https://example.com/a","published":"bad"}]"#).latestEpisodes.map(\.id), ["b", "a"])
    }
}
