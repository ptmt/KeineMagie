import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@MainActor private final class AssessmentGate {
    var calls: [URLRequest] = []
    var release: CheckedContinuation<Void,Never>?
    var receipt = false
    var state = "pending"
    func response() throws -> Data {
        let assessment: [String:Any] = ["id":"receipt","revision":0,"source":"Die kleine Katze schläft.","answer":"Die Katze schläft.","at":"now","assisted":false,"replay_tracking":"unknown","state":state,"sent":true,"alignment":["version":1,"complete":false,"spans":[],"source_words":4,"attempted_words":4,"exact_words":3,"omissions":1,"additions":0,"substitutions":0,"unattempted_words":0]]
        var value: [String:Any] = ["id":"assessment","title":"Test","language":"de","created":"now","mode":"whole","step":0,"replays":0,"draft":"Die Katze schläft.","revision":receipt ? 1 : 0,"checked":receipt,"assisted":false,"plan":[["kind":"whole","asset":0]],"ready":[]]
        if receipt { value["assessment"] = assessment }
        return try JSONSerialization.data(withJSONObject:value)
    }
    func send(_ request: URLRequest) async throws -> AuthResponse {
        if request.url!.path == "/v1/auth/session" { return AuthResponse(data:Data(#"{"user":{"id":"assessment-owner"},"expires_at":"2099-01-01T00:00:00Z"}"#.utf8),status:200) }
        calls.append(request)
        if request.url!.path.hasSuffix("/check") {
            receipt=true
            await withCheckedContinuation {release=$0}
            throw URLError(.networkConnectionLost) // accepted POST, lost acknowledgement
        }
        if request.url!.path.hasSuffix("/cancel-assessment") { state="canceled" }
        return AuthResponse(data:try response(),status:200)
    }
}

@Test @MainActor func nativeHybridCheckPublishesPendingAndRecoversLostAckByGetOnly() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let gate=AssessmentGate()
    let transport: AuthClient.Transport = {try await gate.send($0)}
    let session=SessionController(serverURL:"https://assessment.invalid",readToken:{"synthetic"},saveToken:{_ in},transport:transport)
    await session.restore()
    let model=AppModel(session:session,client:APIClient(endpoint:try ServerEndpoint("https://assessment.invalid"),token:"synthetic",transport:transport),podcastClient:PodcastAPI(endpoint:try ServerEndpoint("https://assessment.invalid"),token:"synthetic",transport:transport),cache:ContentCache(root:root),outboxStore:TranslationOutboxStore(root:root.appendingPathComponent("outbox")))
    try model.hydrateDictations()
    try model.dictationDrafts.accept(JSONDecoder().decode(DictationRecord.self,from:gate.response()))
    #expect(gate.calls.isEmpty)
    let task=Task { try await model.checkDictation(id:"assessment",complete:false,locale:"ru") }
    while gate.release == nil {await Task.yield()}
    try await model.recoverDictationAssessment(id:"assessment")
    #expect(model.dictationDrafts.record("assessment")?.assessment?.state == "pending")
    #expect(model.dictationChecking.contains("assessment"))
    let body=try #require(JSONSerialization.jsonObject(with:gate.calls.first!.httpBody!) as? [String:Any])
    #expect(body["hybrid"] as? Bool == true); #expect(body["locale"] as? String == "ru")
    #expect(body["complete"] as? Bool == false)
    gate.state="failed";gate.release?.resume();try await task.value
    #expect(model.dictationDrafts.record("assessment")?.assessment?.state == "failed")
    try await model.checkDictation(id:"assessment",complete:true,locale:"en")
    try await model.recoverDictationAssessment(id:"assessment")
    #expect(gate.calls.filter{$0.url!.path.hasSuffix("/check")}.count == 1)
    #expect(!model.dictationChecking.contains("assessment"))
    #expect(model.dictationDrafts.record("assessment")?.draft == "Die Katze schläft.")
}
