import XCTest
@testable import KeineMagieCore

final class PodcastEpisodeStateTests: XCTestCase {
    func testLegacySourceAndIdentityAssociation() throws {
        let episode = try JSONDecoder().decode(PodcastEpisode.self, from: Data(#"{"id":"ep","title":"Real title","url":"https://audio.example/a.mp3"}"#.utf8))
        let job = try JSONDecoder().decode(PodcastJob.self, from: Data(#"{"id":"job","url":"https://cdn.example/resolved.mp3","source_url":"https://audio.example/a.mp3","source_language":"de","target_language":"ru","state":"transcribing","progress":100,"segments":[]}"#.utf8))
        XCTAssertTrue(job.belongs(to: episode, feedID: "feed"))
        XCTAssertNil(job.displayProgress)
    }
    func testLinkedImportCarriesActualIdentity() throws {
        let api = PodcastAPI(endpoint: try ServerEndpoint("https://example.com"), token: "synthetic")
        let request = try api.importRequest(url: "https://audio.example/a.mp3", source: "de", feedID: "feed-real", episodeID: "episode-real")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body["feed_id"], "feed-real")
        XCTAssertEqual(body["episode_id"], "episode-real")
    }
}
