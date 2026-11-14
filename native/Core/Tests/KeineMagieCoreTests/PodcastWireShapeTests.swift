import XCTest
@testable import KeineMagieCore

final class PodcastWireShapeTests: XCTestCase {
    // Structural contract from Go podcastStore.subscriptions: summary jobs deliberately
    // drop segments. All values are synthetic; no production content/identifiers.
    private let job = #"{"id":"synthetic-job-000000001","url":"https://audio.example/raw.mp3","feed_id":"synthetic-feed-00000001","episode_id":"synthetic-episode","title":"Saved episode title","source_language":"de","target_language":"ru","state":"completed","progress":100,"created_at":"2026-11-14T00:00:00Z","updated_at":"2026-11-14T00:00:00Z","attempts":1,"segments":null}"#
    func testProductionSummaryNullSegmentsAndServerTitleDecode() throws {
        let body = #"{"items":[{"id":"synthetic-feed-00000001","url":"https://audio.example/feed.xml","title":"Saved feed","episodes":[{"id":"synthetic-episode","title":"Saved episode title","url":"https://audio.example/raw.mp3","preparation":JOB}],"refreshed_at":"2026-11-14T00:00:00Z"}]}"#.replacingOccurrences(of: "JOB", with: job)
        let feeds = try JSONDecoder().decode(PodcastSubscriptions.self, from: Data(body.utf8))
        let preparation = try XCTUnwrap(feeds.items.first?.episodes.first?.preparation)
        XCTAssertEqual(preparation.episodeTitle, "Saved episode title")
        XCTAssertEqual(preparation.segments.count, 0)
        XCTAssertTrue(preparation.belongs(to: feeds.items[0].episodes[0], feedID: feeds.items[0].id))
    }
    func testMissingSegmentsAndOldCachedTitleRemainCompatible() throws {
        let old = job.replacingOccurrences(of: ",\"segments\":null", with: "").replacingOccurrences(of: "\"title\":", with: "\"episode_title\":")
        let decoded = try JSONDecoder().decode(PodcastJob.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.episodeTitle, "Saved episode title")
        XCTAssertTrue(decoded.segments.isEmpty)
    }
    func testActualGoSerializedWire() throws {
        guard let directory = ProcessInfo.processInfo.environment["KM_PODCAST_WIRE_DIR"] else {
            throw XCTSkip("Executed by native/ci/verify_podcast_wire.py with actual Go output")
        }
        let root = URL(fileURLWithPath: directory)
        let feeds = try JSONDecoder().decode(PodcastSubscriptions.self, from: Data(contentsOf: root.appendingPathComponent("subscriptions.json")))
        let library = try JSONDecoder().decode(PodcastLibrary.self, from: Data(contentsOf: root.appendingPathComponent("library.json")))
        let preparation = try XCTUnwrap(feeds.items.first?.episodes.first?.preparation)
        XCTAssertTrue(preparation.segments.isEmpty)
        XCTAssertEqual(preparation.episodeTitle, "Saved episode title")
        XCTAssertEqual(library.items.first?.segments.count, 2113)
        XCTAssertEqual(library.items.first?.episodeTitle, preparation.episodeTitle)
        XCTAssertFalse(library.workerAvailable)
        let empty = try JSONDecoder().decode(PodcastSubscription.self, from: Data(contentsOf: root.appendingPathComponent("empty-subscription.json")))
        XCTAssertTrue(empty.episodes.isEmpty)
    }
    func testSubscriptionNullMissingCollectionsAndWrongTypes() throws {
        let base = #"{"id":"feed","url":"https://audio.example/feed.xml","title":"Feed"}"#
        for suffix in ["", ",\"episodes\":null", ",\"episodes\":[]"] {
            let body = String(base.dropLast()) + suffix + "}"
            XCTAssertTrue(try JSONDecoder().decode(PodcastSubscription.self, from: Data(body.utf8)).episodes.isEmpty)
        }
        for value in ["{}", "false", "42", "\"invalid\"", "[null]"] {
            let body = String(base.dropLast()) + ",\"episodes\":" + value + "}"
            XCTAssertThrowsError(try JSONDecoder().decode(PodcastSubscription.self, from: Data(body.utf8)))
        }
    }
    func testOptionalFieldsAndWrongTypesStayStrict() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(job.utf8)) as? [String: Any])
        for key in ["title", "error", "source_url", "feed_id", "episode_id"] {
            var null = object; null[key] = NSNull()
            XCTAssertNoThrow(try JSONDecoder().decode(PodcastJob.self, from: JSONSerialization.data(withJSONObject: null)))
            var missing = object; missing.removeValue(forKey: key)
            XCTAssertNoThrow(try JSONDecoder().decode(PodcastJob.self, from: JSONSerialization.data(withJSONObject: missing)))
            for invalid: Any in [42, true, ["injected": "value"], ["value"]] {
                var bad = object; bad[key] = invalid
                XCTAssertThrowsError(try JSONDecoder().decode(PodcastJob.self, from: JSONSerialization.data(withJSONObject: bad)), key)
            }
        }
        object["episode_title"] = "Legacy title"
        let current = try JSONDecoder().decode(PodcastJob.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(current.episodeTitle, "Saved episode title")
        let encoded = try JSONEncoder().encode(current)
        XCTAssertEqual(try JSONDecoder().decode(PodcastJob.self, from: encoded).episodeTitle, current.episodeTitle)
        for body in ["{}", "{\"items\":null}", "{\"items\":{}}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(PodcastSubscriptions.self, from: Data(body.utf8)))
        }
        for segments in ["{}", "false", "\"invalid\"", "[null]", "[{\"start\":0,\"end\":1,\"text\":42}]"] {
            let bad = job.replacingOccurrences(of: "\"segments\":null", with: "\"segments\":" + segments)
            XCTAssertThrowsError(try JSONDecoder().decode(PodcastJob.self, from: Data(bad.utf8)))
        }
    }
    func testMalformedRequiredDataStillFailsRatherThanPretendingEmpty() throws {
        for bad in [job.replacingOccurrences(of: "\"segments\":null", with: "\"segments\":{}"), job.replacingOccurrences(of: "\"progress\":100", with: "\"progress\":\"100\"")] {
            XCTAssertThrowsError(try JSONDecoder().decode(PodcastJob.self, from: Data(bad.utf8)))
        }
    }
}
