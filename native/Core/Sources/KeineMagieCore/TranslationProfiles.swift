import Foundation
import CryptoKit

public struct TranslationProfile: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var instruction: String
    public var revision: Int
    public var deleted: Bool
    public var localID: UUID { UUID(uuidString: id) ?? Self.stableID(id) }
    public static func stableID(_ text: String) -> UUID {
        let h = SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02X", $0) }.joined()
        let a = Array(h)
        return UUID(uuidString: String(a[0..<8]) + "-" + String(a[8..<12]) + "-" + String(a[12..<16]) + "-" + String(a[16..<20]) + "-" + String(a[20..<32]))!
    }
    public static func legacyID(id: String, title: String, instruction: String) -> UUID {
        stableID([id, title, instruction].map { "\($0.utf8.count):\($0)" }.joined())
    }
    public var valid: Bool {
        id.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$", options: .regularExpression) != nil && revision >= 0 &&
        (deleted || (!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.unicodeScalars.count <= 60 && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && instruction.unicodeScalars.count <= 1000))
    }
}
public struct TranslationProfileSnapshot: Codable, Equatable, Sendable {
    public var revision: Int
    public var items: [TranslationProfile]
    public init(revision: Int = 0, items: [TranslationProfile] = []) { self.revision = revision; self.items = items }
    public func validated() throws -> Self {
        guard revision >= 0, items.allSatisfy(\.valid), Set(items.map(\.id)).count == items.count else { throw APIError.invalidResponse }
        return self
    }
}
public struct TranslationProfileOperation: Codable, Equatable, Sendable {
    public var operationID: String
    public var id: String
    public var baseRevision: Int
    public var title: String?
    public var instruction: String?
    enum CodingKeys: String, CodingKey { case operationID = "operation_id", id, baseRevision = "base_revision", title, instruction }
}
public struct TranslationProfilePending: Codable, Equatable, Sendable {
    public var method: String
    public var body: TranslationProfileOperation
    public var conflict = false
    public var blocked: String?
}
public struct TranslationProfileJournal: Codable, Equatable, Sendable {
    public var snapshot = TranslationProfileSnapshot()
    public var pending: [TranslationProfilePending] = []
    public var migrated = false
    public init() {}
    public var visible: [TranslationProfile] {
        var result = snapshot.items
        for op in pending {
            let v = TranslationProfile(id: op.body.id, title: op.body.title ?? "", instruction: op.body.instruction ?? "", revision: op.body.baseRevision, deleted: op.method == "DELETE")
            if let i = result.firstIndex(where: { $0.id == v.id }) { result[i] = v } else { result.append(v) }
        }
        return result.filter { !$0.deleted }
    }
    public var shortcuts: [TranslationShortcut] { visible.compactMap { (try? TranslationShortcut(syncedID: $0.localID, title: $0.title, instruction: $0.instruction)) ?? (try? TranslationShortcut(id: $0.localID, title: $0.title, instruction: $0.instruction)) } }
    public func revision(_ id: UUID) -> Int { snapshot.items.first { $0.localID == id }?.revision ?? 0 }
    public mutating func migrate(_ legacy: [TranslationShortcut]) throws {
        guard !migrated else { return }
        for v in legacy {
            let id = TranslationProfile.legacyID(id: v.id.uuidString, title: v.title, instruction: v.instruction).uuidString
            // Retain even a legacy title outside the new scalar bound in the
            // journal; the server rejects it without acknowledging or deleting it.
            pending.append(TranslationProfilePending(method: "PUT", body: .init(operationID: "import-" + id, id: id, baseRevision: 0, title: v.title, instruction: v.instruction)))
        }
        migrated = true
    }
    public mutating func save(id: UUID, title: String, instruction: String, expectedRevision: Int? = nil) throws {
        let item = try TranslationShortcut(syncedID: id, title: title, instruction: instruction)
        let rawID = visible.first { $0.localID == id }?.id ?? id.uuidString
        if pending.contains(where: { $0.method == "PUT" && $0.body.id == rawID && ($0.body.title?.unicodeScalars.count ?? 0) > 60 }), !snapshot.items.contains(where: { $0.id == rawID }) {
            // This legacy payload cannot have been accepted by the scalar-bounded
            // protocol. Explicit correction replaces only its unsendable attempt;
            // the untouched UserDefaults legacy copy remains recoverable.
            pending.removeAll { $0.body.id == rawID }
        }
        let exists = snapshot.items.contains { $0.id == rawID } || pending.contains { $0.body.id == rawID }
        pending.append(TranslationProfilePending(method: exists ? "PATCH" : "PUT", body: .init(operationID: UUID().uuidString, id: rawID, baseRevision: expectedRevision ?? revision(id), title: item.title, instruction: item.instruction)))
    }
    public mutating func delete(_ id: UUID, expectedRevision: Int? = nil) {
        let rawID = visible.first { $0.localID == id }?.id ?? id.uuidString
        pending.append(TranslationProfilePending(method: "DELETE", body: .init(operationID: UUID().uuidString, id: rawID, baseRevision: expectedRevision ?? revision(id))))
    }
    public mutating func receive(_ value: TranslationProfileSnapshot) throws {
        let value = try value.validated()
        if value.revision >= snapshot.revision {
            snapshot = value
            // A deliberately shortened legacy title may have been saved under
            // its stable content-derived identity. Do not overlay its rejected
            // old import after logout/reinstall; retain the untouched legacy file.
            pending.removeAll { op in op.method == "PUT" && op.body.operationID == "import-" + op.body.id && (op.body.title?.unicodeScalars.count ?? 0) > 60 && value.items.contains { $0.id == op.body.id } }
        }
    }
    public mutating func acknowledge(_ op: TranslationProfilePending, _ value: TranslationProfileSnapshot) throws {
        guard pending.first?.body.operationID == op.body.operationID, value.items.contains(where: { $0.id == op.body.id && $0.revision > op.body.baseRevision }) else { throw APIError.invalidResponse }
        try receive(value); pending.removeAll { $0.body.operationID == op.body.operationID }
        // Receipt replay returns current server content, which may include a
        // different device's edit. Keep the stale base so that edit conflicts.
        if let i = pending.firstIndex(where: { $0.body.id == op.body.id }), let saved = value.items.first(where: { $0.id == op.body.id }), !saved.deleted, saved.title == op.body.title, saved.instruction == op.body.instruction {
            pending[i].body.baseRevision = saved.revision
            if pending[i].method == "PUT" { pending[i].method = "PATCH" }
        }
    }
    public mutating func prioritizeIndependentDeletion() {
        guard let first = pending.first, first.conflict || first.blocked != nil else { return }
        if let index = pending.indices.first(where: { i in pending[i].method == "DELETE" && !pending[..<i].contains { $0.body.id == pending[i].body.id } }), index > 0 {
            let deletion = pending.remove(at: index); pending.insert(deletion, at: 0)
        }
    }
    public mutating func resolveConflict(keepBoth: Bool) {
        guard let op = pending.first, op.conflict else { return }
        let last = pending.last { $0.body.id == op.body.id }
        pending.removeAll { $0.body.id == op.body.id }
        if keepBoth, let last, last.method != "DELETE" {
            pending.insert(TranslationProfilePending(method: "PUT", body: .init(operationID: UUID().uuidString, id: UUID().uuidString, baseRevision: 0, title: last.body.title, instruction: last.body.instruction)), at: 0)
        }
    }
}

