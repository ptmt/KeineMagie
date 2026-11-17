import Foundation
import Testing
@testable import KeineMagieCore

@Test func profileLostAcknowledgementDoesNotRebaseAcrossRemoteEdit() throws {
    let id = UUID(); var journal = TranslationProfileJournal()
    try journal.save(id: id, title: "Original", instruction: "Text")
    let sent = journal.pending[0]
    try journal.save(id: id, title: "Queued local edit", instruction: "Text")
    let remote = TranslationProfileSnapshot(revision: 2, items: [TranslationProfile(id: id.uuidString, title: "Other device edit", instruction: "Text", revision: 2, deleted: false)])
    try journal.acknowledge(sent, remote)
    #expect(journal.pending.count == 1)
    #expect(journal.pending[0].body.baseRevision == 0)
    #expect(journal.shortcuts.first?.title == "Queued local edit")
}

@Test func profileCapacityAllowsIndependentDeleteWithoutReorderingDependentEdits() throws {
    let existing = UUID(); var journal = TranslationProfileJournal()
    journal.snapshot = TranslationProfileSnapshot(revision: 1, items: [TranslationProfile(id: existing.uuidString, title: "Existing", instruction: "Text", revision: 1, deleted: false)])
    try journal.save(id: UUID(), title: "Pending", instruction: "New")
    journal.pending[0].blocked = "limit"
    journal.delete(existing)
    journal.prioritizeIndependentDeletion()
    #expect(journal.pending.first?.method == "DELETE")
    #expect(journal.pending.last?.body.title == "Pending")
}

@Test func profileLegacyIDMatchesBrowserUTF8Fixture() {
    #expect(TranslationProfile.legacyID(id: "00000000-0000-0000-0000-000000000001", title: "仕事 🙂", instruction: "Keep meaning.").uuidString == "CF2B83CA-E1BE-71E3-FB92-13F1C8557904")
}
@Test func profileScalarLimitsPreserveWhitespaceAndLegacyLongClusters() throws {
    let value = try TranslationShortcut(syncedID: UUID(), title: String(repeating: "🙂", count: 60), instruction: "  é\nLiteral  ")
    #expect(value.instruction == "  é\nLiteral  ")
    #expect(throws: (any Error).self) { try TranslationShortcut(syncedID: UUID(), title: String(repeating: "🙂", count: 61), instruction: "valid") }
    let old = try TranslationShortcut(title: String(repeating: "👩🏽‍💻", count: 40), instruction: "valid")
    var journal = TranslationProfileJournal(); try journal.migrate([old])
    #expect(journal.shortcuts.first?.title == old.title)
    #expect(journal.pending.first?.body.title == old.title)
    let correctedID = try #require(journal.shortcuts.first?.id)
    try journal.save(id: correctedID, title: "Short title", instruction: old.instruction)
    #expect(journal.pending.count == 1)
    #expect(journal.pending[0].method == "PUT")
    #expect(journal.pending[0].body.title == "Short title")
    var reimport = TranslationProfileJournal(); try reimport.migrate([old])
    try reimport.receive(TranslationProfileSnapshot(revision: 1, items: [TranslationProfile(id: correctedID.uuidString, title: "Short title", instruction: old.instruction, revision: 1, deleted: false)]))
    #expect(reimport.pending.isEmpty)
    #expect(reimport.shortcuts.first?.title == "Short title")
}
@Test func profileDuplicateLegacyIDsPreserveDifferentContentsAndTombstoneReplay() throws {
    let id = UUID()
    let a = try TranslationShortcut(id: id, title: "Same", instruction: "First")
    let b = try TranslationShortcut(id: id, title: "Same", instruction: "Second")
    var journal = TranslationProfileJournal(); try journal.migrate([a,b])
    #expect(journal.pending.count == 2); #expect(journal.pending[0].body.id != journal.pending[1].body.id)
    let first = journal.pending[0]
    let tombstone = TranslationProfile(id: first.body.id, title: "", instruction: "", revision: 4, deleted: true)
    try journal.acknowledge(first, TranslationProfileSnapshot(revision: 4, items: [tombstone]))
    #expect(!journal.shortcuts.contains { $0.id == tombstone.localID })
    #expect(journal.pending.count == 1)
}
@Test func profileStoreOwnerOriginColdRelaunchAndPurge() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = TranslationProfileStore(root: root)
    var journal = TranslationProfileJournal(); try journal.migrate([])
    try journal.save(id: UUID(), title: "Private", instruction: "Pending")
    try store.save(journal, origin: "https://one.invalid", owner: "one")
    let reopened = TranslationProfileStore(root: root)
    #expect(try reopened.load(origin: "https://one.invalid", owner: "one").pending.count == 1)
    #expect(try reopened.load(origin: "https://two.invalid", owner: "one").pending.isEmpty)
    #expect(try reopened.load(origin: "https://one.invalid", owner: "two").pending.isEmpty)
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    #expect(try FileManager.default.attributesOfItem(atPath: files[0].path)[.posixPermissions] as? Int == 0o600)
    try store.remove(origin: "https://one.invalid", owner: "one")
    #expect(try reopened.load(origin: "https://one.invalid", owner: "one").pending.isEmpty)
}


@Test func profileJournalMigratesAndPreservesOfflineEdit() throws {
    let legacy = try TranslationShortcut(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "仕事 🙂", instruction: "Keep meaning.")
    var journal = TranslationProfileJournal()
    try journal.migrate([legacy])
    #expect(journal.pending.count == 1)
    let first = try #require(journal.shortcuts.first)
    try journal.save(id: first.id, title: "Changed", instruction: "Keep meaning.")
    let restored = try JSONDecoder().decode(TranslationProfileJournal.self, from: JSONEncoder().encode(journal))
    #expect(restored.shortcuts.first?.title == "Changed")
    #expect(restored.pending.count == 2)
    var retry = restored; try retry.migrate([legacy])
    #expect(retry.pending.count == 2)
}
