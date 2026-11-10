import Foundation
import Testing
@testable import KeineMagieCore

@Test func shortcutsPersistByStableOwnerAndServerNotSessionToken() throws {
    let suite = "shortcut-test-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TranslationShortcutStore(defaults: defaults)
    let item = try TranslationShortcut(title: "Work", instruction: "Use concise professional language.")
    try store.save([item], server: "https://a.example", owner: "alice")
    #expect(try store.load(server: "https://a.example", owner: "alice") == [item])
    #expect(try store.load(server: "https://a.example", owner: "bob").isEmpty)
    #expect(try store.load(server: "https://b.example", owner: "alice").isEmpty)
    let reopened = TranslationShortcutStore(defaults: defaults)
    #expect(try reopened.load(server: "https://a.example", owner: "alice") == [item])
    try store.save([], server: "https://a.example", owner: "alice")
    #expect(try reopened.load(server: "https://a.example", owner: "alice").isEmpty)
}
