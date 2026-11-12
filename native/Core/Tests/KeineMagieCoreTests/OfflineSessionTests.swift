import Foundation
import Testing
@testable import KeineMagieCore

@MainActor @Test func coldStartRestoresOnlySecurelyBoundPreviousOwnerBeforeNetworkCompletes() async throws {
    var proof: SavedNativeIdentity?
    let first = SessionController(serverURL: "https://example.com", readToken: { "synthetic" }, saveToken: { _ in }, readIdentity: { proof }, saveIdentity: { proof = $0 }) { _ in
        AuthResponse(data: Data(#"{"user":{"id":"owner-A"},"expires_at":"2099-01-01T00:00:00Z"}"#.utf8), status: 200)
    }
    await first.restore()
    #expect(proof != nil)
    let gate = OfflineValidationGate()
    let next = SessionController(serverURL: "https://example.com", readToken: { "synthetic" }, saveToken: { _ in }, readIdentity: { proof }, saveIdentity: { proof = $0 }) { request in
        if request.url?.path.hasSuffix("logout") == true { throw URLError(.notConnectedToInternet) }
        return try await gate.send()
    }
    let task = Task { await next.restore() }
    while !(await gate.ready()) { await Task.yield() }
    #expect(next.phase == .signedIn)
    #expect(next.user?.id == "owner-A")
    #expect(!next.canWrite)
    await gate.fail(); await task.value
    #expect(next.isOffline)
    #expect(next.user?.id == "owner-A")
    #expect(proof != nil)
    await next.logout()
    #expect(proof == nil)
    #expect(next.user == nil)
}
@MainActor @Test func wrongTokenOrOriginAndUnverifiedFirstLaunchNeverUnlockSavedOwner() async throws {
    let user = try JSONDecoder().decode(SessionUser.self, from: Data(#"{"id":"owner-A"}"#.utf8))
    let proof = SavedNativeIdentity(server: "https://example.com", user: user, token: "original")
    for (server, token, saved) in [("https://example.com", "other", Optional(proof)), ("https://other.example", "original", Optional(proof)), ("https://example.com", "original", nil)] {
        let session = SessionController(serverURL: server, readToken: { token }, saveToken: { _ in }, readIdentity: { saved }, saveIdentity: { _ in }) { _ in throw URLError(.notConnectedToInternet) }
        await session.restore()
        #expect(session.user == nil)
        #expect(session.phase == .offline)
        #expect(!session.canWrite)
    }
}
@MainActor @Test func expiredPreviouslyVerifiedTokenRemainsReadOnlyOfflineButServer401ErasesProof() async throws {
    let user = try JSONDecoder().decode(SessionUser.self, from: Data(#"{"id":"owner-A"}"#.utf8))
    var proof: SavedNativeIdentity? = SavedNativeIdentity(server: "https://example.com", user: user, token: "expired-synthetic")
    var token = "expired-synthetic"
    let offline = SessionController(serverURL: "https://example.com", readToken: { token }, saveToken: { token = $0 }, readIdentity: { proof }, saveIdentity: { proof = $0 }) { _ in throw URLError(.timedOut) }
    await offline.restore()
    #expect(offline.user?.id == "owner-A")
    #expect(!offline.canWrite)
    let rejected = SessionController(serverURL: "https://example.com", readToken: { token }, saveToken: { token = $0 }, readIdentity: { proof }, saveIdentity: { proof = $0 }) { _ in AuthResponse(data: Data(), status: 401) }
    await rejected.restore()
    #expect(rejected.user == nil)
    #expect(proof == nil)
    #expect(token.isEmpty)
}
@MainActor @Test func ownerReplacementProofWriteFailureCannotResumePreviousOwnerWrites() async throws {
    var fail = false
    let gate = OwnerProofGate()
    let session = SessionController(serverURL: "https://example.com", readToken: { "synthetic" }, saveToken: { _ in }, readIdentity: { nil }, saveIdentity: { _ in if fail { throw URLError(.cannotWriteToFile) } }) { _ in await gate.send() }
    await session.restore()
    #expect(session.canWrite)
    fail = true
    await gate.replace()
    await session.restore()
    #expect(session.user == nil)
    #expect(!session.canWrite)
}
@MainActor @Test func logoutProofDeletionFailureStillAttemptsBearerDeletionAndRevocation() async {
    var token = "synthetic"
    let gate = LogoutCounter()
    let session = SessionController(serverURL: "https://example.com", readToken: { token }, saveToken: { token = $0 }, readIdentity: { nil }, saveIdentity: { _ in throw URLError(.cannotWriteToFile) }) { _ in await gate.send() }
    await session.logout()
    #expect(token.isEmpty)
    #expect(await gate.calls == 1)
    #expect(session.user == nil)
}
private actor LogoutCounter {
    var calls = 0
    func send() -> AuthResponse { calls += 1; return AuthResponse(data: Data(), status: 204) }
}
private actor OwnerProofGate {
    var owner = "A"
    func replace() { owner = "B" }
    func send() -> AuthResponse { AuthResponse(data: Data("{\"user\":{\"id\":\"\(owner)\"},\"expires_at\":\"2099-01-01T00:00:00Z\"}".utf8), status: 200) }
}
private actor OfflineValidationGate {
    var continuation: CheckedContinuation<AuthResponse, Error>?
    func ready() -> Bool { continuation != nil }
    func send() async throws -> AuthResponse { try await withCheckedThrowingContinuation { continuation = $0 } }
    func fail() { continuation?.resume(throwing: URLError(.timedOut)); continuation = nil }
}
