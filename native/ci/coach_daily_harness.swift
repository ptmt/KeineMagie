import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@MainActor final class DailyCoachGate {
    var actions: [CoachAction] = []
    var verdict = "correct"
    var fail = false
    var hold = false
    var release: CheckedContinuation<Void, Never>?
    var cached = #"{"turns":[{"id":"exercise","text":"","state":"completed","assisted":false,"language":"de","kind":"cloze","prompt":"Ich warte ___ den Bus."}],"observations":[],"model":"fixture"}"#
    func send(_ request: URLRequest) async throws -> AuthResponse {
        if request.url!.path == "/v1/auth/session" {
            return AuthResponse(data: Data(#"{"user":{"id":"daily-owner"},"expires_at":"2099-01-01T00:00:00Z"}"#.utf8), status: 200)
        }
        if request.httpMethod == "POST" {
            let action = try JSONDecoder().decode(CoachAction.self, from: request.httpBody!)
            actions.append(action)
            if hold { await withCheckedContinuation { release = $0 } }
            if fail { throw URLError(.notConnectedToInternet) }
            if ["answer", "recheck"].contains(action.action) {
                var object = try JSONSerialization.jsonObject(with: Data(cached.utf8)) as! [String: Any]
                var turns = object["turns"] as! [[String: Any]]
                turns[0]["attempt"] = ["id":action.requestID,"answer":action.text,"outcome":verdict == "correct" ? "correct" : "wrong","original_outcome":"ambiguous","assisted":false,"at":"now","excluded":false,"assessment_state":"completed","assessment":["verdict":verdict,"corrected_answer":"auf","explanation":"fixture","uncertainty_reason":""]]
                object["turns"] = turns
                cached = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            }
        }
        return AuthResponse(data: Data(cached.utf8), status: 200)
    }
    func model(_ root: URL) async throws -> AppModel {
        let transport: AuthClient.Transport = { try await self.send($0) }
        let session = SessionController(serverURL:"https://daily.invalid",readToken:{"synthetic"},saveToken:{_ in},transport:transport)
        await session.restore()
        return AppModel(session:session,client:APIClient(endpoint:try ServerEndpoint("https://daily.invalid"),token:"synthetic",transport:transport),podcastClient:PodcastAPI(endpoint:try ServerEndpoint("https://daily.invalid"),token:"synthetic",transport:transport),cache:ContentCache(root:root))
    }
}
@Test @MainActor func dailyEntryRequiresForegroundAndCarriesLocalZone() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let gate = DailyCoachGate(), model = try await gate.model(root)
    await model.loadCoach()
    #expect(gate.actions.isEmpty)
    model.sendCoach("entry")
    #expect(gate.actions.isEmpty)
    model.coachForeground = true; model.sendCoach("entry")
    #expect(model.coachPendingID != nil)
    while model.coachBusy { await Task.yield() }
    #expect(gate.actions.map(\.action) == ["entry"])
    #expect(gate.actions.first?.timeZone == TimeZone.current.identifier)
}
@Test @MainActor func dailyAssessmentHapticsCountOnlyExplicitForegroundTransitions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let gate = DailyCoachGate(), model = try await gate.model(root)
    var feedback: [String] = []
    model.coachAssessmentHaptic = { feedback.append($0) }
    model.coachForeground = true
    await model.loadCoach(); #expect(feedback.isEmpty)
    for verdict in ["correct", "incorrect", "partially_correct", "uncertain"] {
        gate.verdict = verdict
        model.sendCoach("answer",text:"auf",turnID:"exercise")
        model.sendCoach("answer",text:"duplicate",turnID:"exercise")
        while model.coachBusy { await Task.yield() }
    }
    #expect(feedback == ["correct", "wrong", "wrong"])
    await model.loadCoach()
    model.sendCoach("reveal",text:"answer",turnID:"exercise")
    while model.coachBusy { await Task.yield() }
    #expect(feedback.count == 3)
    let relaunched = try await gate.model(root)
    relaunched.coachAssessmentHaptic = { feedback.append($0) }; relaunched.coachForeground = true
    await relaunched.loadCoach(); #expect(feedback.count == 3)
    gate.verdict = "correct"; gate.hold = true
    model.sendCoach("answer",text:"auf",turnID:"exercise")
    while gate.release == nil { await Task.yield() }
    model.coachForeground = false
    gate.hold = false; gate.release?.resume(); gate.release = nil
    while model.coachBusy { await Task.yield() }
    #expect(feedback.count == 3)
    model.coachForeground = true; gate.fail = true
    model.sendCoach("answer",text:"auf",turnID:"exercise")
    while model.coachBusy { await Task.yield() }
    #expect(feedback.count == 3)
    // Explicit local receipt recovery must stay silent even if it completes.
    gate.fail = false
    model.sendCoach("recheck",turnID:"exercise")
    while model.coachBusy { await Task.yield() }
    #expect(feedback.count == 3)
}
