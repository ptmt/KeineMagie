import XCTest
@testable import KeineMagieCore

final class CoachTests: XCTestCase {
    func testServerActionsAndLegacyFallback() throws {
        let empty = try JSONDecoder().decode(CoachSnapshot.self, from: Data(#"{"turns":[],"observations":[],"model":"gpt-6.1-terra"}"#.utf8))
        XCTAssertEqual(empty.quickActions.map(\.action), ["practice"])
        let raw = #"{"actions":[{"action":"progress","turn_id":""}],"turns":[],"observations":[],"model":"gpt-6.1-terra"}"#
        let current = try JSONDecoder().decode(CoachSnapshot.self, from: Data(raw.utf8))
        XCTAssertEqual(current.quickActions.map(\.action), ["progress"])
        XCTAssertEqual(try JSONDecoder().decode(CoachSnapshot.self, from: JSONEncoder().encode(current)).quickActions.map(\.action), ["progress"])
    }
    func testChatReceiptContract() throws {
        let raw = #"{"id":"one","text":"","state":"completed","at":"now","assisted":false,"language":"","kind":"nudge","message_version":"one:completed","seen_version":"","source_reveals":0,"answer_reveals":1}"#
        let turn = try JSONDecoder().decode(CoachTurn.self, from: Data(raw.utf8))
        XCTAssertTrue(turn.isUnread)
        XCTAssertEqual(turn.answerReveals, 1)
        XCTAssertFalse(turn.masksAnswer(latestID: "two"))
    }
    func testAssessmentPreservesVerbatimAndLegacyCompatibility() throws {
        let legacy = #"{"id":"old","answer":"  beim  ","outcome":"ambiguous","original_outcome":"ambiguous","assisted":false,"at":"now","excluded":false}"#
        let old = try JSONDecoder().decode(CoachAttempt.self, from: Data(legacy.utf8))
        XCTAssertNil(old.assessment)
        XCTAssertNil(old.assessmentState)
        let raw = legacy.dropLast() + #", "assessment_state":"completed", "assessment":{"verdict":"incorrect","corrected_answer":"bei","explanation":"Beim = bei dem; diesem is already present.","uncertainty_reason":""}}"#
        let assessed = try JSONDecoder().decode(CoachAttempt.self, from: Data(raw.utf8))
        XCTAssertEqual(assessed.answer, "  beim  ")
        XCTAssertEqual(assessed.assessment?.verdict, "incorrect")
        XCTAssertEqual(assessed.assessment?.correctedAnswer, "bei")
        XCTAssertEqual(assessed.assessmentState, "completed")
        let data = Data(#"{"turns":[{"id":"one","text":"Practice","state":"completed","at":"now","assisted":true,"language":"de"}],"observations":[],"model":"gpt-6.1-terra"}"#.utf8)
        let snapshot = try JSONDecoder().decode(CoachSnapshot.self, from: data)
        let pending = snapshot.pendingAssessment(CoachAction(requestID: "check", action: "answer", text: "  beim  ", turnID: "one", locale: "en"))
        XCTAssertEqual(pending.turns[0].attempt?.answer, "  beim  ")
        XCTAssertEqual(pending.turns[0].attempt?.assessmentState, "pending")
        XCTAssertEqual(pending.turns[0].attempt?.assisted, true)
        XCTAssertTrue(pending.observations.isEmpty)
    }
    func testCompactInstructionRetainsUsefulContext() throws {
        func turn(_ message: String, kind: String = "cloze") throws -> CoachTurn {
            let data = try JSONSerialization.data(withJSONObject: ["id":"one", "text":"Practice", "state":"completed", "at":"now", "assisted":false, "language":"de", "message":message, "kind":kind, "prompt":"Ich war einmal ___ diesem Kurs dabei."])
            return try JSONDecoder().decode(CoachTurn.self, from: data)
        }
        for message in ["Fill in the missing preposition.", "Ergänze die fehlende Präposition.", "Вставьте пропущенный предлог.", "Completa la preposición que falta.", "Complète la préposition manquante."] {
            XCTAssertFalse(try turn(message).showsInstruction)
        }
        XCTAssertTrue(try turn("Use the formal register.").showsInstruction)
        var completed = try turn("Fill this gap.")
        completed.attempt = try JSONDecoder().decode(CoachAttempt.self, from: Data(#"{"id":"a","answer":"bei","outcome":"wrong","original_outcome":"wrong","assisted":false,"at":"now","excluded":false}"#.utf8))
        XCTAssertTrue(completed.showsInstruction, "The original exercise instruction remains immutable after submission")
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

extension CoachTests {
    private func recoverySnapshot(attemptID: String? = nil, state: String = "failed", reset: Bool = false) throws -> CoachSnapshot {
        var turn: [String: Any] = ["id": "one", "text": "Practice", "state": "completed", "at": "now", "assisted": false, "language": "de"]
        if let attemptID {
            turn["attempt"] = ["id": attemptID, "answer": "  beim  ", "outcome": "ambiguous", "original_outcome": "ambiguous", "assisted": true, "at": "then", "excluded": true, "assessment_state": state]
        }
        let object: [String: Any] = ["turns": reset ? [] : [turn], "observations": [], "model": "gpt-6.1-terra", "reset_at": reset ? "later" : ""]
        return try JSONDecoder().decode(CoachSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testRecoveryPreservesPriorRecheckIdentityThroughCodingAndReads() throws {
        let prior = try recoverySnapshot(attemptID: "old")
        let request = CoachAction(requestID: "new", action: "recheck", turnID: "one", locale: "de", ownerID: "owner")
        let pending = prior.pendingAssessment(request)
        let saved = try JSONDecoder().decode(CoachSnapshot.self, from: JSONEncoder().encode(pending))
        let merged = prior.preservingUnacknowledged(from: saved)
        XCTAssertEqual(merged.turns.count, 1)
        XCTAssertEqual(merged.turns[0].attempt?.id, "new")
        XCTAssertEqual(merged.turns[0].attempt?.answer, "  beim  ")
        XCTAssertEqual(merged.turns[0].attempt?.localPriorAttemptID, "old")
        XCTAssertEqual(merged.turns[0].attempt?.localRequest?.action, "recheck")
        XCTAssertEqual(merged.turns[0].attempt?.localRequest?.ownerID, "owner")
        XCTAssertTrue(merged.turns[0].attempt?.canRecheck == true)
        XCTAssertEqual(merged.turns[0].attempt?.localRetryAllowed, true)
        XCTAssertTrue(merged.observations.isEmpty)
    }

    func testMatchingServerAcknowledgementAlwaysWins() throws {
        let pending = try recoverySnapshot().pendingAssessment(CoachAction(requestID: "new", action: "answer", text: "  beim  ", turnID: "one", locale: "en"))
        for state in ["pending", "completed", "failed", "canceled"] {
            let remote = try recoverySnapshot(attemptID: "new", state: state)
            let merged = remote.preservingUnacknowledged(from: pending)
            XCTAssertEqual(merged.turns.count, 1)
            XCTAssertEqual(merged.turns[0].attempt?.assessmentState, state)
            XCTAssertEqual(merged.turns[0].attempt?.excluded, true)
            XCTAssertNil(merged.turns[0].attempt?.localRequest)
        }
    }

    func testDifferentAuthoritativeAttemptAndMissingTurnDoNotEraseLiteral() throws {
        let pending = try recoverySnapshot().pendingAssessment(CoachAction(requestID: "local", action: "answer", text: "literal", turnID: "one", locale: "en"))
        let remote = try recoverySnapshot(attemptID: "other", state: "completed")
        let merged = remote.preservingUnacknowledged(from: pending)
        XCTAssertEqual(merged.turns.count, 2)
        XCTAssertEqual(merged.turns[0].attempt?.id, "other")
        XCTAssertEqual(merged.turns[0].attempt?.assessmentState, "completed")
        XCTAssertEqual(merged.turns[1].attempt?.answer, "literal")
        XCTAssertEqual(merged.turns[1].attempt?.localRetryAllowed, false)
        XCTAssertEqual(remote.preservingUnacknowledged(from: merged).turns.count, 2)
        let reset = try recoverySnapshot(reset: true)
        let retained = reset.preservingUnacknowledged(from: merged)
        XCTAssertEqual(retained.turns.count, 1)
        XCTAssertEqual(retained.turns[0].attempt?.answer, "literal")
        XCTAssertTrue(retained.turns[0].attempt?.canRecheck == true)
        XCTAssertTrue(reset.preservingUnacknowledged(from: retained, removing: "local").turns.isEmpty)
    }

    func testLegacyPendingCacheSurvivesMissingReceipt() throws {
        let legacy = try recoverySnapshot(attemptID: "local", state: "pending")
        let remote = try recoverySnapshot()
        let merged = remote.preservingUnacknowledged(from: legacy)
        XCTAssertEqual(merged.turns[0].attempt?.answer, "  beim  ")
        XCTAssertEqual(merged.turns[0].attempt?.localRequest?.requestID, "local")
        XCTAssertTrue(merged.turns[0].attempt?.canRecheck == true)
    }
}
