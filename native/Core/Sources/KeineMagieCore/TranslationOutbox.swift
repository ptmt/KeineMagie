import Foundation
import CryptoKit

public struct TranslationOutbox: Codable, Sendable {
    public enum State: String, Codable, Sendable { case queued, sending, failed, completed, cancelled, needsDecision }
    public enum Failure: String, Codable, Sendable { case network, authentication, provider, rateLimit, server, uncertain, storage }
    public struct Item: Codable, Identifiable, Sendable {
        public let id: UUID
        public let text: String
        public let direction: TranslationDirection
        public let instructions: String?
        public var state: State = .queued
        public var failure: Failure?
        public var attempts = 0
        public var nextAttempt: Date?
        public var result: TranslationRecord?
    }
    public var draft = ""
    public var direction: TranslationDirection = .russianToGerman
    public var selectedShortcutID: String?
    public var items: [Item] = []
    public init() {}
    @discardableResult public mutating func enqueue(direction: TranslationDirection, instructions: String?) throws -> UUID {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.unicodeScalars.count <= 8000 else { throw APIError.emptyText }
        // A repeated submit must not mint a fresh key for any unresolved item,
        // including a timeout whose provider outcome is unknown. Use Retry/check
        // for that same snapshot; cancel/delete is the explicit escape hatch.
        if let item = items.last(where: { ![.completed, .cancelled].contains($0.state) && $0.text == draft && $0.direction == direction && $0.instructions == instructions }) { return item.id }
        guard items.count < 200 else { throw CocoaError(.fileWriteOutOfSpace) }
        let item = Item(id: UUID(), text: draft, direction: direction, instructions: instructions)
        items.append(item)
        return item.id
    }
}

/// Synchronous atomic local journal: callers serialize on MainActor and never
/// suspend between validating the trusted owner lease and saving a snapshot.
/// An unassigned draft has a distinct namespace; it is never adopted on login.
public struct TranslationOutboxStore: Sendable {
    private let root: URL
    public init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("TranslationOutbox", isDirectory: true)) { self.root = root }
    private func path(origin: String, owner: String?) -> URL {
        let scope = origin + "\u{0}" + (owner.map { "owner:" + $0 } ?? "unassigned")
        return root.appendingPathComponent(SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined() + ".json")
    }
    public func load(origin: String, owner: String?) throws -> TranslationOutbox {
        let file = path(origin: origin, owner: owner)
        guard !UserDefaults.standard.bool(forKey: "outbox-denied:" + file.path) else { return TranslationOutbox() }
        guard FileManager.default.fileExists(atPath: file.path) else { return TranslationOutbox() }
        var value = try JSONDecoder().decode(TranslationOutbox.self, from: Data(contentsOf: file))
        for i in value.items.indices where value.items[i].state == .sending {
            // Do not assume a killed process means an unspent provider attempt.
            value.items[i].state = .needsDecision; value.items[i].failure = .uncertain
        }
        return value
    }
    public func save(_ value: TranslationOutbox, origin: String, owner: String?) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var directory = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let data = try JSONEncoder().encode(value)
        let file = path(origin: origin, owner: owner)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        UserDefaults.standard.removeObject(forKey: "outbox-denied:" + file.path)
    }
    public func remove(origin: String, owner: String?) throws {
        let file = path(origin: origin, owner: owner)
        // Deny-only preference, never identity proof. A failed filesystem purge
        // must not resurrect authorized jobs on a subsequent same-owner login.
        UserDefaults.standard.set(true, forKey: "outbox-denied:" + file.path)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
