import XCTest
@testable import KeineMagieCore

final class CoachTests: XCTestCase {
    func testSourceTargetsRejectMalformedIDs() {
        XCTAssertEqual(CoachSourceTarget("translation:original"), .translation("original"))
        XCTAssertEqual(CoachSourceTarget("passage:job_A:12"), .passage("job_A", 12))
        for id in ["translation:../foreign", "passage:job:01", "passage:job:-1", "https://foreign", "translation:"] { XCTAssertNil(CoachSourceTarget(id)) }
    }
    func testReadDoesNotPostAndDecodesEvidence() async throws {
        let client = PodcastAPI(endpoint: try ServerEndpoint("https://example.com"), token: "synthetic", transport: { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/learning/coach")
            return AuthResponse(data: Data(#"{"turns":[{"id":"one","text":"Practice","state":"completed","message":"Try this","kind":"cloze","prompt":"Ich warte ___ den Bus.","target":"verb_government","source_id":"translation:one","at":"2026-11-13T00:00:00Z","assisted":false,"language":"de"}],"observations":[],"model":"gpt-6.1-terra"}"#.utf8), status: 200)
        })
        let value = try await client.coach()
        XCTAssertEqual(value.turns.count, 1)
        XCTAssertNil(value.turns[0].quote)
        XCTAssertEqual(value.turns[0].kind, "cloze")
    }
    func testErrorsAreTypedAndDoNotExposeUpstreamText() async throws {
        let client = PodcastAPI(endpoint: try ServerEndpoint("https://example.com"), token: "synthetic", transport: { _ in
            AuthResponse(data: Data(#"{"error":"private upstream detail","code":"coach_model_unavailable"}"#.utf8), status: 503)
        })
        do { _ = try await client.coach(); XCTFail("expected failure") }
        catch let error as CoachServiceError { XCTAssertEqual(error.message, "coach.error.model_unavailable") }
    }
    func testExplicitActionPreservesID() async throws {
        let client = PodcastAPI(endpoint: try ServerEndpoint("https://example.com"), token: "synthetic", transport: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            XCTAssertEqual(body["request_id"], "stable-id")
            XCTAssertEqual(body["action"], "answer")
            return AuthResponse(data: Data(#"{"turns":[],"observations":[],"model":"gpt-6.1-terra"}"#.utf8), status: 200)
        })
        _ = try await client.coach(action: CoachAction(requestID: "stable-id", action: "answer", text: "auf", turnID: "one", locale: "de"))
    }
}
