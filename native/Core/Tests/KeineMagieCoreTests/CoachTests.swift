import XCTest
@testable import KeineMagieCore

final class CoachTests: XCTestCase {
    func testCompactInstructionRetainsUsefulContext() throws {
        func turn(_ message: String, kind: String = "cloze") throws -> CoachTurn {
            let data = try JSONSerialization.data(withJSONObject: ["id":"one", "text":"Practice", "state":"completed", "at":"now", "assisted":false, "language":"de", "message":message, "kind":kind, "prompt":"Ich war einmal ___ diesem Kurs dabei."])
            return try JSONDecoder().decode(CoachTurn.self, from: data)
        }
        for message in ["Fill in the missing preposition.", "Ergänze die fehlende Präposition.", "Вставьте пропущенный предлог.", "Completa la preposición que falta.", "Complète la préposition manquante."] {
            XCTAssertFalse(try turn(message).showsInstruction)
        }
        XCTAssertTrue(try turn("Use the formal register.").showsInstruction)
        XCTAssertTrue(try turn("Fill in the missing preposition.", kind: "short_rephrase").showsInstruction)
    }
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
    func testCoachFailureStagesAreNotAllNetwork() async throws {
        for (status, body, expected) in [(502, "{}", "server"), (200, "not json", "response")] {
            let client = PodcastAPI(endpoint: try ServerEndpoint("https://example.com"), token: "synthetic", transport: { _ in AuthResponse(data: Data(body.utf8), status: status) })
            do { _ = try await client.coach(); XCTFail("expected failure") }
            catch let error as CoachServiceError { XCTAssertEqual(error.message, "coach.error." + expected) }
            catch { XCTFail("untyped decoding failure") }
        }
        for (code, expected) in [(URLError.Code.timedOut, "timeout"), (.notConnectedToInternet, "network"), (.cancelled, "canceled")] {
            let client = PodcastAPI(endpoint: try ServerEndpoint("https://example.com"), token: "synthetic", transport: { _ in throw URLError(code) })
            do { _ = try await client.coach(); XCTFail("expected failure") }
            catch let error as CoachServiceError { XCTAssertEqual(error.message, "coach.error." + expected) }
            catch { XCTFail("untyped transport failure") }
        }
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
