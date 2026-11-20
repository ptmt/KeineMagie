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
            var object:[String:Any] = ["revision":revision,"whole_starts":starts,"cursor":1,"final_used":false]
            if command.action != "stop" { object["active"]=active }
            let ledger = try JSONDecoder().decode(DictationPlayback.self,from:JSONSerialization.data(withJSONObject:object))
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

@Test @MainActor func policyTwoUsesRootTransportAndPreservesItsVersion() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let gate = GlobalPlaybackGate(), coordinator = DictationPlaybackCoordinator()
    let model = try await gate.model(root)
    var value = gate.values["one"]!; value.playbackPolicyVersion = 2
    gate.values["one"] = value; try model.dictationDrafts.accept(value)
    coordinator.select(value,model:model)
    #expect(!coordinator.disabled)
    #expect(coordinator.controller != nil)
    await coordinator.controller?.play()
    #expect(coordinator.player.playing)
    #expect(model.dictationDrafts.record(value.id)?.playbackPolicyVersion == 2)
    coordinator.reset()
}

@Test @MainActor func policyTwoExtraReplayUsesRootEngineAndExplicitIntent() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let gate=GlobalPlaybackGate(),coordinator=DictationPlaybackCoordinator()
    let model=try await gate.model(root)
    var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(gate.values["one"]!)) as! [String:Any]
    object["playback_policy_version"]=2;object["mode"]="sentences";object["ready"]=[0,1]
    object["plan"]=[["kind":"whole","asset":0],["kind":"sentence","asset":1],["kind":"sentence_repeat","asset":1],["kind":"final","asset":0]]
    object["playback"]=["revision":5,"whole_starts":1,"cursor":3,"final_used":false,"listens":[1,2].map { ["id":"planned-\($0)","client":"native","step":$0,"fence":$0,"offset":0,"lease_until":0,"done":true,"ended":true,"intent":"planned"] as [String:Any] }]
    let value=try JSONDecoder().decode(DictationRecord.self,from:JSONSerialization.data(withJSONObject:object))
    gate.values[value.id]=value;try model.dictationDrafts.accept(value);coordinator.select(value,model:model)
    #expect(value.lastCompletedFragment == 1)
    #expect(coordinator.canReplay(step:1));coordinator.replay(step:1)
    for _ in 0..<500 {if coordinator.player.playing {break};await Task.yield()}
    #expect(coordinator.player.playing);#expect(gate.commands.last?.1.intent == "extra")
    #expect(gate.commands.last?.1.step == 1)
    #expect(!coordinator.canReplay(step:1))
    coordinator.reset()
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

@Test @MainActor func globalOfflineStopSurvivesActualOwnerCacheAndResetsBeforeNewStart() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let gate = GlobalPlaybackGate(), session = DictationPlaybackCoordinator()
    let model = try await gate.model(root)
    session.select(gate.values["one"]!,model:model)
    let controller = try #require(session.controller)
    await controller.play()
    session.player.position = 2
    let remote = gate.values["one"]!
    gate.status = 503
    let stopped = controller.stop()
    #expect(!session.player.playing)
    #expect(controller.timing.elapsed == 0)
    let intent = try #require(model.dictationDrafts.playbackStop(id:"one"))
    await stopped.value
    #expect(model.dictationDrafts.record("one")?.playback?.wholeStarts == 1)

    // Recreate AppModel/ContentCache on the same real disk root, not an in-memory journal.
    let coldModel = try await gate.model(root)
    gate.values["one"] = remote
    let cold = DictationPlaybackCoordinator()
    cold.select(try #require(coldModel.dictationDrafts.record("one")),model:coldModel)
    #expect(coldModel.dictationDrafts.playbackStop(id:"one")?.id == intent.id)
    #expect(cold.controller?.explicitlyStopped == true)
    #expect(cold.controller?.timing.elapsed == 0)
    await cold.controller?.play()
    #expect(!cold.player.playing)
    #expect(gate.commands.map { $0.1.action } == ["start"])

    gate.status = 200
    await cold.controller?.play()
    #expect(cold.player.playing)
    #expect(cold.player.position == 0)
    #expect(gate.commands.map { $0.1.action } == ["start","stop","start"])
    #expect(coldModel.dictationDrafts.record("one")?.playback?.wholeStarts == 2)
    #expect(coldModel.dictationDrafts.playbackStop(id:"one") == nil)
    #expect(coldModel.dictationDrafts.record("one")?.draft == "private draft one")
    session.reset();cold.reset()
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
