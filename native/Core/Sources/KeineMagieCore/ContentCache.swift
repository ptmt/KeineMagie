import Foundation
import CryptoKit

private final class CacheFence: @unchecked Sendable {
    let lock = NSLock()
    var current: [String: UUID] = [:]
}
/// The lock covers the actual atomic write as well as invalidation: no check-then-write window.
public final class ContentCacheSession: @unchecked Sendable {
    fileprivate let id = UUID()
    fileprivate let server: String
    fileprivate let owner: String
    fileprivate var scope: String { server + "\u{0}" + owner }
    fileprivate let fence: CacheFence
    fileprivate var active = true
    fileprivate init(server: String, owner: String, fence: CacheFence) { self.server = server; self.owner = owner; self.fence = fence }
    public func invalidate() { fence.lock.withLock { active = false } }
}

/// Non-secret personal content only. Credentials never enter this store.
public actor ContentCache {
    private let root: URL
    private nonisolated let fence = CacheFence()
    private var revisions: [String: (UUID, Int)] = [:]
    public init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("ContentCache", isDirectory: true)) { self.root = root }
    public nonisolated func openSession(server: String, owner: String) -> ContentCacheSession {
        let session = ContentCacheSession(server: server, owner: owner, fence: fence)
        fence.lock.withLock { fence.current[session.scope] = session.id }
        return session
    }
    public func save(_ data: Data, dataset: String, session: ContentCacheSession, revision: Int) throws {
        try fence.lock.withLock {
            guard session.active, fence.current[session.scope] == session.id else { return }
            let key = session.scope + "\u{0}" + dataset
            if let previous = revisions[key], previous.0 == session.id, previous.1 >= revision { return }
            try save(data, dataset: dataset, server: session.server, owner: session.owner)
            revisions[key] = (session.id, revision)
        }
    }
    /// Explicit logout/account boundary cleanup. A later session cannot be erased by a queued cleanup.
    public func remove(session: ContentCacheSession) throws {
        try fence.lock.withLock {
            guard fence.current[session.scope] == session.id else { return }
            for dataset in ["history", "podcasts", "learning"] {
                let url = path(dataset: dataset, server: session.server, owner: session.owner)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                revisions[session.scope + "\u{0}" + dataset] = nil
            }
        }
    }
    private func path(dataset: String, server: String, owner: String) -> URL {
        let key = Data((server + "\u{0}" + owner + "\u{0}" + dataset).utf8)
        let digest = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(digest + ".json")
    }
    public func load(dataset: String, server: String, owner: String) throws -> Data? {
        let url = path(dataset: dataset, server: server, owner: owner)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    public func save(_ data: Data, dataset: String, server: String, owner: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var directory = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let url = path(dataset: dataset, server: server, owner: owner)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