/// Small journal writes are synchronous on the owning model's MainActor: no
/// queued file write can outlive owner reset. Network suspension is fenced there.
public struct TranslationProfileStore: Sendable {
    private let root: URL
    public init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("TranslationProfiles", isDirectory: true)) { self.root = root }
    private func file(origin: String, owner: String) -> URL { root.appendingPathComponent(SHA256.hash(data: Data((origin + "\u{0}" + owner).utf8)).map { String(format: "%02x", $0) }.joined() + ".json") }
    public func load(origin: String, owner: String) throws -> TranslationProfileJournal {
        let url = file(origin: origin, owner: owner)
        guard !owner.isEmpty, !origin.isEmpty else { throw APIError.missingToken }
        guard !UserDefaults.standard.bool(forKey: "profiles-denied:" + url.path), FileManager.default.fileExists(atPath: url.path) else { return TranslationProfileJournal() }
        return try JSONDecoder().decode(TranslationProfileJournal.self, from: Data(contentsOf: url))
    }
    public func save(_ value: TranslationProfileJournal, origin: String, owner: String) throws {
        guard !owner.isEmpty, !origin.isEmpty else { throw APIError.missingToken }
        let data = try JSONEncoder().encode(value)
        guard data.count <= 4 * 1024 * 1024 else { throw APIError.invalidResponse }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var directory = root, attributes = URLResourceValues(); attributes.isExcludedFromBackup = true; try directory.setResourceValues(attributes)
        let url = file(origin: origin, owner: owner)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        UserDefaults.standard.removeObject(forKey: "profiles-denied:" + url.path)
    }
    public func remove(origin: String, owner: String) throws {
        let url = file(origin: origin, owner: owner)
        UserDefaults.standard.set(true, forKey: "profiles-denied:" + url.path)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
