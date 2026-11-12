import Testing
import Foundation
@testable import KeineMagieCore

@Suite struct EpisodeNavigationTests {
    @Test func learningRequestsAreReadOnlyExceptExplicitAssessment() throws {
        let api = PodcastAPI(endpoint: try ServerEndpoint("https://example.com"), token: "synthetic")
        let read = try api.learningRequest(resource: .analysis("synthetic-job-000000001"))
        #expect(read.url?.path == "/v1/learning/episodes/synthetic-job-000000001/analysis")
        #expect(read.httpMethod == "GET")
        #expect(read.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(read.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
        let vocabulary = try api.learningRequest(resource: .vocabulary("synthetic-job-000000001", "de"))
        #expect(URLComponents(url: vocabulary.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "job_id" })?.value == "synthetic-job-000000001")
        let update = try api.learningRequest(resource: .profile("ru"), assessment: "B2")
        #expect(update.httpMethod == "PUT")
        #expect(try JSONSerialization.jsonObject(with: update.httpBody!) as? [String: String] == ["cefr": "B2"])
        #expect(throws: APIError.self) { try api.learningRequest(resource: .analysis("../foreign")) }
        #expect(throws: APIError.self) { try api.learningRequest(resource: .profile("en")) }
        #expect(throws: APIError.self) { try api.learningRequest(resource: .profile("de"), assessment: "D1") }
        #expect(throws: APIError.self) { try api.learningRequest(resource: .analysis("synthetic-job-000000001"), assessment: "B1") }
    }
    @Test func citationsRejectNegativeOutOfBoundsAndFabricatedQuotes() throws {
        let segments = try JSONDecoder().decode([PodcastSegment].self, from: Data(#"[{"start":0,"end":2,"text":"Hallo Welt","translation":"Привет"}]"#.utf8))
        #expect(LearningCitation(segmentID: 0, quote: "Hallo").valid(in: segments))
        for citation in [LearningCitation(segmentID: -1, quote: "Hallo"), LearningCitation(segmentID: 1, quote: "Hallo"), LearningCitation(segmentID: 0, quote: ""), LearningCitation(segmentID: 0, quote: "Привет"), LearningCitation(segmentID: 0, quote: "hallo")] {
            #expect(!citation.valid(in: segments))
        }
    }
    @Test func searchMatchesSourceAndTranslationWithoutDuplicatingSegment() throws {
        let segments = try JSONDecoder().decode([PodcastSegment].self, from: Data(#"[{"start":0,"end":2,"text":"Alltag Alltag","translation":"ALLTAG"},{"start":2,"end":4,"text":"Hallo","translation":"Привет"}]"#.utf8))
        #expect(EpisodeNavigation.matches("alltag", segments: segments) == [0])
        #expect(EpisodeNavigation.matches("ПРИВЕТ", segments: segments) == [1])
        #expect(EpisodeNavigation.matches(" ", segments: segments).isEmpty)
        #expect(EpisodeNavigation.timestamp(20129) == "335:29")
    }
    @Test func timestampJumpUsesStoredIndexIncludingLongTranscriptsAndGaps() throws {
        let segments = try JSONDecoder().decode([PodcastSegment].self, from: Data(("[" + (0..<2113).map { "{\"start\":\($0 * 10),\"end\":\($0 * 10 + 8),\"text\":\"Segment \($0)\",\"translation\":\"Перевод \($0)\"}" }.joined(separator: ",") + "]").utf8))
        #expect(EpisodeNavigation.index(at: "335:29", segments: segments) == 2012)
        #expect(EpisodeNavigation.index(at: "00:09", segments: segments) == 0)
        #expect(EpisodeNavigation.index(at: "999:00", segments: segments) == 2112)
        for invalid in ["-1:00", "1:60", "NaN", "1:2", "1:00:00", ""] {
            #expect(EpisodeNavigation.index(at: invalid, segments: segments) == nil)
        }
        #expect(EpisodeNavigation.index(at: "0:00", segments: []) == nil)
    }
}
