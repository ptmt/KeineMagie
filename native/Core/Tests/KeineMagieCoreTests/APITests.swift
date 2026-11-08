import Foundation
import Testing
@testable import KeineMagieCore

@Test func buildsAuthenticatedRequestsAndExactTTSPayload() throws {
    let api = APIClient(endpoint: try ServerEndpoint("https://example.com/app"), token: "secret")
    let translation = try api.translationRequest(text: "Hallo", source: .german)
    #expect(translation.url?.path == "/app/v1/translations")
    #expect(translation.httpMethod == "POST")
    #expect(translation.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    #expect(translation.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let history = try api.historyRequest()
    #expect(history.httpMethod == "GET")
    let tts = try api.ttsRequest(text: "Hallo")
    let data = try #require(tts.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(body["text"] as? String == "Hallo")
    #expect(body["language"] as? String == "de-DE")
    #expect(body["voice"] as? String == "alloy")
    #expect(body["model"] as? String == "gpt-4o-mini-tts")
    #expect(body["format"] as? String == "mp3")
    #expect(body["speed"] as? Double == 1)
    #expect(throws: (any Error).self) { try APIClient(endpoint: ServerEndpoint("https://example.com"), token: "").historyRequest() }
    #expect(throws: (any Error).self) { try api.translationRequest(text: "  ", source: .russian) }
    #expect(throws: (any Error).self) { try APIClient(endpoint: ServerEndpoint("https://example.com"), token: "bad\nheader").historyRequest() }
}
