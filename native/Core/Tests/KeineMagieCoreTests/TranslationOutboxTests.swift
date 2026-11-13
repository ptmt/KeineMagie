import Foundation
import Testing
@testable import KeineMagieCore

@Test func outboxLogoutDeniesRestoreOfResidualFile() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = TranslationOutboxStore(root: root)
    var value = TranslationOutbox(); value.draft = "private"; try value.enqueue(direction: .russianToGerman, instructions: nil)
    try store.save(value, origin: "https://logout.invalid", owner: "alice")
    let file = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
    let residual = try Data(contentsOf: file)
    try store.remove(origin: "https://logout.invalid", owner: "alice")
    try residual.write(to: file) // simulate a surviving old file after purge failure
    #expect(try store.load(origin: "https://logout.invalid", owner: "alice").items.isEmpty)
}

@Test func outboxPersistsExactImmutableSnapshotAndRecoversSending() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = TranslationOutboxStore(root: root)
    var value = TranslationOutbox()
    value.draft = "  Привет 👩🏽‍💻 e\u{301}\n"
    let id = try value.enqueue(direction: .russianToGerman, instructions: "exact style")
    value.items[0].state = .sending
    try store.save(value, origin: "https://a.invalid", owner: "alice")
    value.draft = "new draft"
    let restored = try store.load(origin: "https://a.invalid", owner: "alice")
    #expect(restored.items.first?.id == id)
    #expect(restored.items.first?.text == "  Привет 👩🏽‍💻 e\u{301}\n")
    #expect(restored.items.first?.state == .needsDecision)
    #expect(try store.load(origin: "https://a.invalid", owner: "bob").items.isEmpty)
    #expect(try store.load(origin: "https://b.invalid", owner: "alice").items.isEmpty)
    #expect(try store.load(origin: "https://a.invalid", owner: nil).items.isEmpty)
}
