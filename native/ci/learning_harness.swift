import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@MainActor final class LearningGate {
    var calls: [(String, String)] = []
    var holdProfileWrite = false
    var holdVocabulary = false
    var held = false
    var failVocabulary = false
    var unauthorized = false
    var releases: [CheckedContinuation<Void, Never>] = []
    var proof: SavedNativeIdentity?
    var level = "B1"
    var authOffline = false
    static let job = #"{"id":"synthetic-job-000000001","url":"https://audio.example/episode.mp3","source_language":"de","target_language":"ru","state":"completed","progress":100,"segments":[{"start":0,"end":10,"text":"Hallo","translation":"Привет"}]}"#
    func send(_ request: URLRequest) async throws -> AuthResponse {
        let path = request.url!.path
        calls.append((path, request.httpMethod!))
        if path == "/v1/auth/session" {
            if authOffline { throw URLError(.notConnectedToInternet) }
            return AuthResponse(data: Data(#"{"user":{"id":"synthetic-learning-owner"},"expires_at":"2099-12-01T00:00:00Z"}"#.utf8), status: 200)
        }
        if held || (holdVocabulary && path.hasSuffix("/vocabulary")) || (holdProfileWrite && request.httpMethod == "PUT") { await withCheckedContinuation { releases.append($0) } }
        if unauthorized { return AuthResponse(data: Data(), status: 401) }
        if path.hasSuffix("/vocabulary") && failVocabulary { return AuthResponse(data: Data(), status: 503) }
        let body: String
        if path.hasSuffix("/analysis") { body = #"{"state":"completed","result":{"narrative":[{"text":"Saved summary","citations":[{"segment_id":0,"quote":"Hallo"}]}],"topics":[],"recommendations":[]}}"# }
        else if path.hasSuffix("/vocabulary") { body = #"{"items":[{"id":"word","term":"Hallo","translation":"Привет","favorite":true,"status":"saved","segment_id":0,"quote":"Hallo"}]}"# }
        else {
            if request.httpMethod == "PUT" { level = (try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String])["cefr"]! }
            body = "{\"language\":\"\(request.url!.lastPathComponent)\",\"cefr\":\"\(level)\",\"self_assessments\":[{\"cefr\":\"\(level)\",\"assessed_at\":\"2026-11-12T12:00:00Z\"}]}"
        }
        return AuthResponse(data: Data(body.utf8), status: 200)
    }
    func model(root: URL) async throws -> AppModel {
        let transport: AuthClient.Transport = { try await self.send($0) }
        let session = SessionController(serverURL: "https://learning.invalid", readToken: { "synthetic" }, saveToken: { _ in }, readIdentity: { self.proof }, saveIdentity: { self.proof = $0 }, transport: transport)
        await session.restore()
        let endpoint = try ServerEndpoint("https://learning.invalid")
        return AppModel(session: session, client: APIClient(endpoint: endpoint, token: "synthetic", transport: transport), podcastClient: PodcastAPI(endpoint: endpoint, token: "synthetic", transport: transport), cache: ContentCache(root: root))
    }
    var job: PodcastJob { try! JSONDecoder().decode(PodcastJob.self, from: Data(Self.job.utf8)) }
}
@Test @MainActor func learningIsReadOnlyCoalescedAndRejectsLateReset() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = LearningGate(); let model = try await gate.model(root: root)
    gate.held = true
    let task = Task { await model.loadEpisodeLearning(gate.job) }
    while gate.releases.count < 2 { await Task.yield() }
    await model.loadEpisodeLearning(gate.job)
    #expect(gate.calls.filter { $0.0.hasPrefix("/v1/learning/") }.count == 2)
    #expect(gate.calls.allSatisfy { $0.1 == "GET" })
    model.resetSessionContent()
    gate.releases.forEach { $0.resume() }; gate.releases = []
    await task.value
    #expect(model.episodeLearning.isEmpty)
}
@Test @MainActor func learningPersistsAcrossOfflineRelaunchAndPartialFailureRetainsWords() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = LearningGate(); let model = try await gate.model(root: root)
    await model.loadEpisodeLearning(gate.job)
    await model.loadLearningProfile("de", assessment: "B2")
    #expect(model.learningProfiles["de"]?.cefr == "B2")
    #expect(gate.calls.suffix(2).map { $0.1 } == ["PUT", "GET"])
    gate.failVocabulary = true
    await model.loadEpisodeLearning(gate.job)
    #expect(model.episodeLearning[gate.job.id]?.vocabulary?.count == 1)
    #expect(model.learningErrors[gate.job.id] != nil)
    gate.authOffline = true
    let offline = try await gate.model(root: root)
    let count = gate.calls.count
    await offline.loadEpisodeLearning(gate.job)
    await offline.loadLearningProfile("de", assessment: "C1")
    #expect(!offline.session.canWrite)
    #expect(gate.calls.count == count)
    #expect(offline.episodeLearning[gate.job.id]?.analysis?.result?.narrative.first?.text == "Saved summary")
    #expect(offline.learningProfiles["de"]?.cefr == "B2")
}
@Test @MainActor func savedSummaryDoesNotWaitForVocabularyReadiness() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = LearningGate(); let model = try await gate.model(root: root)
    gate.holdVocabulary = true
    let task = Task { await model.loadEpisodeLearning(gate.job) }
    while gate.releases.isEmpty { await Task.yield() }
    for _ in 0..<100 { await Task.yield() }
    #expect(model.episodeLearning[gate.job.id]?.analysis?.result?.narrative.first?.text == "Saved summary")
    gate.releases.forEach { $0.resume() }; gate.releases = []
    await task.value
}
@Test @MainActor func profileRefreshCannotSupersedePendingAssessment() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = LearningGate(); let model = try await gate.model(root: root)
    await model.loadLearningProfile("de")
    gate.holdProfileWrite = true
    let save = Task { await model.loadLearningProfile("de", assessment: "B2") }
    while gate.releases.isEmpty { await Task.yield() }
    await model.loadLearningProfile("de")
    gate.releases.forEach { $0.resume() }; gate.releases = []
    await save.value
    #expect(gate.level == "B2")
    #expect(model.learningProfiles["de"]?.cefr == "B2")
}
@Test @MainActor func profileAssessmentSupersedesOlderReadAndRejectsLateReset() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = LearningGate(); let model = try await gate.model(root: root)
    gate.held = true
    let read = Task { await model.loadLearningProfile("de") }
    while gate.releases.isEmpty { await Task.yield() }
    gate.held = false
    await model.loadLearningProfile("de", assessment: "B2")
    gate.releases.forEach { $0.resume() }; gate.releases = []
    await read.value
    #expect(model.learningProfiles["de"]?.cefr == "B2")
    gate.holdProfileWrite = true
    let write = Task { await model.loadLearningProfile("de", assessment: "C1") }
    while gate.releases.isEmpty { await Task.yield() }
    model.resetSessionContent()
    gate.releases.forEach { $0.resume() }; gate.releases = []
    await write.value
    #expect(model.learningProfiles.isEmpty)
}
@Test @MainActor func unauthorizedProfileInvalidatesOfflineProvenance() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = LearningGate(); let model = try await gate.model(root: root)
    await model.loadLearningProfile("de")
    gate.unauthorized = true
    await model.loadLearningProfile("de", assessment: "B2")
    #expect(model.learningProfiles.isEmpty)
    #expect(gate.proof == nil)
    #expect(!model.session.canWrite)
}
@Test @MainActor func unauthorizedLearningClearsProvenanceAndPrivateState() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = LearningGate(); let model = try await gate.model(root: root)
    await model.loadEpisodeLearning(gate.job)
    gate.unauthorized = true
    await model.loadEpisodeLearning(gate.job)
    #expect(model.episodeLearning.isEmpty)
    #expect(gate.proof == nil)
    #expect(!model.session.canWrite)
}
