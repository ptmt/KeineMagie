import Foundation
import Testing
@testable import KeineMagieCore

@MainActor
private final class HistoryHarness {
    var history = HistoryState()
    var isRefreshing = false

    func refresh(fetch: () async -> [TranslationRecord]) async {
        guard !isRefreshing else { return }
        let snapshot = history.snapshot()
        isRefreshing = true
        defer { isRefreshing = false }
        history.apply(await fetch(), since: snapshot)
    }
}

@MainActor
private final class SuspendedHistoryResponse {
    private var continuation: CheckedContinuation<[TranslationRecord], Never>?
    private var started: CheckedContinuation<Void, Never>?

    func fetch() async -> [TranslationRecord] {
        await withCheckedContinuation {
            continuation = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ records: [TranslationRecord]) {
        continuation?.resume(returning: records)
        continuation = nil
    }
}

private func record(_ id: String, at time: TimeInterval) -> TranslationRecord {
    TranslationRecord(id: id, createdAt: Date(timeIntervalSince1970: time), text: id,
                      sourceLanguage: .german, targetLanguage: .russian, translation: id,
                      idioms: [], patterns: [], vocabulary: [])
}

@Test @MainActor func staleRefreshPreservesTranslationCreatedWhileGETWasSuspended() async {
    let model = HistoryHarness()
    let response = SuspendedHistoryResponse()
    let refresh = Task { await model.refresh { await response.fetch() } }
    await response.waitUntilStarted()

    // POST persists and returns while the earlier GET still has its old snapshot.
    model.history.insert(record("new", at: 20))
    await model.refresh { Issue.record("Overlapping refresh should be skipped"); return [] }
    response.finish([record("old", at: 10)])
    await refresh.value

    #expect(model.history.records.map(\.id) == ["new", "old"])
    #expect(!model.isRefreshing)
}

@Test func insertedHistoryUsesTimestampOrderAndStableIDTiesWithoutDuplicates() {
    var history = HistoryState()
    history.insert(record("z", at: 30))
    history.insert(record("a", at: 30))
    history.insert(record("old", at: 10))
    history.insert(record("a", at: 30))
    #expect(history.records.map(\.id) == ["a", "z", "old"])
}

@Test func refreshMergesByIDAndKeepsConcurrentPOSTResultInTimestampOrder() {
    var history = HistoryState()
    let snapshot = history.snapshot()
    history.insert(record("new", at: 20))
    history.apply([record("z", at: 30), record("new", at: 5),
                   record("z", at: 30), record("a", at: 30)], since: snapshot)
    #expect(history.records.map(\.id) == ["a", "z", "new"])
    #expect(history.records.last?.createdAt == Date(timeIntervalSince1970: 20))
}

@Test func subsequentRefreshRemainsAuthoritativeForRecordsCreatedBeforeItStarted() {
    var history = HistoryState()
    let staleSnapshot = history.snapshot()
    history.insert(record("new", at: 20))
    history.apply([record("old", at: 10)], since: staleSnapshot)
    #expect(history.records.map(\.id) == ["new", "old"])

    let freshSnapshot = history.snapshot()
    history.apply([record("server", at: 30)], since: freshSnapshot)
    #expect(history.records.map(\.id) == ["server"])
}

@Test @MainActor func identityResetClearsHistoryAndRejectsPreviousIdentityResponse() async {
    let model = HistoryHarness()
    model.history.insert(record("previous-local", at: 10))
    let response = SuspendedHistoryResponse()
    let refresh = Task { await model.refresh { await response.fetch() } }
    await response.waitUntilStarted()

    // Both server and token changes use this reset in AppModel.saveSettings.
    model.history.reset()
    #expect(model.history.records.isEmpty)
    model.history.insert(record("current", at: 20))
    response.finish([record("previous-remote", at: 30)])
    await refresh.value
    #expect(model.history.records.map(\.id) == ["current"])

    model.history.reset()
    #expect(model.history.records.isEmpty)
    await model.refresh { [record("current-remote", at: 40)] }
    #expect(model.history.records.map(\.id) == ["current-remote"])
}
