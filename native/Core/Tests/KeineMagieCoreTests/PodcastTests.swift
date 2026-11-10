import XCTest
@testable import KeineMagieCore

final class PodcastTests: XCTestCase {
    func testShareAcceptsOnlySinglePublicWebURL() throws {
        XCTAssertEqual(try PodcastShareURL("https://example.com/episode.mp3").url.host, "example.com")
        for value in ["file:///etc/passwd", "https://user:pass@example.com/a.mp3", "https://example.com/a.mp3#secret", "https://example.com/a.mp3?token=secret", "https://example.com/a.mp3\nhttps://other.example/a.mp3"] {
            XCTAssertThrowsError(try PodcastShareURL(value), value)
        }
    }
    func testFeedRequestsAreAuthenticatedAndDiscoveryDoesNotEnqueue() throws {
        let api = PodcastAPI(endpoint: try ServerEndpoint("https://example.com"), token: "synthetic")
        let request = try api.subscriptionRequest(url: "https://audio.example/show")
        XCTAssertEqual(request.url?.path, "/v1/podcasts/subscriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String:String]
        XCTAssertEqual(body, ["url": "https://audio.example/show"])
        XCTAssertThrowsError(try api.subscriptionActionRequest(id: "../owner", action: "refresh"))
    }
    func testPodcastRequestUsesExplicitSessionAndSource() throws {
        let api = PodcastAPI(endpoint: try ServerEndpoint("https://example.com"), token: "synthetic")
        let request = try api.importRequest(url: "https://audio.example/a.mp3", source: "de")
        XCTAssertEqual(request.url?.path, "/v1/podcasts")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String:String]
        XCTAssertEqual(body?["source_language"], "de")
        XCTAssertEqual(body?["url"], "https://audio.example/a.mp3")
        XCTAssertThrowsError(try api.importRequest(url: "https://audio.example/a.mp3", source: "en"))
    }
}
