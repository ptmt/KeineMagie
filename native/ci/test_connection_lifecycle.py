"""Execute real AppModel with synthetic API transport, never Keychain/provider."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@MainActor final class Gate {
    var completeEntered = false
    var release: CheckedContinuation<Void, Never>?
    var callbackTask: Task<Void, Never>?
    var failCatalog = false
    var failHistory = false
    var failComplete = false
    var statusCalls = 0
    var holdStatus = false
    var statusRelease: CheckedContinuation<Void, Never>?
    var degradedCatalog = false
    var holdSession = false
    var translationError: URLError?
    var translationStatus = 200
    var holdTranslation = false
    var translationRelease: CheckedContinuation<Void, Never>?
    let outboxRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var sessionRelease: CheckedContinuation<Void, Never>?
    var owner = "synthetic"
    var translationRequests: [URLRequest] = []
    func send(_ r: URLRequest) async throws -> AuthResponse {
        var body = "{}"
        if r.url!.path == "/v1/auth/session", holdSession { await withCheckedContinuation { sessionRelease = $0 } }
        switch r.url!.path {
        case "/v1/auth/session": body = "{\"user\":{\"id\":\"\(owner)\"},\"expires_at\":\"2099-01-01T00:00:00Z\"}"
        case "/v1/provider/connect": body = #"{"bootstrap_token":"synthetic","expires_in":300,"message":"test"}"#
        case "/v1/provider/bootstrap/start":
            let d = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String:String]
            let redirect = d["redirect_uri"]!
            let authorize = "https://auth.openai.com/api/accounts/authorize?client_id=dynamic_agent_client&response_type=code&redirect_uri=\(redirect.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)&state=synthetic-state&nonce=synthetic&code_challenge=synthetic&code_challenge_method=S256"
            body = String(data: try JSONSerialization.data(withJSONObject:["authorize_url":authorize]),encoding:.utf8)!
            callbackTask = Task {
                try? await Task.sleep(for:.milliseconds(100))
                _ = try? await URLSession.shared.data(from: URL(string:redirect+"?state=synthetic-state&code=synthetic&client_id=oaiapp_synthetic")!)
            }
        case "/v1/provider/bootstrap/complete":
            completeEntered = true
            await withCheckedContinuation { release = $0 }
            return AuthResponse(data:Data("{}".utf8), status:failComplete ? 502 : 204)
        case "/v1/provider":
            statusCalls += 1
            if holdStatus { await withCheckedContinuation { statusRelease = $0 } }
            if failCatalog { return AuthResponse(data:Data("{}".utf8),status:502) }
            if degradedCatalog { return AuthResponse(data:Data(#"{"connected":true,"status":"catalog_unavailable","message":"Catalog unavailable; check again.","models":[],"selected_model":""}"#.utf8),status:200) }
            body = #"{"connected":true,"status":"connected","message":"synthetic","models":[{"slug":"synthetic","display_name":"Synthetic"}],"selected_model":"synthetic"}"#
        case "/v1/translations":
            if r.httpMethod == "POST" {
                translationRequests.append(r)
                if holdTranslation { await withCheckedContinuation { translationRelease = $0 } }
                if let translationError { throw translationError }
                if translationStatus != 200 { return AuthResponse(data: Data("{}".utf8), status: translationStatus) }
                body = #"{"id":"translated","created_at":"2026-11-09T12:00:00Z","text":"Hallo","source_language":"de","target_language":"ru","translation":"Привет","idioms":[],"patterns":[],"vocabulary":[]}"#
                break
            }
            if failHistory { return AuthResponse(data:Data("{}".utf8),status:503) }
            body = #"{"items":[]}"#
        default: throw APIError.invalidResponse
        }
        return AuthResponse(data:Data(body.utf8),status:200)
    }
    func finish() { release?.resume(); release = nil }
}
@MainActor func fixture(_ gate: Gate) async -> AppModel {
    let transport: AuthClient.Transport = { request in try await gate.send(request) }
    let session = SessionController(serverURL:"https://synthetic.invalid",readToken:{"synthetic"},saveToken:{_ in},transport:transport)
    await session.restore()
    return AppModel(session:session, client:APIClient(endpoint:try! ServerEndpoint("https://synthetic.invalid"),token:"synthetic",transport:transport), outboxStore: TranslationOutboxStore(root: gate.outboxRoot))
}
@Test @MainActor func translatorDoesNotWaitForSessionCheckOrStaleOffline() async throws {
    let gate = Gate(); gate.owner = "outbox-repro-\(UUID())"
    let model = await fixture(gate)
    model.draft = "  Привет 👩🏽‍💻 e\u{301}\n"
    gate.holdSession = true
    let checking = Task { await model.session.restore() }
    while gate.sessionRelease == nil { await Task.yield() }
    await model.translate()
    #expect(gate.translationRequests.count == 1, "Delayed advisory session check must not gate an authenticated translation")
    gate.sessionRelease?.resume(); gate.sessionRelease = nil
    await checking.value
    model.session.recordNetworkFailure(URLError(.notConnectedToInternet))
    model.draft = "Second"
    await model.translate()
    #expect(gate.translationRequests.count == 2, "Stale offline state must not gate a real request")
}
@Test @MainActor func translatorPersistsTypingAndSubmissionBeforeRequest() async throws {
    let gate = Gate(); gate.owner = "outbox-durable-\(UUID())"
    let model = await fixture(gate)
    model.loadTranslationOutbox()
    model.draft = "  Привет 👩🏽‍💻 e\u{301}\n"
    model.direction = .germanToRussian
    let next = await fixture(gate)
    next.loadTranslationOutbox()
    #expect(next.draft == model.draft)
    #expect(next.direction == .germanToRussian)
    await model.translate()
    #expect(model.outbox.items.count == 1)
    #expect(model.outbox.items.first?.state == .completed)
    #expect(model.draft == "  Привет 👩🏽‍💻 e\u{301}\n")
    let request = try #require(gate.translationRequests.first)
    #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == model.outbox.items.first?.id.uuidString)
    #expect(request.value(forHTTPHeaderField: "X-Translation-Owner") == gate.owner)
    model.resetSessionContent()
}
@Test @MainActor func outboxDoubleTapTypingCancelAndLateCompletion() async throws {
    let gate = Gate(); gate.holdTranslation = true
    let model = await fixture(gate); model.draft = "first"
    let first = Task { await model.translate() }
    while gate.translationRelease == nil { await Task.yield() }
    let duplicate = Task { await model.translate() }
    await Task.yield()
    #expect(gate.translationRequests.count == 1)
    #expect(model.outbox.items.count == 1)
    model.draft = "typing continues"
    let id = try #require(model.outbox.items.first?.id)
    model.removeTranslation(id)
    gate.translationRelease?.resume(); gate.translationRelease = nil
    await first.value; await duplicate.value
    #expect(model.draft == "typing continues")
    #expect(model.result == nil)
    #expect(model.outbox.items.first?.state == .cancelled)
}
@Test @MainActor func outboxOfflineRestoreRetryAndAmbiguousResponse() async throws {
    let gate = Gate(); gate.translationError = URLError(.notConnectedToInternet)
    let model = await fixture(gate); model.draft = "queued exact"
    await model.translate()
    let id = try #require(model.outbox.items.first?.id)
    #expect(model.outbox.items.first?.state == .queued)
    let next = await fixture(gate); next.loadTranslationOutbox()
    #expect(next.outbox.items.first?.id == id)
    gate.translationError = nil
    await next.retryTranslation(id)
    #expect(next.outbox.items.first?.state == .completed)
    #expect(gate.translationRequests.count == 2)
    #expect(try JSONSerialization.jsonObject(with: gate.translationRequests[0].httpBody!) as? [String: String] == JSONSerialization.jsonObject(with: gate.translationRequests[1].httpBody!) as? [String: String])
    #expect(gate.translationRequests[0].value(forHTTPHeaderField: "Idempotency-Key") == gate.translationRequests[1].value(forHTTPHeaderField: "Idempotency-Key"))
    next.draft = "timeout"; gate.translationError = URLError(.timedOut)
    await next.translate()
    #expect(next.outbox.items.last?.state == .needsDecision)
    await next.resumeTranslations()
    #expect(gate.translationRequests.count == 3)
}
@Test @MainActor func outboxStorageFailureNeverSends() async throws {
    let gate = Gate(); let model = await fixture(gate)
    model.loadTranslationOutbox(); model.draft = "safe"
    try FileManager.default.removeItem(at: gate.outboxRoot)
    try Data("blocked".utf8).write(to: gate.outboxRoot)
    await model.translate()
    #expect(model.outboxStorageError)
    #expect(gate.translationRequests.isEmpty)
    #expect(model.draft == "safe")
}
@Test @MainActor func outbox401RevokesIdentityAndLateOwnerCannotMutate() async throws {
    let gate = Gate(); gate.translationStatus = 401
    let model = await fixture(gate); model.draft = "private"
    await model.translate()
    #expect(model.session.user == nil)
    #expect(model.outbox.items.isEmpty)
    #expect(model.draft.isEmpty)
    await model.logout()
    #expect(try TranslationOutboxStore(root: gate.outboxRoot).load(origin: "https://synthetic.invalid", owner: gate.owner).items.isEmpty)
    gate.translationStatus = 200; gate.holdTranslation = true
    gate.owner = "alice"; await model.session.restore(); model.loadTranslationOutbox()
    model.draft = "old owner"
    let task = Task { await model.translate() }
    while gate.translationRelease == nil { await Task.yield() }
    gate.owner = "bob"; await model.session.restore(); model.resetSessionContent(); model.loadTranslationOutbox()
    model.draft = "bob draft"
    gate.translationRelease?.resume(); gate.translationRelease = nil
    await task.value
    #expect(model.draft == "bob draft")
    #expect(model.result == nil)
    #expect(model.outbox.items.isEmpty)
}
@Test @MainActor func outboxOrdersQueuedSnapshotsAndNeverSendsTyping() async throws {
    let gate = Gate(); gate.holdTranslation = true
    let model = await fixture(gate); model.draft = "one"
    #expect(gate.translationRequests.isEmpty)
    let first = Task { await model.translate() }
    while gate.translationRelease == nil { await Task.yield() }
    model.draft = "two"; await model.translate()
    model.draft = "not submitted"
    #expect(model.outbox.items.map(\.text) == ["one", "two"])
    #expect(gate.translationRequests.count == 1)
    gate.holdTranslation = false
    gate.translationRelease?.resume(); gate.translationRelease = nil
    await first.value
    #expect(gate.translationRequests.count == 2)
    #expect(model.outbox.items.allSatisfy { $0.state == .completed })
    #expect(model.draft == "not submitted")
}
@Test @MainActor func advisoryFailureDoesNotBlockAutomaticSameOwnerRetry() async throws {
    let gate = Gate(); let model = await fixture(gate)
    model.translationForeground = false
    model.draft = "queued by tap"; await model.translate()
    #expect(gate.translationRequests.isEmpty)
    model.session.recordNetworkFailure(URLError(.timedOut))
    #expect(!model.session.canWrite)
    model.translationForeground = true
    await model.resumeTranslations()
    #expect(gate.translationRequests.count == 1)
    #expect(model.outbox.items.first?.state == .completed)
}
@Test @MainActor func programmaticBrowserDismissalDoesNotCancelCompletion() async throws {
    let gate = Gate(); let model = await fixture(gate)
    let connect = Task { await model.connectChatGPT() }
    for _ in 0..<1000 { if gate.completeEntered {break}; try await Task.sleep(for:.milliseconds(2)) }
    #expect(gate.completeEntered)
    #expect(model.chatGPTBrowser == nil)
    model.browserDismissed()
    #expect(model.busy)
    gate.finish(); await connect.value
    #expect(model.provider?.connected == true)
    #expect(model.provider?.selectedModel == "synthetic")
    #expect(model.translatorError == nil)
    #expect(!model.busy)
}
@Test @MainActor func completionFailureRemainsVisibleAfterDismissal() async throws {
    let gate = Gate(); gate.failComplete = true
    let model = await fixture(gate)
    let connect = Task { await model.connectChatGPT() }
    for _ in 0..<1000 { if gate.completeEntered {break}; try await Task.sleep(for:.milliseconds(2)) }
    model.browserDismissed(); gate.finish(); await connect.value
    #expect(model.translatorError == APIError.http(502).localizedDescription)
    #expect(model.provider == nil)
    #expect(!model.busy)
}
@Test @MainActor func explicitCancellationDuringCompletionSuppressesLateState() async throws {
    let gate = Gate(); let model = await fixture(gate)
    let connect = Task { await model.connectChatGPT() }
    for _ in 0..<1000 { if gate.completeEntered {break}; try await Task.sleep(for:.milliseconds(2)) }
    model.cancelChatGPT(); gate.finish(); await connect.value
    #expect(model.provider == nil)
    #expect(model.translatorError == nil)
    #expect(!model.busy)
}
@Test @MainActor func userCloseWhileBrowsingCancelsWithoutCompleting() async throws {
    let gate = Gate(); let model = await fixture(gate)
    let connect = Task { await model.connectChatGPT() }
    for _ in 0..<1000 { if model.chatGPTBrowser != nil {break}; try await Task.sleep(for:.milliseconds(1)) }
    #expect(model.chatGPTBrowser != nil)
    model.browserDismissed(); await connect.value
    gate.callbackTask?.cancel()
    #expect(!gate.completeEntered)
    #expect(model.provider == nil)
    #expect(!model.busy)
}
@Test @MainActor func refreshKeepsConnectionWhenHistoryFails() async {
    let gate = Gate(); gate.failHistory = true
    let model = await fixture(gate)
    await model.refreshTranslator()
    #expect(gate.statusCalls == 1)
    #expect(model.provider?.connected == true)
    #expect(model.translatorError == APIError.http(503).localizedDescription)
    #expect(!model.refreshing)
}
@Test @MainActor func checkConnectionShowsBusyAndSafeHTTPFailure() async {
    let gate = Gate(); gate.holdStatus = true; gate.failCatalog = true
    let model = await fixture(gate)
    let check = Task { await model.refreshTranslator() }
    while gate.statusRelease == nil { await Task.yield() }
    #expect(model.refreshing)
    gate.statusRelease?.resume(); gate.statusRelease = nil
    await check.value
    #expect(!model.refreshing)
    #expect(model.translatorError == APIError.http(502).localizedDescription)
}
@Test @MainActor func unavailableCatalogKeepsConnectionButNoModel() async {
    let gate = Gate(); gate.degradedCatalog = true
    let model = await fixture(gate)
    await model.refreshTranslator()
    #expect(model.provider?.connected == true)
    #expect(model.provider?.selectedModel == "")
    #expect(model.translatorError == "Catalog unavailable; check again.")
}
@Test @MainActor func customStyleReachesActualAppModelRequestAndNeverCrossesAccounts() async throws {
    let gate = Gate(); gate.owner = "style-owner-\(UUID())"
    let ownerA = gate.owner
    let model = await fixture(gate)
    let id = UUID()
    let instructions = String(repeating: "e\u{301}", count: 500)
    try model.saveShortcut(id: id, title: "Private style", instruction: instructions)
    model.selectedShortcutID = id.uuidString
    model.draft = "Hallo"
    await model.translate()
    #expect(model.result?.id == "translated")
    #expect(model.history.count == 1)
    #expect(model.selectedShortcutID == nil)
    let request = try #require(gate.translationRequests.first)
    let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])
    #expect(body["instructions"] == instructions)
    #expect(body["text"] == "Hallo")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
    model.selectedShortcutID = "friendly"
    gate.owner = "style-other-owner-\(UUID())"
    await model.session.restore()
    // Mirror RootView's generation observer; UI tests exercise that observer itself.
    model.resetSessionContent(); model.loadShortcuts()
    #expect(model.shortcuts.isEmpty)
    #expect(model.selectedShortcutID == nil)
    #expect(model.translationInstruction == nil)
    #expect(model.history.isEmpty)
    #expect(model.result == nil)
    #expect(model.draft.isEmpty)
    gate.owner = ownerA
    await model.session.restore()
    model.resetSessionContent(); model.loadShortcuts()
    #expect(model.shortcuts.map(\.id) == [id])
    #expect(model.selectedShortcutID == nil)
    try model.deleteShortcut(id)
}
'''

def main():
    scratch = Path.home()/'.hermes/cache/scratch'
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='km-lifecycle-', dir=scratch) as temp:
        p = Path(temp)
        (p/'Sources/Lifecycle').mkdir(parents=True)
        (p/'Tests/LifecycleTests').mkdir(parents=True)
        (p/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name:"Lifecycle",platforms:[.macOS(.v14)],dependencies:[.package(path:"%s")],targets:[.target(name:"Lifecycle",dependencies:[.product(name:"KeineMagieCore",package:"Core")]),.testTarget(name:"LifecycleTests",dependencies:["Lifecycle"])])
''' % (ROOT/'Core'))
        app = (ROOT/'App/AppModel.swift').read_text().replace('import SwiftUI','import Foundation\nimport Observation')
        (p/'Sources/Lifecycle/AppModel.swift').write_text(app)
        (p/'Sources/Lifecycle/PodcastStore.swift').write_text((ROOT/'App/PodcastStore.swift').read_text())
        (p/'Sources/Lifecycle/Stubs.swift').write_text('''import Foundation
import KeineMagieCore
struct ChatGPTBrowser: Identifiable { let id = UUID(); let url: URL }
enum TokenStore { static func readIdentity() throws -> SavedNativeIdentity? { fatalError("Keychain forbidden") }; static func saveIdentity(_ identity: SavedNativeIdentity?) throws { fatalError("Keychain forbidden") }; static func read() throws -> String { fatalError("Keychain forbidden") }; static func save(_ s:String) throws { fatalError("Keychain forbidden") } }
enum ProductIdentity { static let defaultServerURL = "https://synthetic.invalid" }
enum AppL10n { static func text(_ key:String) -> String { key } }
''')
        (p/'Tests/LifecycleTests/LifecycleTests.swift').write_text(HARNESS)
        (p/'Tests/LifecycleTests/DatasetTests.swift').write_text((ROOT/'ci/dataset_harness.swift').read_text())
        (p/'Tests/LifecycleTests/LearningTests.swift').write_text((ROOT/'ci/learning_harness.swift').read_text())
        (p/'Tests/LifecycleTests/CoachTests.swift').write_text((ROOT/'ci/coach_harness.swift').read_text())
        subprocess.run(['swift','test','--package-path',temp],check=True)

class ConnectionLifecycleTests(unittest.TestCase):
    def test_real_app_model_with_synthetic_transport(self):
        main()

if __name__ == '__main__': unittest.main()
