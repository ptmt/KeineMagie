import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@MainActor final class PassageGate {
    var stars = Set<Int>()
    var revision = 0
    var calls: [URLRequest] = []
    var holdWrite = false
    var holdRead = false
    var releases: [CheckedContinuation<Void, Never>] = []
    var unauthorized = false
    var offline = false
    var owner = "passage-owner"
    var proof: SavedNativeIdentity?
    var failWrite = false
    var wire: String {
        let ids = stars.sorted()
        let groups = ids.map { "{\"id\":\"pg_\($0)\",\"job_id\":\"\(job.id)\",\"segment_ids\":[\($0)],\"start\":0,\"end\":10}" }.joined(separator: ",")
        return "{\"version\":1,\"revision\":\(revision),\"job_id\":\"\(job.id)\",\"favorite_segment_ids\":\(ids),\"groups\":[\(groups)]}"
    }
    var job: PodcastJob { try! JSONDecoder().decode(PodcastJob.self, from: Data(LearningGate.job.utf8)) }
    func send(_ r: URLRequest) async throws -> AuthResponse {
        calls.append(r)
        if offline { throw URLError(.notConnectedToInternet) }
        if r.url!.path == "/v1/auth/session" { return AuthResponse(data: Data("{\"user\":{\"id\":\"\(owner)\"},\"expires_at\":\"2099-12-01T00:00:00Z\"}".utf8), status: 200) }
        let old = wire
        if (holdWrite && r.httpMethod == "PUT") || (holdRead && r.httpMethod == "GET") { await withCheckedContinuation { releases.append($0) } }
        if unauthorized { return AuthResponse(data: Data(), status: 401) }
        if r.httpMethod == "PUT" {
            if failWrite { return AuthResponse(data: Data(), status: 503) }
            let body = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String:Bool]
            let id = Int(r.url!.lastPathComponent)!
            if body["favorite"] == true { stars.insert(id) } else { stars.remove(id) }; revision += 1
            return AuthResponse(data: Data("{\"passage_groups\":\(wire)}".utf8), status: 200)
        }
        return AuthResponse(data: Data(old.utf8), status: 200)
    }
    func model(_ root: URL) async throws -> AppModel {
        let transport: AuthClient.Transport = { try await self.send($0) }
        let session = SessionController(serverURL: "https://passage.invalid", readToken: { "synthetic" }, saveToken: { _ in }, readIdentity: { self.proof }, saveIdentity: { self.proof = $0 }, transport: transport)
        await session.restore()
        let endpoint = try ServerEndpoint("https://passage.invalid")
        return AppModel(session: session, client: APIClient(endpoint: endpoint, token: "synthetic", transport: transport), podcastClient: PodcastAPI(endpoint: endpoint, token: "synthetic", transport: transport), cache: ContentCache(root: root))
    }
    func release() { releases.forEach { $0.resume() }; releases = [] }
}
@Test @MainActor func passageMutationPersistsOfflineAndIsOwnerScoped() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = PassageGate(); let model = try await gate.model(root)
    await model.loadPassageGroups(gate.job)
    await model.setPassage(gate.job, index: 0, favorite: true)
    #expect(model.episodeLearning[gate.job.id]?.passageGroups?.starredIDs == [0])
    #expect(gate.calls.filter { $0.httpMethod == "PUT" }.count == 1)
    #expect(gate.calls.last?.value(forHTTPHeaderField: "X-Passage-Owner") == gate.owner)
    gate.offline = true
    let offline = try await gate.model(root)
    await offline.loadPassageGroups(gate.job)
    #expect(offline.episodeLearning[gate.job.id]?.passageGroups?.starredIDs == [0])
    let count = gate.calls.count
    await offline.setPassage(gate.job, index: 0, favorite: false)
    #expect(gate.calls.count == count)
    gate.offline = false; gate.owner = "other-owner"
    let other = try await gate.model(root)
    gate.holdRead = true
    let task = Task { await other.loadPassageGroups(gate.job) }
    while gate.releases.isEmpty { await Task.yield() }
    #expect(other.episodeLearning[gate.job.id]?.passageGroups == nil)
    other.resetSessionContent(); gate.release(); await task.value
    #expect(other.episodeLearning.isEmpty)
}
@Test @MainActor func passageWriteCoalescesAndOlderReadCannotUndoIt() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = PassageGate(); let model = try await gate.model(root)
    await model.loadPassageGroups(gate.job)
    gate.holdRead = true
    let read = Task { await model.loadPassageGroups(gate.job) }
    while gate.releases.isEmpty { await Task.yield() }
    gate.holdRead = false; gate.holdWrite = true
    let save = Task { await model.setPassage(gate.job, index: 0, favorite: true) }
    while gate.releases.count < 2 { await Task.yield() }
    await model.setPassage(gate.job, index: 0, favorite: true)
    #expect(gate.calls.filter { $0.httpMethod == "PUT" }.count == 1)
    gate.releases.removeLast().resume(); await save.value
    gate.release(); await read.value
    #expect(model.episodeLearning[gate.job.id]?.passageGroups?.starredIDs == [0])
    gate.holdWrite = false; gate.unauthorized = true
    await model.setPassage(gate.job, index: 0, favorite: false)
    #expect(model.episodeLearning.isEmpty)
    #expect(gate.proof == nil)
}
@Test @MainActor func passageFailureKeepsConfirmedStateAndResetRejectsLateWrite() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = PassageGate(); let model = try await gate.model(root)
    await model.loadPassageGroups(gate.job)
    gate.failWrite = true
    await model.setPassage(gate.job, index: 0, favorite: true)
    #expect(model.episodeLearning[gate.job.id]?.passageGroups?.starredIDs.isEmpty == true)
    #expect(model.passageErrors[gate.job.id] != nil)
    gate.failWrite = false; gate.holdWrite = true
    let write = Task { await model.setPassage(gate.job, index: 0, favorite: true) }
    while gate.releases.isEmpty { await Task.yield() }
    model.resetSessionContent(); gate.release(); await write.value
    #expect(model.episodeLearning.isEmpty)
}
