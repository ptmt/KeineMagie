import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@MainActor final class CoachGate {
    var hold = false
    var replies: [CheckedContinuation<Void, Never>] = []
    var calls: [String] = []
    var proof: SavedNativeIdentity?
    var offline = false
    var failPost = false
    var owner = "coach-fixture"
    var actions: [CoachAction] = []
    var status = 200
    var bodyOverride: String?
    let body = #"{"turns":[{"id":"saved","text":"Practice","state":"completed","at":"2026-11-13T00:00:00Z","assisted":false,"language":"de","message":"Saved coach turn","kind":"cloze","prompt":"Ich warte ___ den Bus."}],"observations":[],"model":"gpt-6.1-terra"}"#
    func send(_ r: URLRequest) async throws -> AuthResponse {
        if r.url!.path == "/v1/auth/session" {
            if offline { throw URLError(.notConnectedToInternet) }
            return AuthResponse(data: Data("{\"user\":{\"id\":\"\(owner)\"},\"expires_at\":\"2099-01-01T00:00:00Z\"}".utf8), status: 200)
        }
        calls.append(r.httpMethod!)
        if r.httpMethod == "POST" {
            actions.append(try JSONDecoder().decode(CoachAction.self, from: r.httpBody!))
            if failPost { throw URLError(.timedOut) }
        }
        let capturedBody = bodyOverride ?? body, capturedStatus = status
        if hold { await withCheckedContinuation { replies.append($0) } }
        return AuthResponse(data: Data(capturedBody.utf8), status: capturedStatus)
    }
    func model(_ root: URL) async throws -> AppModel {
        let transport: AuthClient.Transport = { try await self.send($0) }
        let session = SessionController(serverURL: "https://coach.invalid", readToken: { "synthetic" }, saveToken: { _ in }, readIdentity: { self.proof }, saveIdentity: { self.proof = $0 }, transport: transport)
        await session.restore()
        let endpoint = try ServerEndpoint("https://coach.invalid")
        return AppModel(session: session, client: APIClient(endpoint: endpoint, token: "synthetic", transport: transport), podcastClient: PodcastAPI(endpoint: endpoint, token: "synthetic", transport: transport), cache: ContentCache(root: root))
    }
}
@Test @MainActor func coachWriteDominatesStaleReadAndCancellation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    gate.hold = true
    let read = Task { await model.loadCoach() }
    while gate.replies.isEmpty { await Task.yield() }
    gate.hold = false; gate.bodyOverride = gate.body.replacingOccurrences(of: "Saved coach turn", with: "New saved turn")
    model.sendCoach("message", text: "Practice")
    while model.coachBusy { await Task.yield() }
    gate.replies.removeFirst().resume(); await read.value
    #expect(model.coach?.turns.first?.message == "New saved turn")
    gate.hold = true
    model.sendCoach("message", text: "Slow")
    while gate.replies.isEmpty { await Task.yield() }
    gate.hold = false; gate.bodyOverride = #"{"turns":[],"observations":[],"model":"gpt-6.1-terra"}"#
    model.sendCoach("cancel", turnID: model.coachPendingID!)
    while model.coachBusy { await Task.yield() }
    gate.replies.removeFirst().resume()
    for _ in 0..<100 { await Task.yield() }
    #expect(model.coach?.turns.isEmpty == true)
    #expect(gate.calls == ["GET", "POST", "POST", "POST"])
    gate.status = 401
    await model.loadCoach()
    #expect(!model.session.canWrite)
    #expect(model.coach == nil)
}
@Test @MainActor func coachAssessmentIsImmediateDurableAndFenced() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    await model.loadCoach()
    gate.hold = true
    model.sendCoach("answer", text: "  beim  ", turnID: "saved")
    #expect(model.coach?.turns.first?.attempt?.answer == "  beim  ")
    #expect(model.coach?.turns.first?.attempt?.assessmentState == "pending")
    model.sendCoach("answer", text: "duplicate", turnID: "saved")
    while gate.replies.isEmpty { await Task.yield() }
    #expect(gate.calls == ["GET", "POST"])
    let cache = ContentCache(root: root)
    let data = try await cache.load(dataset: "coach", server: model.session.serverURL, owner: "coach-fixture")
    #expect(data != nil)
    let saved = try JSONDecoder().decode(CoachSnapshot.self, from: data!)
    #expect(saved.turns.first?.attempt?.answer == "  beim  ")
    #expect(saved.turns.first?.attempt?.assessmentState == "pending")
    model.resetSessionContent()
    gate.replies.removeFirst().resume()
    for _ in 0..<100 { await Task.yield() }
    #expect(model.coach == nil)
}
@Test @MainActor func coachAssessmentStorageFailureNeverSends() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    await model.loadCoach()
    try FileManager.default.removeItem(at: root)
    try Data("blocked".utf8).write(to: root)
    model.sendCoach("answer", text: "  beim  ", turnID: "saved")
    while model.coachBusy { await Task.yield() }
    #expect(gate.calls == ["GET"])
    #expect(model.coach?.turns.first?.attempt?.answer == "  beim  ")
    #expect(model.coachError == "coach.error.storage")
}
@Test @MainActor func coachReadOnlyCacheAndLateReset() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    await model.loadCoach()
    #expect(model.coach?.turns.first?.message == "Saved coach turn")
    #expect(gate.calls == ["GET"])
    gate.offline = true
    let offline = try await gate.model(root)
    await offline.loadCoach()
    #expect(offline.coach?.turns.count == 1)
    #expect(!offline.session.canWrite)
    offline.sendCoach("message", text: "No offline inference")
    #expect(gate.calls == ["GET"])
    gate.offline = false; gate.hold = true
    model.sendCoach("message", text: "Practice")
    model.sendCoach("message", text: "Duplicate")
    while gate.replies.isEmpty { await Task.yield() }
    #expect(gate.calls == ["GET", "POST"])
    model.resetSessionContent()
    gate.replies.forEach { $0.resume() }; gate.replies = []
    for _ in 0..<100 { await Task.yield() }
    #expect(model.coach == nil)
    #expect(!model.coachBusy)
}

