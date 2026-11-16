import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@MainActor final class FollowupGate {
    var owner = "followup-owner"
    var requests: [URLRequest] = []
    var held: CheckedContinuation<Void, Never>?
    var suspend = false
    var status = 201
    var revisedSource: String? = "У меня встреча."
    let original = #"{"id":"saved","created_at":"2026-11-16T12:00:00Z","text":"фрагмент","source_language":"ru","target_language":"de","translation":"Fragment","idioms":[],"patterns":[],"vocabulary":[]}"#
    func send(_ r: URLRequest) async throws -> AuthResponse {
        if r.url!.path == "/v1/auth/session" { return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["user": ["id": owner], "expires_at": "2099-01-01T00:00:00Z"]), status: 200) }
        if r.url!.path == "/v1/provider" { return AuthResponse(data: Data(), status: 503) }
        if r.url!.path == "/v1/translations" { return AuthResponse(data: Data(("{\"items\":[" + original + "]}").utf8), status: 200) }
        if r.url!.path == "/v1/auth/logout" { return AuthResponse(data: Data(), status: 204) }
        if r.httpMethod == "DELETE" { return AuthResponse(data: Data(), status: 204) }
        let body = try JSONDecoder().decode(TranslationFollowupInput.self, from: r.httpBody!)
        requests.append(r)
        if suspend { await withCheckedContinuation { held = $0 } }
        if status != 201 { return AuthResponse(data: Data(), status: status) }
        var record = try JSONSerialization.jsonObject(with: Data(original.utf8)) as! [String: Any]
        record["followups"] = [["request_id": body.requestID, "question": body.question, "answer": "Short explanation", "current_source": body.currentSource, "current_translation": body.currentTranslation, "revised_text": "Ich habe einen Termin.", "revised_source_text": revisedSource as Any? ?? NSNull(), "created_at": "2026-11-16T12:01:00Z"]]
        return AuthResponse(data: try JSONSerialization.data(withJSONObject: record), status: 201)
    }
}
@MainActor func followupFixture(_ gate: FollowupGate, root: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) async -> AppModel {
    let transport: AuthClient.Transport = { r in try await gate.send(r) }
    let session = SessionController(serverURL: "https://followup.invalid", readToken: { "synthetic" }, saveToken: { _ in }, transport: transport)
    await session.restore()
    let model = AppModel(session: session, client: APIClient(endpoint: try! ServerEndpoint("https://followup.invalid"), token: "synthetic", transport: transport), cache: ContentCache(root: root))
    await model.refreshTranslator()
    #expect(model.displayedTranslation.isEmpty, "An empty initial result must not unwrap a nil local proposal")
    model.openTranslationDiscussion(model.history[0])
    return model
}
@Test @MainActor func followupOfflineReadsAndOwnerReplacementFence() async throws {
    let gate = FollowupGate(); let model = await followupFixture(gate)
    model.followupQuestion = "private"
    model.session.recordNetworkFailure(URLError(.notConnectedToInternet))
    #expect(model.discussionRecord?.text == "фрагмент")
    #expect(model.beginTranslationFollowup(locale: "en") == nil)
    #expect(gate.requests.isEmpty)
    await model.session.restore()
    gate.suspend = true
    let task = try #require(model.beginTranslationFollowup(locale: "en"))
    while gate.held == nil { await Task.yield() }
    gate.owner = "replacement-owner"
    await model.session.restore()
    model.resetSessionContent()
    gate.held?.resume(); await task.value
    #expect(model.discussionRecord == nil)
    #expect(model.history.isEmpty)
    #expect(model.followupQuestion.isEmpty)
}

