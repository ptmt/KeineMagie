import Foundation
import Testing
@testable import KeineMagieCore

private func historyItem(_ id: String = "one", favorite: Bool = false) -> TranslationRecord {
    TranslationRecord(id: id, createdAt: Date(timeIntervalSince1970: 10), text: id,
                      sourceLanguage: .german, targetLanguage: .russian, translation: "result",
                      favorite: favorite, idioms: [], patterns: [], vocabulary: [])
}

@Test func historyMutationsWaitForAcknowledgementAndDeduplicatePerRow() throws {
    var state = HistoryState()
    state.insert(historyItem())
    let mutationValue = state.beginMutation(id: "one")
    let mutation = try #require(mutationValue)
    #expect(state.isMutating("one"))
    #expect(state.beginMutation(id: "one") == nil)
    #expect(state.records.count == 1)
    state.failMutation(mutation)
    #expect(!state.isMutating("one"))
    #expect(state.records.count == 1)
}

@Test func deletedHistoryCannotBeResurrectedByDelayedGETEvenAfterNewerRefresh() throws {
    var state = HistoryState()
    state.insert(historyItem())
    let before = state.snapshot()
    let deletionValue = state.beginMutation(id: "one")
    let deletion = try #require(deletionValue)
    let during = state.snapshot()
    state.completeDeletion(deletion)
    state.apply([], since: state.snapshot())
    state.apply([historyItem()], since: before)
    state.apply([historyItem()], since: during)
    #expect(state.records.isEmpty)
}

@Test func favoriteAcknowledgementWinsAgainstGETStartedDuringMutation() throws {
    var state = HistoryState()
    state.insert(historyItem())
    let mutationValue = state.beginMutation(id: "one")
    let mutation = try #require(mutationValue)
    let delayed = state.snapshot()
    state.apply([], since: delayed)
    #expect(state.records.count == 1, "Pending rows remain visible")
    state.completeUpdate(historyItem(favorite: true), mutation: mutation)
    #expect(state.records.first?.favorite == true)
    state.apply([historyItem(favorite: true)], since: state.snapshot())
    state.apply([historyItem()], since: delayed)
    #expect(state.records.first?.favorite == true)
}

@Test func resetRejectsOldMutationAcknowledgementAndFailureForSameID() throws {
    var state = HistoryState()
    state.insert(historyItem())
    let oldValue = state.beginMutation(id: "one")
    let old = try #require(oldValue)
    state.reset()
    state.insert(historyItem())
    let currentValue = state.beginMutation(id: "one")
    let current = try #require(currentValue)
    state.completeUpdate(historyItem(favorite: true), mutation: old)
    state.completeDeletion(old)
    state.failMutation(old)
    #expect(state.records.first?.favorite == false)
    #expect(state.isMutating("one"))
    state.completeUpdate(historyItem(favorite: true), mutation: current)
    #expect(state.records.first?.favorite == true)
    #expect(!state.isMutating("one"))
}

@MainActor private final class DelayedMutationGET {
    var continuation: CheckedContinuation<[TranslationRecord], Never>?
    func fetch() async -> [TranslationRecord] { await withCheckedContinuation { continuation = $0 } }
    func waitUntilStarted() async { while continuation == nil { await Task.yield() } }
    func finish(_ records: [TranslationRecord]) { continuation?.resume(returning: records); continuation = nil }
}
@MainActor private final class MutationHistoryHarness {
    var state = HistoryState()
    func refresh(_ response: DelayedMutationGET) async {
        let snapshot = state.snapshot()
        state.apply(await response.fetch(), since: snapshot)
    }
}
@Test @MainActor func suspendedGETCannotUndoAcknowledgedDeletionOrFavorite() async throws {
    let model = MutationHistoryHarness()
    model.state.insert(historyItem())
    model.state.insert(historyItem("two"))
    let deletionValue = model.state.beginMutation(id: "one")
    let deletion = try #require(deletionValue)
    let updateValue = model.state.beginMutation(id: "two")
    let update = try #require(updateValue)
    let response = DelayedMutationGET()
    let refresh = Task { await model.refresh(response) }
    await response.waitUntilStarted()
    model.state.completeDeletion(deletion)
    model.state.completeUpdate(historyItem("two", favorite: true), mutation: update)
    response.finish([historyItem(), historyItem("two")])
    await refresh.value
    #expect(model.state.records.map(\.id) == ["two"])
    #expect(model.state.records.first?.favorite == true)
}
@Test @MainActor func suspendedMutationResponseAfterOwnerResetCannotChangeNewOwnersRow() async throws {
    let model = MutationHistoryHarness()
    model.state.insert(historyItem())
    let oldValue = model.state.beginMutation(id: "one")
    let old = try #require(oldValue)
    let response = DelayedMutationGET()
    let mutation = Task {
        _ = await response.fetch()
        model.state.completeDeletion(old)
    }
    await response.waitUntilStarted()
    model.state.reset(); model.state.insert(historyItem(favorite: true))
    response.finish([])
    await mutation.value
    #expect(model.state.records.first?.favorite == true)
}

@Test func legacyHistoryDefaultsFavoriteToFalse() throws {
    let data = Data(#"{"id":"old","created_at":"2026-11-10T10:00:00Z","text":"old","source_language":"de","target_language":"ru","translation":"result","idioms":[],"patterns":[],"vocabulary":[]}"#.utf8)
    #expect(try APIJSON.decoder().decode(TranslationRecord.self, from: data).favorite == false)
}

@Test func historyMutationRequestsEncodeSingleIDAndExactContract() throws {
    let client = APIClient(endpoint: try ServerEndpoint("https://example.com/app"), token: "secret")
    let id = "a/b ?#%ü"
    let deletion = try client.deleteHistoryRequest(id: id)
    #expect(deletion.httpMethod == "DELETE")
    #expect(deletion.url?.absoluteString == "https://example.com/app/v1/history/a%2Fb%20%3F%23%25%C3%BC")
    #expect(deletion.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    let update = try client.favoriteHistoryRequest(id: id, favorite: true)
    #expect(update.httpMethod == "PATCH")
    #expect(update.url == deletion.url)
    #expect(update.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(try JSONSerialization.jsonObject(with: #require(update.httpBody)) as? [String: Bool] == ["favorite": true])
    #expect(throws: (any Error).self) { try client.deleteHistoryRequest(id: "") }
}

@Test func germanPolishingDirectionUsesRealTranslationRequestWithInstructions() throws {
    let api = APIClient(endpoint: try ServerEndpoint("https://example.com"), token: "secret")
    let request = try api.translationRequest(text: "Ich hat Zeit", direction: .germanPolishing, instructions: "Friendly")
    let data = try #require(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: String]
    let body = try #require(object)
    #expect(body["source_language"] == "de")
    #expect(body["target_language"] == "de")
    #expect(body["text"] == "Ich hat Zeit")
    #expect(body["instructions"] == "Friendly")
}

@Test func historyMutationTransportAccepts204AndDecodesUpdatedRecord() async throws {
    let data = Data(#"{"id":"one","created_at":"2026-11-10T10:00:00Z","text":"old","source_language":"de","target_language":"ru","translation":"result","favorite":true,"idioms":[],"patterns":[],"vocabulary":[]}"#.utf8)
    let client = APIClient(endpoint: try ServerEndpoint("https://example.com"), token: "secret", transport: { request in
        if request.httpMethod == "DELETE" { return AuthResponse(data: Data(), status: 204) }
        return AuthResponse(data: data, status: 200)
    })
    try await client.deleteHistory(id: "one")
    #expect(try await client.setHistoryFavorite(id: "one", favorite: true).favorite)
}