@Test @MainActor func coachUnreceivedAnswerSurvivesRefreshAndRelaunchWithoutPosting() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    await model.loadCoach()
    gate.failPost = true
    model.sendCoach("answer", text: "  beim  ", turnID: "saved")
    while model.coachBusy { await Task.yield() }
    let requestID = try #require(model.coach?.turns.first?.attempt?.id)
    await model.loadCoach()
    #expect(model.coach?.turns.first?.attempt?.answer == "  beim  ")
    #expect(model.coach?.turns.first?.attempt?.id == requestID)
    let relaunched = try await gate.model(root)
    await relaunched.loadCoach()
    #expect(relaunched.coach?.turns.first?.attempt?.answer == "  beim  ")
    #expect(relaunched.coach?.turns.first?.attempt?.id == requestID)
    #expect(relaunched.coach?.turns.first?.attempt?.canRecheck == true)
    #expect(gate.calls == ["GET", "POST", "GET", "GET"])
    // Explicit recovery uses the same answer request, never recheck on a missing server attempt.
    relaunched.sendCoach("recheck", turnID: "saved")
    while relaunched.coachBusy { await Task.yield() }
    #expect(gate.actions.last?.action == "answer")
    #expect(gate.actions.last?.requestID == requestID)
    #expect(gate.actions.last?.text == "  beim  ")
}