@Test @MainActor func followupExplicitSendPreservesBaselineAndPairedApply() async throws {
    let gate = FollowupGate(); let model = await followupFixture(gate)
    model.followupQuestion = "контекст"
    #expect(gate.requests.isEmpty)
    let task = try #require(model.beginTranslationFollowup(locale: "ru")); await task.value
    #expect(gate.requests.count == 1)
    #expect(model.discussionRecord?.followups.count == 1)
    #expect(model.displayedTranslation == "Fragment")
    #expect(model.draft == "фрагмент")
    model.applyTranslationProposal(try #require(model.discussionRecord?.followups.first))
    #expect(model.draft == "У меня встреча.")
    #expect(model.displayedTranslation == "Ich habe einen Termin.")
    #expect(model.history.first?.text == "фрагмент")
    #expect(model.history.first?.translation == "Fragment")
}
@Test @MainActor func followupRetryKeepsExactIdentityAcrossRelaunch() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gate = FollowupGate(); gate.status = 502
    let model = await followupFixture(gate, root: root)
    model.followupQuestion = "question"
    await model.beginTranslationFollowup(locale: "en")?.value
    #expect(model.followupQuestion == "question")
    let again = await followupFixture(gate, root: root)
    await again.loadTranslationDiscussions()
    #expect(again.followupQuestion == "question")
    gate.status = 201
    await again.beginTranslationFollowup(locale: "en")?.value
    #expect(gate.requests.count == 2)
    #expect(gate.requests[0].httpBody == gate.requests[1].httpBody)
}
@Test @MainActor func followupCoalescesAndIgnoresCancelledLateReplyAndEdits() async throws {
    let gate = FollowupGate(); gate.suspend = true
    let model = await followupFixture(gate)
    model.followupQuestion = "question"
    let task = try #require(model.beginTranslationFollowup(locale: "en"))
    #expect(model.followupPending)
    #expect(model.beginTranslationFollowup(locale: "en") == nil)
    while gate.held == nil { await Task.yield() }
    model.draft = "new draft"
    model.closeTranslationDiscussion()
    gate.held?.resume(); await task.value
    #expect(model.draft == "new draft")
    #expect(model.history[0].followups.isEmpty)
    #expect(!model.followupPending)
    #expect(gate.requests.count == 1)
}
@Test @MainActor func followupUnauthorizedClearsPrivateState() async throws {
    let gate = FollowupGate(); gate.status = 401
    let model = await followupFixture(gate)
    model.followupQuestion = "private question"
    await model.beginTranslationFollowup(locale: "en")?.value
    #expect(model.session.phase == .signedOut)
    #expect(model.discussionRecord == nil)
    #expect(model.followupQuestion.isEmpty)
}

@Test @MainActor func followupQuotaKeepsDraftAndEditingNeverOverwritesOnCompletion() async throws {
    let gate = FollowupGate(); gate.status = 429
    let model = await followupFixture(gate)
    model.followupQuestion = "question"
    await model.beginTranslationFollowup(locale: "en")?.value
    #expect(model.followupError == "followup.quota")
    #expect(model.followupQuestion == "question")
    gate.status = 201; gate.suspend = true
    let task = try #require(model.beginTranslationFollowup(locale: "en"))
    while gate.held == nil { await Task.yield() }
    model.draft = "edited during followup"
    model.followupQuestion = "next question"
    gate.held?.resume(); await task.value
    #expect(model.draft == "edited during followup")
    #expect(model.followupQuestion == "next question")
    #expect(model.displayedTranslation == "Fragment")
    #expect(model.discussionRecord?.followups.count == 1)
}
@Test @MainActor func followupOwnerGenerationAndDeletionIgnoreLateTransport() async throws {
    let gate = FollowupGate(); gate.suspend = true
    let model = await followupFixture(gate)
    model.followupQuestion = "private"
    let task = try #require(model.beginTranslationFollowup(locale: "en"))
    while gate.held == nil { await Task.yield() }
    let item = model.history[0]
    model.deleteHistory(item)
    while model.historyBusy(item.id) { await Task.yield() }
    gate.held?.resume(); await task.value
    #expect(model.history.isEmpty)
    #expect(model.discussionRecord == nil)
    #expect(!model.followupPending)
    #expect(model.beginTranslationFollowup(locale: "en") == nil)
}
@Test @MainActor func followupLogoutCannotRestorePendingPrivateContent() async throws {
    let gate = FollowupGate(); gate.suspend = true
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = await followupFixture(gate, root: root)
    model.followupQuestion = "private"
    let task = try #require(model.beginTranslationFollowup(locale: "en"))
    while gate.held == nil { await Task.yield() }
    await model.logout()
    gate.held?.resume(); await task.value
    #expect(model.discussionRecord == nil)
    #expect(model.history.isEmpty)
    #expect(model.followupQuestion.isEmpty)
    let recreated = await followupFixture(gate, root: root)
    await recreated.loadTranslationDiscussions()
    #expect(recreated.followupQuestion.isEmpty, "Logout must purge persisted discussion drafts")
}

