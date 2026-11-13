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
    var status = 200
    var bodyOverride: String?
    let body = #"{"turns":[{"id":"saved","text":"Practice","state":"completed","at":"2026-11-13T00:00:00Z","assisted":false,"language":"de","message":"Saved coach turn","kind":"cloze","prompt":"Ich warte ___ den Bus."}],"observations":[],"model":"gpt-6.1-terra"}"#
    func send(_ r: URLRequest) async throws -> AuthResponse {
        if r.url!.path == "/v1/auth/session" {
            if offline { throw URLError(.notConnectedToInternet) }
            return AuthResponse(data: Data(#"{"user":{"id":"coach-fixture"},"expires_at":"2099-01-01T00:00:00Z"}"#.utf8), status: 200)
        }
        calls.append(r.httpMethod!)
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