extension CoachGate {
    func snapshot(attemptID: String, state: String = "failed", answer: String = "  beim  ") throws -> String {
        var object = try JSONSerialization.jsonObject(with: Data(body.utf8)) as! [String: Any]
        var turns = object["turns"] as! [[String: Any]]
        turns[0]["attempt"] = ["id": attemptID, "answer": answer, "outcome": "ambiguous", "original_outcome": "ambiguous", "assisted": false, "at": "now", "excluded": false, "assessment_state": state]
        object["turns"] = turns
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

@Test @MainActor func coachUnreceivedRecheckKeepsIdentityUntilMatchingAcknowledgement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate()
    gate.bodyOverride = try gate.snapshot(attemptID: "prior")
    let model = try await gate.model(root)
    await model.loadCoach()
    gate.failPost = true
    model.sendCoach("recheck", turnID: "saved")
    while model.coachBusy { await Task.yield() }
    let requestID = try #require(model.coach?.turns.first?.attempt?.id)
    await model.loadCoach()
    #expect(model.coach?.turns.first?.attempt?.id == requestID)
    let relaunched = try await gate.model(root)
    await relaunched.loadCoach()
    #expect(relaunched.coach?.turns.first?.attempt?.id == requestID)
    #expect(relaunched.coach?.turns.first?.attempt?.answer == "  beim  ")
    #expect(gate.actions.count == 1)
    gate.failPost = false
    gate.bodyOverride = try gate.snapshot(attemptID: requestID, state: "completed")
    relaunched.sendCoach("recheck", turnID: "saved")
    while relaunched.coachBusy { await Task.yield() }
    #expect(gate.actions.count == 2)
    #expect(gate.actions.last?.action == "recheck")
    #expect(gate.actions.last?.requestID == requestID)
    #expect(relaunched.coach?.turns.first?.attempt?.assessmentState == "completed")
    #expect(relaunched.coach?.turns.first?.attempt?.localRequest == nil)
    let acknowledged = try await gate.model(root)
    await acknowledged.loadCoach()
    #expect(acknowledged.coach?.turns.first?.attempt?.assessmentState == "completed")
    #expect(acknowledged.coach?.turns.first?.attempt?.localRequest == nil)
    #expect(gate.actions.count == 2)
}

@Test @MainActor func coachMissingTurnsRetainLiteralUntilExplicitRemoval() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    await model.loadCoach()
    gate.failPost = true
    model.sendCoach("answer", text: "  beim  ", turnID: "saved")
    while model.coachBusy { await Task.yield() }
    let requestID = try #require(model.coach?.turns.first?.attempt?.id)
    gate.bodyOverride = #"{"turns":[],"observations":[],"model":"gpt-6.1-terra","reset_at":"later"}"#
    await model.loadCoach()
    let relaunched = try await gate.model(root)
    await relaunched.loadCoach()
    #expect(relaunched.coach?.turns.first?.attempt?.answer == "  beim  ")
    #expect(relaunched.coach?.turns.first?.attempt?.canRecheck == true)
    // A missing server exercise cannot be reassessed. Explicit cancel remains reachable.
    relaunched.sendCoach("recheck", turnID: "saved")
    #expect(relaunched.coachError == "coach.error.conflict")
    #expect(gate.actions.count == 1)
    gate.failPost = false
    relaunched.sendCoach("message", text: "Another practice")
    while relaunched.coachBusy { await Task.yield() }
    #expect(relaunched.coach?.turns.first?.attempt?.answer == "  beim  ")
    relaunched.sendCoach("cancel", turnID: requestID)
    while relaunched.coachBusy { await Task.yield() }
    #expect(relaunched.coach?.turns.isEmpty == true)
    let cleared = try await gate.model(root)
    await cleared.loadCoach()
    #expect(cleared.coach?.turns.isEmpty == true)
    #expect(gate.actions.map(\.action) == ["answer", "message", "cancel"])
}

@Test @MainActor func coachUnacknowledgedAnswerDoesNotCrossAccounts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    await model.loadCoach()
    gate.failPost = true
    model.sendCoach("answer", text: "private A", turnID: "saved")
    while model.coachBusy { await Task.yield() }
    gate.owner = "account-B"
    await model.session.restore()
    await model.loadCoach()
    #expect(model.coach?.turns.first?.attempt == nil)
    let relaunchedB = try await gate.model(root)
    await relaunchedB.loadCoach()
    #expect(relaunchedB.coach?.turns.first?.attempt == nil)
    #expect(gate.actions.count == 1)
    gate.owner = "coach-fixture"
    let relaunchedA = try await gate.model(root)
    await relaunchedA.loadCoach()
    #expect(relaunchedA.coach?.turns.first?.attempt?.answer == "private A")
}

