import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

/// Real AppModel, journal, API and playback controller. Only AVAudioSession/media
/// output is replaced for macOS; real audio/clock acceptance is in Release UITests.
@MainActor private final class GlobalPlaybackGate {
    var values: [String: DictationRecord] = [:]
    var calls: [(String,String)] = []
    var commands: [(String,DictationPlaybackRequest)] = []
    var heldID: String?
    var release: CheckedContinuation<Void,Never>?
    var status = 200
    var holdSession = false
    var sessionRelease: CheckedContinuation<Void,Never>?
    func record(_ id: String, ready: Bool = true) throws -> DictationRecord {
        try JSONDecoder().decode(DictationRecord.self,from:Data("""
        {"id":"\(id)","title":"Attempt \(id)","language":"de","created":"now","mode":"whole","step":0,"replays":0,"draft":"private draft \(id)","revision":1,"checked":false,"assisted":false,"plan":[{"kind":"whole","asset":0}],"ready":\(ready ? "[0]" : "[]"),"playback_policy_version":1,"playback":{"revision":1,"whole_starts":0,"cursor":1,"final_used":false}}
        """.utf8))
    }
    func send(_ r: URLRequest) async throws -> AuthResponse {
        let path = r.url!.path
        if path == "/v1/auth/session" {
            if holdSession { await withCheckedContinuation { sessionRelease = $0 } }
            return AuthResponse(data:Data(#"{"user":{"id":"global-owner"},"expires_at":"2099-01-01T00:00:00Z"}"#.utf8),status:200)
        }
        calls.append((r.httpMethod ?? "GET",path))
        let parts = path.split(separator:"/")
        let id = String(parts[3])
        if heldID == id { await withCheckedContinuation { release = $0 } }
        if status != 200 { return AuthResponse(data:Data(),status:status) }
        if path.contains("/audio/") { return AuthResponse(data:Data([0]),status:200) }
        var value = values[id]!
        if path.hasSuffix("/playback") {
            let command = try JSONDecoder().decode(DictationPlaybackRequest.self,from:r.httpBody!)
            commands.append((id,command))
            let revision = (value.playback?.revision ?? 0) + 1
            let starts = (value.playback?.wholeStarts ?? 0) + (command.action == "start" ? 1 : 0)
            let active: [String:Any] = ["id":command.id,"client":command.client,"step":command.step,"fence":revision,"offset":command.offset,"lease_until":command.action == "release" ? Int64(0) : Int64(2000000000000),"done":false]
            let ledger = try JSONDecoder().decode(DictationPlayback.self,from:JSONSerialization.data(withJSONObject:["revision":revision,"whole_starts":starts,"cursor":1,"final_used":false,"active":active]))
            value.playback = ledger; values[id] = value
            return AuthResponse(data:try JSONEncoder().encode(ledger),status:200)
        }
        return AuthResponse(data:try JSONEncoder().encode(value),status:200)
    }
    func model(_ root: URL) async throws -> AppModel {
        let transport: AuthClient.Transport = { request in try await self.send(request) }
        let session = SessionController(serverURL:"https://global.invalid",readToken:{"synthetic"},saveToken:{_ in},transport:transport)
        await session.restore()
        let model = AppModel(session:session,client:APIClient(endpoint:try ServerEndpoint("https://global.invalid"),token:"synthetic",transport:transport),podcastClient:PodcastAPI(endpoint:try ServerEndpoint("https://global.invalid"),token:"synthetic",transport:transport),cache:ContentCache(root:root),outboxStore:TranslationOutboxStore(root:root.appendingPathComponent("outbox")))
        try model.hydrateDictations()
        for id in ["one","two"] { let value = try record(id); values[id] = value; try model.dictationDrafts.accept(value) }
        return model
    }
}

@Test @MainActor func globalPlaybackSelectionAndOpenAreCachedOnlyNoAdmissionOrPreparation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let gate = GlobalPlaybackGate(), session = DictationPlaybackCoordinator()
    let model = try await gate.model(root)
    #expect(!session.visible)
    session.select(gate.values["one"]!,model:model)
    #expect(session.visible)
    let identity = session.controller
    for _ in 0..<4 {
        session.select(gate.values["one"]!,model:model)
        session.requestOpen()
        #expect(session.controller === identity)
    }
    #expect(session.openRequest == 4)
    #expect(gate.calls.isEmpty)
    #expect(model.dictationDrafts.record("one")?.draft == "private draft one")
    var empty = try gate.record("empty",ready:false)
    try model.dictationDrafts.accept(empty)
    session.select(empty,model:model)
    #expect(!session.visible)
    #expect(gate.calls.isEmpty)
    empty.ready = [0]; try model.dictationDrafts.update(empty)
    #expect(session.visible)
    session.reset()
}

@Test @MainActor func globalReplacementStopsOneEngineAndReleasesOnlyOldAttempt() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let gate = GlobalPlaybackGate(), session = DictationPlaybackCoordinator()
    let model = try await gate.model(root)
    session.select(gate.values["one"]!,model:model)
    await session.controller?.play()
    #expect(session.player.playing)
    let oldCompletion = session.player.finished
    let player = session.player
    session.select(gate.values["two"]!,model:model)
    #expect(!session.player.playing)
    await session.controller?.play()
    for _ in 0..<50 { await Task.yield() }
    #expect(session.player === player)
    #expect(session.player.playing)
    oldCompletion?(true)
    for _ in 0..<20 { await Task.yield() }
    #expect(session.player.playing, "An obsolete completion must not stop the new engine")
    #expect(gate.commands.filter { $0.0 == "one" }.map { $0.1.action } == ["start","release"])
    #expect(gate.commands.filter { $0.0 == "two" }.map { $0.1.action } == ["start"])
    #expect(model.dictationDrafts.record("one")?.playback?.active?.leaseUntil == 0)
    #expect(model.dictationDrafts.record("one")?.playback?.wholeStarts == 1)
    #expect(model.dictationDrafts.record("two")?.draft == "private draft two")
    #expect(!gate.calls.contains { $0.0 == "POST" && !$0.1.hasSuffix("/playback") })
    session.reset()
}

