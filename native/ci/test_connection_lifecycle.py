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
    var owner = "synthetic"
    var translationRequests: [URLRequest] = []
    func send(_ r: URLRequest) async throws -> AuthResponse {
        var body = "{}"
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
    return AppModel(session:session, client:APIClient(endpoint:try! ServerEndpoint("https://synthetic.invalid"),token:"synthetic",transport:transport))
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