@Test @MainActor func coachExplicitResetRemovesUnacknowledgedAnswer() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    await model.loadCoach()
    gate.failPost = true
    model.sendCoach("answer", text: "literal", turnID: "saved")
    while model.coachBusy { await Task.yield() }
    gate.failPost = false
    gate.bodyOverride = #"{"turns":[],"observations":[],"model":"gpt-6.1-terra"}"#
    model.sendCoach("reset")
    while model.coachBusy { await Task.yield() }
    let relaunched = try await gate.model(root)
    await relaunched.loadCoach()
    #expect(relaunched.coach?.turns.isEmpty == true)
    #expect(gate.actions.map(\.action) == ["answer", "reset"])
}

@Test @MainActor func coachQuickSendKeepsDraftAndCoalesces() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    await model.loadCoach(); model.coachDraft = "30 seconds"; gate.hold = true
    model.sendCoach("message", text: "30 seconds", preserveDraft: true)
    model.sendCoach("message", text: "30 seconds", preserveDraft: true)
    #expect(model.coachBusy)
    while gate.replies.isEmpty { await Task.yield() }
    #expect(gate.actions.count == 1)
    gate.hold = false; gate.replies.removeFirst().resume()
    while model.coachBusy { await Task.yield() }
    #expect(model.coachDraft == "30 seconds")
}

@Test @MainActor func coachCancelledViewportCallbackNeverPosts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    gate.bodyOverride = gate.body.replacingOccurrences(of: "\"language\":\"de\"", with: "\"language\":\"de\",\"message_version\":\"saved:completed\"")
    await model.loadCoach(); let turn = try #require(model.coach?.turns.first)
    let callback = Task { await model.seeCoach(turn) }; callback.cancel(); await callback.value
    #expect(gate.actions.isEmpty)
}

@Test @MainActor func coachStaleViewportTurnCannotSendAfterOwnerReplacement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    gate.bodyOverride = gate.body.replacingOccurrences(of: "\"language\":\"de\"", with: "\"language\":\"de\",\"message_version\":\"saved:completed\"")
    await model.loadCoach(); let old = try #require(model.coach?.turns.first)
    gate.owner = "replacement"; await model.session.restore()
    await model.seeCoach(old)
    #expect(gate.actions.isEmpty)
    #expect(model.coach == nil)
}

@Test @MainActor func coachSeenRevocationClearsOwnerAndCachedConversation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    gate.bodyOverride = gate.body.replacingOccurrences(of: "\"language\":\"de\"", with: "\"language\":\"de\",\"message_version\":\"saved:completed\"")
    await model.loadCoach()
    let turn = try #require(model.coach?.turns.first)
    gate.status = 401
    await model.seeCoach(turn)
    #expect(!model.session.canWrite)
    #expect(model.coach == nil)
}

@Test @MainActor func coachSeenReceiptFencesLogoutAndDoesNotReplaceConversation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CoachGate(); let model = try await gate.model(root)
    gate.bodyOverride = gate.body.replacingOccurrences(of: "\"language\":\"de\"", with: "\"language\":\"de\",\"message_version\":\"saved:completed\",\"seen_version\":\"\"")
    await model.loadCoach(); let turn = model.coach!.turns[0]
    gate.hold = true
    let seen = Task { await model.seeCoach(turn) }
    while gate.replies.isEmpty { await Task.yield() }
    await model.seeCoach(turn)
    #expect(gate.actions.map(\.action) == ["seen"])
    model.resetSessionContent(); gate.replies.removeFirst().resume(); await seen.value
    #expect(model.coach == nil)
}