@Test @MainActor func followupSnapshotsExactCurrentDraftAndDoesNotApplyAnUnrequestedProposal() async throws {
    let gate = FollowupGate(); let model = await followupFixture(gate)
    model.draft = "  Текущий e\u{301} 👩🏽‍💻\n"
    model.followupQuestion = "  Why?\n"
    await model.beginTranslationFollowup(locale: "en")?.value
    let request = try #require(gate.requests.first)
    let body = try JSONDecoder().decode(TranslationFollowupInput.self, from: request.httpBody!)
    #expect(body.currentSource == "  Текущий e\u{301} 👩🏽‍💻\n")
    #expect(body.currentTranslation == "Fragment")
    #expect(body.question == "  Why?\n")
    #expect(model.draft == body.currentSource)
    #expect(model.displayedTranslation == "Fragment")
    let turn = try #require(model.discussionRecord?.followups.first)
    model.draft = "later manual edit"
    model.applyTranslationProposal(turn)
    #expect(model.draft == "У меня встреча.", "Explicit stale proposal apply uses its paired source, never the latest unrelated draft")
    #expect(model.displayedTranslation == "Ich habe einen Termin.")
    #expect(model.history[0].text == "фрагмент")
    #expect(model.history[0].translation == "Fragment")
}

@Test @MainActor func followupLegacyNullableProposalAppliesCapturedSourceNotLaterDraft() async throws {
    let gate = FollowupGate(); gate.revisedSource = nil
    let model = await followupFixture(gate)
    model.draft = "  captured source\n"
    model.followupQuestion = "wording?"
    await model.beginTranslationFollowup(locale: "en")?.value
    let turn = try #require(model.discussionRecord?.followups.first)
    #expect(turn.revisedSourceText == nil)
    model.draft = "later unrelated draft"
    model.applyTranslationProposal(turn)
    #expect(model.draft == "  captured source\n")
    #expect(model.displayedTranslation == "Ich habe einen Termin.")
    #expect(model.history[0].text == "фрагмент")
}

@Test @MainActor func followupStorageFailureDoesNotSendAndErrorsRetainExactRetry() async throws {
    for status in [403, 404, 409, 502, 503] {
        let gate = FollowupGate(); gate.status = status
        let model = await followupFixture(gate)
        model.followupQuestion = "retained"
        await model.beginTranslationFollowup(locale: "en")?.value
        #expect(model.followupQuestion == "retained")
        #expect(model.discussionRecord?.followups.isEmpty == true)
        #expect(model.followupError != nil)
        await model.beginTranslationFollowup(locale: "en")?.value
        #expect(gate.requests.count == 2)
        #expect(gate.requests[0].httpBody == gate.requests[1].httpBody)
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gate = FollowupGate(); let model = await followupFixture(gate, root: root)
    await model.loadTranslationDiscussions()
    try FileManager.default.removeItem(at: root)
    try Data().write(to: root)
    model.followupQuestion = "must not send"
    await model.beginTranslationFollowup(locale: "en")?.value
    #expect(gate.requests.isEmpty)
    #expect(model.followupError == "followup.storage")
}
