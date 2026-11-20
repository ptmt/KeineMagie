"""Execute real AppModel with synthetic API transport, never Keychain/provider."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
import Foundation
import Testing
import CryptoKit
import Observation
import KeineMagieCore
@testable import Lifecycle

@MainActor final class Gate {
    var completeEntered = false
    var release: CheckedContinuation<Void, Never>?
    var callbackTask: Task<Void, Never>?
    var failCatalog = false
    var catalogError: URLError?
    var providerHTTP = 200
    var disconnected = false
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
    var recoveredHistory = "{\"items\":[]}"
    var historyCalls = 0
    var holdHistory = false
    var historyRelease: CheckedContinuation<Void, Never>?
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
            if let catalogError { throw catalogError }
            if providerHTTP != 200 { return AuthResponse(data: Data(), status: providerHTTP) }
            if disconnected { return AuthResponse(data: Data(#"{"connected":false,"status":"not_connected","message":"Connect ChatGPT"}"#.utf8), status: 200) }
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
            historyCalls += 1
            let response = recoveredHistory
            if holdHistory { await withCheckedContinuation { historyRelease = $0 } }
            if failHistory { return AuthResponse(data:Data("{}".utf8),status:503) }
            body = response
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
    return AppModel(session:session, client:APIClient(endpoint:try! ServerEndpoint("https://synthetic.invalid"),token:"synthetic",transport:transport), cache: ContentCache(root: gate.outboxRoot.appendingPathComponent("cache")), outboxStore: TranslationOutboxStore(root: gate.outboxRoot), profileStore: TranslationProfileStore(root: gate.outboxRoot.appendingPathComponent("profiles")))
}
final class PendingObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    func record() { lock.withLock { changed = true } }
    var didChange: Bool { lock.withLock { changed } }
}
@Test @MainActor func idleResumeNeverPublishesFalsePending() async throws {
    let gate = Gate(); let model = await fixture(gate)
    model.loadTranslationOutbox()
    let observation = PendingObservation()
    withObservationTracking { _ = model.translationPending } onChange: { observation.record() }
    await model.resumeTranslations()
    #expect(!observation.didChange, "Empty queue must not publish pending even for a single task hop")
    #expect(gate.translationRequests.isEmpty)
    model.draft = "Hallo"; await model.translate()
    let saved = model.displayedTranslation
    let completed = PendingObservation()
    withObservationTracking { _ = model.translationPending } onChange: { completed.record() }
    await model.resumeTranslations()
    #expect(!completed.didChange, "Completed receipts must not flash the retained result on foreground")
    #expect(model.displayedTranslation == saved)
    #expect(gate.translationRequests.count == 1)
}
@Test @MainActor func backoffResumeNeverPublishesPendingOrPosts() async throws {
    let gate = Gate(); let model = await fixture(gate)
    gate.translationError = URLError(.notConnectedToInternet)
    model.draft = "offline receipt"; await model.translate()
    #expect(model.outbox.items.first?.state == .queued)
    #expect(try #require(model.outbox.items.first?.nextAttempt) > Date())
    let observation = PendingObservation()
    withObservationTracking { _ = model.translationPending } onChange: { observation.record() }
    await model.resumeTranslations()
    #expect(!observation.didChange)
    #expect(!model.translationPending)
    #expect(gate.translationRequests.count == 1)
}
@Test @MainActor func dueResumePublishesPendingAndRetainsExactReceipt() async throws {
    let gate = Gate(); let model = await fixture(gate)
    model.translationForeground = false
    model.draft = "  due e\u{301} 👩🏽‍💻\n"
    await model.translate()
    let receipt = try #require(model.outbox.items.first)
    #expect(!model.translationPending)
    #expect(gate.translationRequests.isEmpty)
    model.translationForeground = true; gate.holdTranslation = true
    let resumed = Task { await model.resumeTranslations() }
    while gate.translationRelease == nil { await Task.yield() }
    #expect(model.translationPending)
    #expect(model.outbox.items.first?.id == receipt.id)
    let persisted = try TranslationOutboxStore(root: gate.outboxRoot).load(origin: "https://synthetic.invalid", owner: gate.owner)
    // A freshly loaded journal treats interrupted sends as uncertain, never replayable.
    #expect(persisted.items.first?.state == .needsDecision)
    #expect(persisted.items.first?.attempts == 1)
    #expect(persisted.items.first?.text == receipt.text)
    gate.translationRelease?.resume(); await resumed.value
    #expect(!model.translationPending)
    #expect(model.outbox.items.first?.state == .completed)
    #expect(gate.translationRequests.count == 1)
}
@Test @MainActor func clearInputKeepsResultAndAcceptedReceiptWithoutOverwritingNewDraft() async throws {
    let gate = Gate(); let model = await fixture(gate)
    model.draft = "Hallo"; await model.translate()
    let prior = try #require(model.result)
    model.draft = ""
    #expect(model.displayedTranslation == prior.translation)
    model.openTranslationDiscussion(prior)
    #expect(model.discussionSource == prior.text)
    #expect(model.draft.isEmpty)
    model.closeTranslationDiscussion()
    model.draft = "accepted next"; gate.holdTranslation = true
    let task = try #require(model.beginTranslation())
    while gate.translationRelease == nil { await Task.yield() }
    model.draft = ""
    #expect(model.displayedTranslation == prior.translation)
    #expect(model.translationPending)
    model.draft = "new unsubmitted draft"
    gate.translationRelease?.resume(); await task.value
    #expect(model.draft == "new unsubmitted draft")
    #expect(model.outbox.items.last?.text == "accepted next")
    #expect(model.outbox.items.last?.state == .completed)
    let body = try #require(JSONSerialization.jsonObject(with: gate.translationRequests.last!.httpBody!) as? [String: String])
    #expect(body["text"] == "accepted next")
}
@Test @MainActor func translationJournalRunsOffMain() async throws {
    let gate = Gate()
    let disk = JournalProbe()
    let transport: AuthClient.Transport = { request in try await gate.send(request) }
    let session = SessionController(serverURL:"https://synthetic.invalid",readToken:{"synthetic"},saveToken:{_ in},transport:transport)
    await session.restore()
    let store = TranslationOutboxStore(root: gate.outboxRoot, beforeSave: { _ in disk.record() })
    let model = AppModel(session:session, client:APIClient(endpoint:try ServerEndpoint("https://synthetic.invalid"),token:"synthetic",transport:transport), outboxStore:store)
    model.draft = "private"
    await model.translate()
    #expect(!disk.sawMainThread, "JSON encoding and filesystem writes must not run on MainActor")
    #expect(gate.translationRequests.count == 1)
}
@Test @MainActor func delayedJournalKeepsInputResponsiveAndLogoutCannotResurrectIt() async throws {
    let gate = Gate(); let disk = SuspendedJournal()
    let transport: AuthClient.Transport = { request in try await gate.send(request) }
    let session = SessionController(serverURL:"https://synthetic.invalid",readToken:{"synthetic"},saveToken:{_ in},transport:transport)
    await session.restore()
    let store = TranslationOutboxStore(root:gate.outboxRoot, beforeSave: { value in
        if !value.items.isEmpty { disk.pause() }
    })
    let model = AppModel(session:session, client:APIClient(endpoint:try ServerEndpoint("https://synthetic.invalid"),token:"synthetic",transport:transport), outboxStore:store)
    model.draft = "accepted snapshot"
    #expect(await model.flushTranslationPersistence())
    let accepted = try #require(model.beginTranslation())
    while !disk.entered { await Task.yield() }
    await model.resumeTranslations()
    #expect(gate.translationRequests.isEmpty, "Automatic drain must not bypass an acceptance awaiting disk")
    #expect(model.translationPending)
    #expect(gate.translationRequests.isEmpty, "Persist before POST")
    model.draft = "responsive new input"
    #expect(model.draft == "responsive new input")
    await model.logout()
    #expect(!model.translationPending)
    disk.release()
    await accepted.value
    #expect(gate.translationRequests.isEmpty)
    #expect(model.result == nil)
    #expect(try store.load(origin:"https://synthetic.invalid",owner:gate.owner).items.isEmpty)
}
final class SuspendedJournal: @unchecked Sendable {
    private let condition = NSCondition()
    private var started = false
    private var finished = false
    var entered: Bool { condition.withLock { started } }
    func pause() { condition.lock(); started = true; while !finished { condition.wait() }; condition.unlock() }
    func release() { condition.lock(); finished = true; condition.broadcast(); condition.unlock() }
}
final class JournalProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var mainThread = false
    var sawMainThread: Bool { lock.withLock { mainThread } }
    func record() { lock.withLock { mainThread = mainThread || Thread.isMainThread } }
}
@Test @MainActor func explicitTranslationFeedbackStartsSynchronouslyAndStopsWhenQueued() async throws {
    let gate = Gate(); gate.holdTranslation = true
    let model = await fixture(gate); model.draft = "first"
    let accepted = try #require(model.beginTranslation())
    #expect(model.translationPending, "Tap must publish before persistence or transport")
    #expect(gate.translationRequests.isEmpty)
    #expect(model.beginTranslation() == nil, "Duplicate accepted tap coalesces synchronously")
    while gate.translationRelease == nil { await Task.yield() }
    #expect(model.translationPending)
    gate.translationError = URLError(.notConnectedToInternet)
    gate.translationRelease?.resume(); gate.translationRelease = nil
    await accepted.value
    #expect(!model.translationPending, "Saved waiting must not animate as active work")
    #expect(model.outbox.items.first?.state == .queued)
    #expect(gate.translationRequests.count == 1)
}
@Test @MainActor func explicitFeedbackKeepsOldResultAndResetFencesLateCompletion() async throws {
    let gate = Gate(); let model = await fixture(gate); model.draft = "first"
    await model.translate(); let previous = model.result
    gate.holdTranslation = true; model.draft = "second"
    let accepted = try #require(model.beginTranslation())
    #expect(model.result?.translation == previous?.translation)
    while gate.translationRelease == nil { await Task.yield() }
    model.resetSessionContent()
    #expect(!model.translationPending)
    gate.translationRelease?.resume(); gate.translationRelease = nil
    await accepted.value
    #expect(!model.translationPending)
    #expect(model.result == nil)
}
@Test @MainActor func feedbackStorageFailureAndChangedOwnerNeverSend() async throws {
    let gate = Gate(); let model = await fixture(gate); model.draft = "disk failure"
    // Replace this synthetic journal directory with a file to force a real write failure.
    #expect(await model.flushTranslationPersistence())
    try FileManager.default.removeItem(at: gate.outboxRoot)
    try Data().write(to: gate.outboxRoot)
    let accepted = try #require(model.beginTranslation())
    #expect(model.translationPending)
    await accepted.value
    #expect(!model.translationPending)
    #expect(model.outboxStorageError)
    #expect(gate.translationRequests.isEmpty)
}
@Test @MainActor func feedbackAllowsNewSnapshotWhileExistingRequestIsPending() async throws {
    let gate = Gate(); gate.holdTranslation = true
    let model = await fixture(gate); model.draft = "first"
    let accepted = try #require(model.beginTranslation())
    while gate.translationRelease == nil { await Task.yield() }
    model.draft = "different draft"
    #expect(!model.translationSubmitPending)
    let second = try #require(model.beginTranslation())
    await second.value
    #expect(model.outbox.items.count == 2)
    #expect(gate.translationRequests.count == 1)
    gate.translationError = URLError(.notConnectedToInternet)
    gate.translationRelease?.resume(); gate.translationRelease = nil
    await accepted.value
    #expect(!model.translationPending)
    #expect(model.draft == "different draft")
}
@Test @MainActor func headerDirectionEditsRetainResultAndNeverMutateAcceptedSnapshot() async throws {
    let gate = Gate()
    let model = await fixture(gate)
    model.draft = "first"; model.direction = .germanToRussian
    await model.translate()
    let prior = try #require(model.result)
    gate.holdTranslation = true
    model.draft = "second"; model.direction = .russianToGerman
    let accepted = try #require(model.beginTranslation())
    while gate.translationRelease == nil { await Task.yield() }
    model.direction = .germanPolishing
    #expect(model.draft == "second")
    #expect(model.result?.id == prior.id)
    #expect(model.result?.translation == prior.translation)
    #expect(model.translationPending)
    #expect(!model.translationSubmitPending, "A changed next-draft direction is editable during an immutable send")
    #expect(model.outbox.items.last?.direction == .russianToGerman)
    #expect(gate.translationRequests.count == 2, "Changing direction does not automatically translate")
    let body = try #require(gate.translationRequests.last?.httpBody)
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String:Any])
    #expect(payload["source_language"] as? String == "ru")
    #expect(payload["target_language"] as? String == "de")
    gate.translationRelease?.resume(); gate.translationRelease = nil
    await accepted.value
    #expect(model.direction == .germanPolishing)
    #expect(gate.translationRequests.count == 2)
    #expect(await model.flushTranslationPersistence())
    let relaunched = await fixture(gate); relaunched.loadTranslationOutbox()
    #expect(relaunched.direction == .germanPolishing)
    #expect(relaunched.draft == "second")
}

@Test @MainActor func historyFailureStaysInHistoryAndProviderSettlesIndependently() async throws {
    let gate = Gate(); gate.holdHistory = true; gate.failHistory = true
    let model = await fixture(gate)
    let task = Task { await model.refreshTranslator() }
    while gate.historyRelease == nil { await Task.yield() }
    for _ in 0..<100 { await Task.yield() }
    #expect(model.provider?.connected == true, "Provider readiness must not await history")
    gate.historyRelease?.resume(); gate.historyRelease = nil
    await task.value
    #expect(model.historyLoadError != nil)
    #expect(model.translatorError == nil, "A history read is not a failed translation")
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
@Test @MainActor func outboxDoubleTapTypingAndLateCompletionPreserveDraft() async throws {
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
    #expect(model.result?.id == "translated")
    #expect(model.outbox.items.first?.state == .completed)
}
@Test @MainActor func inFlightRequestCannotBeHiddenAndResubmitted() async throws {
    let gate = Gate(); gate.holdTranslation = true
    let model = await fixture(gate); model.draft = "one paid request"
    let task = Task { await model.translate() }
    while gate.translationRelease == nil { await Task.yield() }
    let id = try #require(model.outbox.items.first?.id)
    model.removeTranslation(id)
    model.removeTranslation(id, delete: true)
    await model.translate()
    #expect(model.outbox.items.map(\.id) == [id])
    #expect(model.outbox.items.first?.state == .sending)
    gate.holdTranslation = false
    gate.translationRelease?.resume(); gate.translationRelease = nil; await task.value
    #expect(gate.translationRequests.count == 1)
    #expect(model.outbox.items.first?.state == .completed)
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
@Test @MainActor func uncertainRecoveryOnlyReadsHistoryAndKeepsOriginalIdentity() async throws {
    let gate = Gate(); gate.translationError = URLError(.timedOut)
    let model = await fixture(gate); model.draft = "same text"
    await model.translate()
    let id = try #require(model.outbox.items.first?.id)
    gate.translationError = nil
    await model.retryTranslation(id)
    #expect(gate.translationRequests.count == 1, "Checking an unknown outcome must never POST")
    #expect(gate.historyCalls == 1)
    #expect(model.outbox.items.first?.id == id)
    #expect(model.outbox.items.first?.state == .needsDecision)
    #expect(model.draft == "same text")
}
@Test @MainActor func recoveryMatchesIdentityNotTextAndRetainsCompletedReceipts() async throws {
    let gate = Gate(); gate.translationError = URLError(.timedOut)
    let model = await fixture(gate); model.draft = "same text"; await model.translate()
    let original = try #require(model.outbox.items.first?.id)
    model.removeTranslation(original)
    await model.translate()
    let other = try #require(model.outbox.items.last?.id)
    #expect(original != other)
    // Preserve two same-text requests in storage. The recovery must select by ID.
    let recordID = "outbox-" + SHA256.hash(data: Data((gate.owner + "\u{0}" + other.uuidString).utf8)).map { String(format: "%02x", $0) }.joined()
    gate.recoveredHistory = "{\"items\":[{\"id\":\"\(recordID)\",\"created_at\":\"2026-11-09T12:00:00Z\",\"text\":\"same text\",\"source_language\":\"ru\",\"target_language\":\"de\",\"translation\":\"Recovered answer\",\"idioms\":[],\"patterns\":[],\"vocabulary\":[]}]}"
    model.draft = "still editing"
    await model.checkTranslation(other)
    #expect(gate.translationRequests.count == 2)
    #expect(model.outbox.items.map(\.id) == [original, other])
    #expect(model.outbox.items.map(\.state) == [.cancelled, .completed])
    #expect(model.history.map(\.id) == [recordID])
    #expect(model.result?.id == recordID)
    #expect(model.draft == "still editing")
    let restored = await fixture(gate); restored.loadTranslationOutbox()
    #expect(restored.outbox.items.map(\.id) == [original, other])
    #expect(restored.outbox.items.last?.result?.id == recordID)
}
@Test @MainActor func recoveryReadCoalescesAndOwnerResetFencesLateAnswer() async throws {
    let gate = Gate(); gate.translationError = URLError(.timedOut)
    let model = await fixture(gate); model.draft = "private"; await model.translate()
    let id = try #require(model.outbox.items.first?.id)
    await model.checkTranslation(id)
    #expect(model.translationCheckNotices[id] != nil)
    gate.recoveredHistory = recoveredJSON(id, owner: gate.owner)
    gate.holdHistory = true
    let task = Task { await model.checkTranslation(id) }
    while gate.historyRelease == nil { await Task.yield() }
    await model.checkTranslation(id)
    #expect(gate.historyCalls == 2)
    gate.owner = "replacement"; await model.session.restore()
    model.resetSessionContent(); model.loadTranslationOutbox(); model.draft = "new owner"
    #expect(model.checkingTranslations.isEmpty)
    #expect(model.translationCheckNotices.isEmpty)
    gate.historyRelease?.resume(); gate.historyRelease = nil; await task.value
    #expect(model.outbox.items.isEmpty)
    #expect(model.result == nil)
    #expect(model.draft == "new owner")
}
@MainActor func recoveredJSON(_ id: UUID, owner: String, text: String = "same text") -> String {
    let key = "outbox-" + SHA256.hash(data: Data((owner + "\u{0}" + id.uuidString).utf8)).map { String(format: "%02x", $0) }.joined()
    return "{\"items\":[{\"id\":\"\(key)\",\"created_at\":\"2026-11-09T12:00:00Z\",\"text\":\"\(text)\",\"source_language\":\"ru\",\"target_language\":\"de\",\"translation\":\"Recovered answer\",\"idioms\":[],\"patterns\":[],\"vocabulary\":[]}]}"
}
@Test @MainActor func recoveryRejectsSameTextWrongReceiptAndOwnerThenPersistsExactMatch() async throws {
    let gate = Gate(); gate.translationError = URLError(.timedOut)
    let model = await fixture(gate); model.draft = "same text"; await model.translate()
    let id = try #require(model.outbox.items.first?.id)
    for response in [recoveredJSON(UUID(), owner: gate.owner), recoveredJSON(id, owner: "other-owner")] {
        gate.recoveredHistory = response
        await model.checkTranslation(id)
        #expect(model.outbox.items.first?.state == .needsDecision)
        #expect(model.result == nil)
        #expect(model.history.isEmpty)
    }
    gate.recoveredHistory = recoveredJSON(id, owner: gate.owner)
    await model.checkTranslation(id)
    #expect(gate.translationRequests.count == 1)
    #expect(gate.historyCalls == 3)
    #expect(model.outbox.items.first?.id == id)
    #expect(model.outbox.items.first?.state == .completed)
    let cache = ContentCache(root: gate.outboxRoot.appendingPathComponent("cache"))
    let data = try #require(try await cache.load(dataset: "history", server: model.session.serverURL, owner: gate.owner))
    let rows = try JSONDecoder().decode([TranslationRecord].self, from: data)
    #expect(rows.map(\.id) == model.history.map(\.id))
    #expect(rows.count == 1)
}
@Test @MainActor func recoveredAnswerSurvivesAnOlderEmptyRefreshAndCacheWrite() async throws {
    let gate = Gate(); gate.translationError = URLError(.timedOut)
    let model = await fixture(gate); model.draft = "same text"; await model.translate()
    let id = try #require(model.outbox.items.first?.id)
    gate.holdHistory = true
    let refresh = Task { await model.refreshTranslator() }
    while gate.historyRelease == nil { await Task.yield() }
    gate.holdHistory = false; gate.recoveredHistory = recoveredJSON(id, owner: gate.owner)
    await model.checkTranslation(id)
    let recovered = try #require(model.result?.id)
    gate.historyRelease?.resume(); gate.historyRelease = nil; await refresh.value
    #expect(model.history.map(\.id) == [recovered])
    #expect(gate.translationRequests.count == 1)
    #expect(gate.historyCalls == 2)
    let cache = ContentCache(root: gate.outboxRoot.appendingPathComponent("cache"))
    let data = try #require(try await cache.load(dataset: "history", server: model.session.serverURL, owner: gate.owner))
    #expect(try JSONDecoder().decode([TranslationRecord].self, from: data).map(\.id) == [recovered])
}
@Test @MainActor func cancelledRecoveryRejectsLateAnswerAndLateFailureNotice() async throws {
    for fail in [false, true] {
        let gate = Gate(); gate.translationError = URLError(.timedOut)
        let model = await fixture(gate); model.draft = "same text"; await model.translate()
        let id = try #require(model.outbox.items.first?.id)
        gate.recoveredHistory = recoveredJSON(id, owner: gate.owner)
        gate.holdHistory = true; gate.failHistory = fail
        let check = Task { await model.checkTranslation(id) }
        while gate.historyRelease == nil { await Task.yield() }
        model.removeTranslation(id)
        gate.historyRelease?.resume(); gate.historyRelease = nil; await check.value
        #expect(model.outbox.items.first?.state == .cancelled)
        #expect(model.translationCheckNotices.isEmpty)
        #expect(model.checkingTranslations.isEmpty)
        #expect(model.history.isEmpty)
        #expect(model.result == nil)
        #expect(gate.translationRequests.count == 1)
    }
}
@Test @MainActor func hiddenCompletedReceiptsDoNotBlockNewSubmission() async throws {
    let gate = Gate(); let model = await fixture(gate)
    var saved = TranslationOutbox()
    for index in 0..<200 {
        saved.draft = "completed \(index)"
        try saved.enqueue(direction: .russianToGerman, instructions: nil)
        saved.items[index].state = .completed
    }
    try TranslationOutboxStore(root: gate.outboxRoot).save(saved, origin: model.session.serverURL, owner: gate.owner)
    model.loadTranslationOutbox(); model.draft = "new authorized request"
    await model.translate()
    #expect(gate.translationRequests.count == 1)
    #expect(model.outbox.items.count == 201, "Keep hidden completed receipts, not a permanent submission limit")
    var full = TranslationOutbox()
    for index in 0..<200 {
        full.draft = "pending \(index)"
        try full.enqueue(direction: .russianToGerman, instructions: nil)
    }
    full.draft = "pending 199"
    #expect(try full.enqueue(direction: .russianToGerman, instructions: nil) == full.items.last?.id)
    full.draft = "over capacity"
    #expect(throws: CocoaError.self) { try full.enqueue(direction: .russianToGerman, instructions: nil) }
}
@Test @MainActor func cancelledLookupTaskDoesNotAcceptAnUncancellableResponse() async throws {
    let gate = Gate(); gate.translationError = URLError(.timedOut)
    let model = await fixture(gate); model.draft = "same text"; await model.translate()
    let id = try #require(model.outbox.items.first?.id)
    gate.recoveredHistory = recoveredJSON(id, owner: gate.owner); gate.holdHistory = true
    let task = Task { await model.checkTranslation(id) }
    while gate.historyRelease == nil { await Task.yield() }
    task.cancel()
    gate.historyRelease?.resume(); gate.historyRelease = nil; await task.value
    #expect(model.outbox.items.first?.state == .needsDecision)
    #expect(model.history.isEmpty)
    #expect(model.result == nil)
    #expect(model.checkingTranslations.isEmpty)
    #expect(gate.translationRequests.count == 1)
}
@Test @MainActor func recoveryRoutesServerErrorsToGETAndProviderRetryReusesKey() async throws {
    for status in [424, 503] {
        let gate = Gate(); gate.translationStatus = status
        let model = await fixture(gate); model.draft = "retry original"; await model.translate()
        let id = try #require(model.outbox.items.first?.id)
        gate.translationStatus = 200
        await model.retryTranslation(id)
        #expect(model.outbox.items.count == 1)
        #expect(model.outbox.items.first?.id == id)
        #expect(gate.translationRequests.count == (status == 424 ? 2 : 1))
        #expect(gate.historyCalls == (status == 424 ? 0 : 1))
        #expect(gate.translationRequests.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == id.uuidString })
        #expect(model.outbox.items.first?.state == (status == 424 ? .completed : .failed))
    }
}
@Test @MainActor func outboxStorageFailureNeverSends() async throws {
    let gate = Gate(); let model = await fixture(gate)
    model.loadTranslationOutbox(); model.draft = "safe"
    #expect(await model.flushTranslationPersistence())
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
    #expect(model.historyLoadError == APIError.http(503).localizedDescription)
    #expect(model.translatorError == nil)
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
    #expect(model.translatorError == nil)
    #expect(model.providerDiagnostic == "chatgpt.status.unavailable")
}
@Test @MainActor func catalogTransportFailureIsAdvisoryAndTranslationFailureStaysVisible() async {
    let gate = Gate(); let model = await fixture(gate)
    await model.refreshTranslator()
    gate.catalogError = URLError(.timedOut)
    await model.refreshTranslator()
    #expect(model.provider?.connected == true)
    #expect(model.translatorError == nil)
    model.draft = "Typed during timeout"
    #expect(gate.translationRequests.isEmpty)
    gate.translationStatus = 424
    await model.translate()
    #expect(gate.translationRequests.count == 1)
    #expect(model.outbox.items.first?.state == .failed)
    #expect(model.outbox.items.first?.failure == .provider)
    await model.refreshTranslator()
    #expect(model.outbox.items.first?.failure == .provider)
    #expect(model.draft == "Typed during timeout")
    #expect(model.translatorError == nil)
}
@Test @MainActor func provider401IsIdentityFailureNotCatalogAdvisory() async {
    let gate = Gate(); let model = await fixture(gate)
    model.draft = "Private synthetic draft"
    await model.refreshTranslator()
    gate.providerHTTP = 401
    await model.refreshTranslator()
    #expect(model.session.user == nil)
    #expect(model.provider == nil)
    #expect(model.draft.isEmpty)
    #expect(gate.translationRequests.isEmpty)
}
@Test @MainActor func disconnectedProviderRemainsDistinctFromCatalogFailure() async {
    let gate = Gate(); gate.disconnected = true
    let model = await fixture(gate)
    await model.refreshTranslator()
    #expect(model.provider?.connected == false)
    #expect(model.provider?.status == "not_connected")
    #expect(model.translatorError == nil)
}
@Test @MainActor func unavailableCatalogKeepsConnectionButNoModel() async {
    let gate = Gate(); gate.degradedCatalog = true
    let model = await fixture(gate)
    await model.refreshTranslator()
    #expect(model.provider?.connected == true)
    #expect(model.provider?.selectedModel == "")
    #expect(model.translatorError == nil, "Auxiliary catalog failure must not become a red translation error")
    #expect(gate.translationRequests.isEmpty)
    model.draft = "Synthetic typed draft"
    #expect(gate.translationRequests.isEmpty, "Typing never authorizes inference")
    await model.translate()
    #expect(gate.translationRequests.count == 1)
    #expect(model.outbox.items.first?.state == .completed)
    #expect(model.draft == "Synthetic typed draft")
    await model.refreshTranslator()
    #expect(model.translatorError == nil, "Passive checks must not restore the red banner after success")
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
        coordinator = (ROOT/'App/DictationPlaybackCoordinator.swift').read_text().replace('import SwiftUI','import Foundation\nimport Observation')
        (p/'Sources/Lifecycle/DictationPlaybackCoordinator.swift').write_text(coordinator)
        # Only the platform output adapter is substituted. Production coordinator,
        # API transport, journal and admission controller run unchanged.
        (p/'Sources/Lifecycle/DictationPlayer.swift').write_text('''import Foundation
import Observation
@MainActor @Observable final class DictationPlayer {
 var playing = false
 var rate: Float = 1
 var finished: ((Bool) -> Void)?
 var position: Double = 0
 var duration: Double? = 8
 func play(_ data: Data, offset: Double = 0) throws { position=offset;playing=true }
 func stop(resetTiming: Bool = false) { playing=false;finished=nil;if resetTiming {position=0} }
}
''')
        (p/'Tests/LifecycleTests/DictationAssessmentTests.swift').write_text((ROOT/'ci/dictation_assessment_harness.swift').read_text())
        (p/'Tests/LifecycleTests/DictationGlobalTests.swift').write_text((ROOT/'ci/dictation_global_harness.swift').read_text())
        (p/'Sources/Lifecycle/TranslationProfileSync.swift').write_text((ROOT/'App/TranslationProfileSync.swift').read_text())
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
        (p/'Tests/LifecycleTests/PassageTests.swift').write_text((ROOT/'ci/passage_harness.swift').read_text())
        (p/'Tests/LifecycleTests/CoachTests.swift').write_text((ROOT/'ci/coach_harness.swift').read_text())
        (p/'Tests/LifecycleTests/DictationTests.swift').write_text((ROOT/'ci/dictation_harness.swift').read_text())
        (p/'Tests/LifecycleTests/FollowupTests.swift').write_text((ROOT/'ci/followup_harness.swift').read_text())
        (p/'Tests/LifecycleTests/ProfileTests.swift').write_text((ROOT/'ci/profile_harness.swift').read_text())
        # Execute the view's actual conflict resolver without requiring an iOS UI host.
        view = (ROOT/'App/DictationView.swift').read_text()
        resolver = view[view.index('    private func resolveConflict('):view.index('    private func perform(')].replace('private func resolveConflict', 'func resolveConflict')
        (p/'Sources/Lifecycle/DictationConflictHarness.swift').write_text('''import Foundation
import KeineMagieCore
@MainActor final class DictationConflictHarness {
 let model: AppModel
 var record: DictationRecord?
 var items: [DictationRecord] = []
 var error: String?
 var cleared = false
 init(model: AppModel) { self.model = model }
 func clear() { cleared = true; record = nil; items = [] }
''' + resolver + '}')
        (p/'Tests/LifecycleTests/CoachTwoClientTests.swift').write_text((ROOT/'ci/coach_two_client_harness.swift').read_text())
        subprocess.run(['swift','test','--jobs','2','--package-path',temp],check=True)

class ConnectionLifecycleTests(unittest.TestCase):
    def test_real_app_model_with_synthetic_transport(self):
        main()

if __name__ == '__main__': unittest.main()