@Test @MainActor func globalLate401FromReplacedAttemptRevokesCurrentOwnerAndHidesBar() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let gate = GlobalPlaybackGate(), session = DictationPlaybackCoordinator()
    let model = try await gate.model(root)
    session.select(gate.values["one"]!,model:model)
    gate.heldID = "one"
    let old = session.controller!
    let start = Task { await old.play() }
    while gate.release == nil { await Task.yield() }
    session.select(gate.values["two"]!,model:model)
    #expect(session.visible)
    gate.status = 401; gate.release?.resume(); gate.release = nil
    await start.value
    #expect(!model.session.canWrite)
    #expect(!session.visible)
    #expect(!session.player.playing)
    #expect(model.dictationDrafts.records.isEmpty)
    #expect(gate.commands.isEmpty)
}

@Test @MainActor func globalSameOwnerValidationKeepsSelectionClockAndReservation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let gate = GlobalPlaybackGate(), session = DictationPlaybackCoordinator()
    let model = try await gate.model(root)
    session.select(gate.values["one"]!,model:model)
    await session.controller?.play()
    let controller = session.controller
    session.player.position = 2
    session.interrupt()
    for _ in 0..<30 { await Task.yield() }
    gate.holdSession = true
    let validation = Task { await model.session.restore() }
    while gate.sessionRelease == nil { await Task.yield() }
    #expect(!model.session.canWrite)
    #expect(session.visible, "Advisory validation is not logout")
    #expect(session.disabled)
    #expect(session.controller === controller)
    #expect(session.record?.playback?.wholeStarts == 1)
    gate.sessionRelease?.resume(); gate.sessionRelease = nil
    await validation.value
    #expect(session.controller === controller)
    #expect(session.label == "dictation.resume")
    #expect(session.player.position == 2)
    #expect(session.visible)
    session.reset()
}

@Test @MainActor func globalOwnerResetFencesLateAudioAndPurgesSelectionImmediately() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let gate = GlobalPlaybackGate(), session = DictationPlaybackCoordinator()
    let model = try await gate.model(root)
    session.select(gate.values["one"]!,model:model)
    gate.heldID = "one"
    let old = session.controller!
    let start = Task { await old.play() }
    while gate.release == nil { await Task.yield() }
    model.session.rejectUnauthorized(); model.resetSessionContent(); session.reset()
    #expect(!session.visible)
    #expect(session.attemptID == nil)
    gate.release?.resume(); gate.release = nil
    await start.value
    #expect(!session.player.playing)
    #expect(model.dictationDrafts.records.isEmpty)
    #expect(gate.commands.isEmpty)
}
