import XCTest
@testable import KeineMagieCore

final class ContentCacheTests: XCTestCase {
    func testRevisionFenceRejectsOutOfOrderWritesAndInvalidatedSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ContentCache(root: root)
        let lease = cache.openSession(server: "https://one.example", owner: "A")
        try await cache.save(Data("new".utf8), dataset: "history", session: lease, revision: 2)
        try await cache.save(Data("old".utf8), dataset: "history", session: lease, revision: 1)
        let data = try await cache.load(dataset: "history", server: "https://one.example", owner: "A")
        XCTAssertEqual(data, Data("new".utf8))
        lease.invalidate()
        try await cache.save(Data("late".utf8), dataset: "history", session: lease, revision: 3)
        let after = try await cache.load(dataset: "history", server: "https://one.example", owner: "A")
        XCTAssertEqual(after, data)
        try await cache.remove(session: lease)
        let cleared = try await cache.load(dataset: "history", server: "https://one.example", owner: "A")
        XCTAssertNil(cleared)
    }

    func testNewSessionSupersedesQueuedOldWriteAndCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ContentCache(root: root)
        let old = cache.openSession(server: "https://one.example", owner: "A")
        let current = cache.openSession(server: "https://one.example", owner: "A")
        try await cache.save(Data("current".utf8), dataset: "history", session: current, revision: 1)
        try await cache.save(Data("stale".utf8), dataset: "history", session: old, revision: 99)
        try await cache.remove(session: old)
        let data = try await cache.load(dataset: "history", server: "https://one.example", owner: "A")
        XCTAssertEqual(data, Data("current".utf8))
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let attributes = try FileManager.default.attributesOfItem(atPath: files[0].path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testLogoutRemovesLearningSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ContentCache(root: root)
        let lease = cache.openSession(server: "https://one.example", owner: "A")
        try await cache.save(Data("private summary".utf8), dataset: "learning", session: lease, revision: 1)
        lease.invalidate()
        try await cache.remove(session: lease)
        let cleared = try await cache.load(dataset: "learning", server: "https://one.example", owner: "A")
        XCTAssertNil(cleared)
    }
    func testOwnerAndServerIsolation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ContentCache(root: root)
        try await cache.save(Data("private history".utf8), dataset: "history", server: "https://one.example", owner: "A")
        let own = try await cache.load(dataset: "history", server: "https://one.example", owner: "A")
        let otherOwner = try await cache.load(dataset: "history", server: "https://one.example", owner: "B")
        let otherServer = try await cache.load(dataset: "history", server: "https://two.example", owner: "A")
        XCTAssertEqual(own, Data("private history".utf8))
        XCTAssertNil(otherOwner); XCTAssertNil(otherServer)
    }
}
