import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@MainActor final class ProfileGate {
    var snapshot = TranslationProfileSnapshot()
    var requests: [URLRequest] = []
    var holdRead = false
    var readRelease: CheckedContinuation<Void, Never>?
    var status = 200
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("profile-fixture-" + UUID().uuidString)
    func send(_ request: URLRequest) async throws -> AuthResponse {
        if request.url!.path == "/v1/auth/session" { return AuthResponse(data: Data(#"{"user":{"id":"synthetic-profile-owner"},"expires_at":"2099-01-01T00:00:00Z"}"#.utf8), status: 200) }
        guard request.url!.path == "/v1/translation-profiles" else { throw APIError.invalidResponse }
        requests.append(request)
        let value = snapshot
        if request.httpMethod == "GET", holdRead { await withCheckedContinuation { readRelease = $0 } }
        return AuthResponse(data: try JSONEncoder().encode(value), status: status)
    }
    func model() async throws -> AppModel {
        let transport: AuthClient.Transport = { try await self.send($0) }
        let session = SessionController(serverURL: "https://profile-fixture.invalid", readToken: { "synthetic" }, saveToken: { _ in }, transport: transport)
        await session.restore()
        return AppModel(session: session, client: APIClient(endpoint: try ServerEndpoint(session.serverURL), token: "synthetic", transport: transport), cache: ContentCache(root: root.appendingPathComponent("cache")), outboxStore: TranslationOutboxStore(root: root.appendingPathComponent("outbox")), profileStore: TranslationProfileStore(root: root.appendingPathComponent("profiles")))
    }
}
@Test @MainActor func profileActualModelOldReadPreservesLocalDraftAndSingleFlight() async throws {
    let gate = ProfileGate(); let model = try await gate.model(); model.loadShortcuts()
    gate.holdRead = true
    let read = Task { await model.syncShortcuts() }
    while gate.readRelease == nil { await Task.yield() }
    let id = UUID(); model.draft = "Untouched composer é"
    try model.saveShortcut(id: id, title: "Offline pending", instruction: "Only submitted explicitly")
    await model.syncShortcuts()
    #expect(gate.requests.count == 1)
    gate.status = 503; gate.readRelease?.resume(); await read.value
    #expect(model.shortcuts.first?.title == "Offline pending")
    #expect(model.draft == "Untouched composer é")
    #expect(model.shortcutJournal.pending.count == 1)
    let cold = try await gate.model(); cold.loadShortcuts()
    #expect(cold.shortcuts.first?.id == id)
    #expect(cold.shortcutJournal.pending.count == 1)
}
@Test @MainActor func profileActualModel401PurgesCacheAndLateResponseCannotRestore() async throws {
    let gate = ProfileGate(); let model = try await gate.model(); model.loadShortcuts()
    gate.holdRead = true
    let task = Task { await model.syncShortcuts() }
    while gate.readRelease == nil { await Task.yield() }
    try model.saveShortcut(title: "Private", instruction: "Private instruction")
    gate.status = 401; gate.readRelease?.resume(); await task.value
    #expect(model.session.user == nil); #expect(model.shortcuts.isEmpty)
    let cached = try TranslationProfileStore(root: gate.root.appendingPathComponent("profiles")).load(origin: "https://profile-fixture.invalid", owner: "synthetic-profile-owner")
    #expect(cached.pending.isEmpty)
}
@Test @MainActor func profileSuperseded401PurgesCapturedScopeAfterReset() async throws {
    let gate = ProfileGate(); let model = try await gate.model(); model.loadShortcuts()
    gate.holdRead = true
    let task = Task { await model.syncShortcuts() }
    while gate.readRelease == nil { await Task.yield() }
    var journal = model.shortcutJournal
    try journal.save(id: UUID(), title: "Private pending", instruction: "Captured scope")
    try model.persistShortcuts(journal)
    model.resetSessionContent()
    gate.status = 401; gate.readRelease?.resume(); await task.value
    #expect(model.session.user == nil)
    let cached = try TranslationProfileStore(root: gate.root.appendingPathComponent("profiles")).load(origin: "https://profile-fixture.invalid", owner: "synthetic-profile-owner")
    #expect(cached.pending.isEmpty)
}

@Test @MainActor func profileActualModelResetFencesDelayedServerSnapshot() async throws {
    let gate = ProfileGate(); let model = try await gate.model(); model.loadShortcuts()
    gate.holdRead = true
    let task = Task { await model.syncShortcuts() }
    while gate.readRelease == nil { await Task.yield() }
    model.resetSessionContent(); gate.readRelease?.resume(); await task.value
    #expect(model.shortcuts.isEmpty); #expect(model.shortcutScope == nil)
}
@Test @MainActor func profileExplicitLogoutPurgesBeforeScopeReset() async throws {
    let gate = ProfileGate(); let model = try await gate.model(); model.loadShortcuts()
    gate.status = 503
    try model.saveShortcut(title: "Unsent private profile", instruction: "Must not return after logout")
    await model.logout()
    let cached = try TranslationProfileStore(root: gate.root.appendingPathComponent("profiles")).load(origin: "https://profile-fixture.invalid", owner: "synthetic-profile-owner")
    #expect(cached.pending.isEmpty)
    #expect(model.shortcuts.isEmpty)
}
@Test @MainActor func profileActualModelStorageFailureDoesNotAcknowledgeEdit() async throws {
    let gate = ProfileGate(); let model = try await gate.model(); model.loadShortcuts()
    let blocker = gate.root.appendingPathComponent("blocked")
    try Data().write(to: blocker)
    model.shortcutProfileStore = TranslationProfileStore(root: blocker)
    #expect(throws: (any Error).self) { try model.saveShortcut(title: "Must stay unsaved", instruction: "No request") }
    #expect(model.shortcuts.isEmpty); #expect(model.shortcutJournal.pending.isEmpty); #expect(gate.requests.isEmpty)
}

@Test @MainActor func profilesTwoActualAppModelsAgainstGoWire() async throws {
    guard let directory = ProcessInfo.processInfo.environment["KM_PROFILE_BRIDGE_DIR"] else { return }
    let f = try JSONDecoder().decode([String:String].self, from: Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("ready.json")))
    let origin = f["url"]!, owner = f["owner"]!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("profile-two-native-" + UUID().uuidString)
    func make(_ name: String, token: String) async throws -> AppModel {
        let session = SessionController(serverURL: origin, allowLocalHTTP: true, readToken: { token }, saveToken: { _ in })
        await session.restore()
        #expect(session.user?.id == owner)
        return AppModel(session: session, client: APIClient(endpoint: try ServerEndpoint(origin, allowLocalHTTP: true), token: token), cache: ContentCache(root: root.appendingPathComponent(name + "/cache")), outboxStore: TranslationOutboxStore(root: root.appendingPathComponent(name + "/outbox")), profileStore: TranslationProfileStore(root: root.appendingPathComponent(name + "/profiles")))
    }
    let a = try await make("a", token: f["token"]!), b = try await make("b", token: f["second_token"]!)
    await a.syncShortcuts(); await b.syncShortcuts()
    let id = UUID(); let instruction = "  Literal 👩🏽‍💻 é\nKeep meaning.  "
    try a.saveShortcut(id: id, title: "Native original", instruction: instruction)
    for _ in 0..<100 where !a.shortcutJournal.pending.isEmpty { await a.syncShortcuts(); try await Task.sleep(for: .milliseconds(10)) }
    await b.syncShortcuts()
    #expect(b.shortcuts.first(where: { $0.id == id })?.instruction == instruction)
    let oldRevision = b.shortcutJournal.revision(id)
    b.draft = "Typed while profile sync runs"
    try a.saveShortcut(id: id, title: "Remote new title", instruction: instruction)
    for _ in 0..<100 where !a.shortcutJournal.pending.isEmpty { await a.syncShortcuts(); try await Task.sleep(for: .milliseconds(10)) }
    try b.saveShortcut(id: id, title: "Conflicting local title", instruction: "Different full instruction", expectedRevision: oldRevision)
    for _ in 0..<100 where b.shortcutSyncIssue != "shortcut.sync.conflict" { await b.syncShortcuts(); try await Task.sleep(for: .milliseconds(10)) }
    #expect(b.shortcutSyncIssue == "shortcut.sync.conflict")
    #expect(b.draft == "Typed while profile sync runs")
    b.resolveShortcutConflict(keepBoth: true)
    for _ in 0..<100 where !b.shortcutJournal.pending.isEmpty { await b.syncShortcuts(); try await Task.sleep(for: .milliseconds(10)) }
    await a.syncShortcuts()
    #expect(a.shortcuts.contains { $0.title == "Remote new title" })
    #expect(a.shortcuts.contains { $0.title == "Conflicting local title" })
    b.selectedShortcutID = id.uuidString
    try a.deleteShortcut(id)
    for _ in 0..<100 where !a.shortcutJournal.pending.isEmpty { await a.syncShortcuts(); try await Task.sleep(for: .milliseconds(10)) }
    await b.syncShortcuts()
    #expect(b.selectedShortcutID == nil)
    #expect(b.draft == "Typed while profile sync runs")
    let cold = try await make("b", token: f["second_token"]!); cold.loadShortcuts()
    #expect(!cold.shortcuts.contains { $0.id == id })
    #expect(cold.shortcuts.contains { $0.title == "Conflicting local title" })
}
