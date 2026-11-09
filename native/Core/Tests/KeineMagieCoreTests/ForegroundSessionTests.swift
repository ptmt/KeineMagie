import Foundation
import Testing
@testable import KeineMagieCore

private actor ValidationGate {
    private var continuation: CheckedContinuation<AuthResponse, Error>?
    private var calls = 0
    func send() async throws -> AuthResponse {
        calls += 1
        if calls == 1 { return validSession() }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func ready() -> Bool { continuation != nil }
    func finish(status: Int, userID: String = "fixture-user") {
        let data = Data("{\"user\":{\"id\":\"\(userID)\"},\"expires_at\":\"2099-12-01T12:00:00Z\"}".utf8)
        continuation?.resume(returning: AuthResponse(data: data, status: status)); continuation = nil
    }
    func fail() { continuation?.resume(throwing: URLError(.notConnectedToInternet)); continuation = nil }
    func count() -> Int { calls }
}
private func validSession() -> AuthResponse {
    AuthResponse(data: Data(#"{"user":{"id":"fixture-user"},"expires_at":"2099-12-01T12:00:00Z"}"#.utf8), status: 200)
}

@MainActor @Test func foregroundValidationPreservesTranslatorIdentityAndGeneration() async throws {
    let gate = ValidationGate()
    let session = SessionController(serverURL: "https://example.com", readToken: { "synthetic-session" }, saveToken: { _ in }) { _ in try await gate.send() }
    await session.restore()
    let generation = session.generation
    let refresh = Task { await session.restore() }
    while !(await gate.ready()) { await Task.yield() }
    #expect(session.phase == .signedIn, "Foreground validation must not replace the translator with the login loader")
    #expect(session.user?.id == "fixture-user")
    #expect(session.generation == generation, "Foreground validation must not clear drafts, history or provider state")
    await gate.finish(status: 200)
    await refresh.value
    #expect(session.phase == .signedIn)
    #expect(session.generation == generation)
}

@MainActor @Test func foregroundAccountChangeInvalidatesPreviousContentGeneration() async {
    let gate = ValidationGate()
    let session = SessionController(serverURL: "https://example.com", readToken: { "synthetic-session" }, saveToken: { _ in }) { _ in try await gate.send() }
    await session.restore()
    let previousGeneration = session.generation
    let refresh = Task { await session.restore() }
    while !(await gate.ready()) { await Task.yield() }
    await gate.finish(status: 200, userID: "other-account")
    await refresh.value
    #expect(session.phase == .signedIn)
    #expect(session.user?.id == "other-account")
    #expect(session.generation > previousGeneration, "Old draft/history/provider and pending work must be invalidated even without a phase transition")
}

@MainActor @Test func foregroundTransientFailureRetainsValidatedSessionAndCredential() async {
    let gate = ValidationGate()
    var stored = "synthetic-session"
    let session = SessionController(serverURL: "https://example.com", readToken: { stored }, saveToken: { stored = $0 }) { _ in try await gate.send() }
    await session.restore()
    let generation = session.generation
    let refresh = Task { await session.restore() }
    while !(await gate.ready()) { await Task.yield() }
    await gate.fail()
    await refresh.value
    #expect(session.phase == .signedIn)
    #expect(session.user?.id == "fixture-user")
    #expect(stored == "synthetic-session")
    #expect(session.generation == generation)
}

@MainActor @Test func foreground401ClearsIdentityAndCredentialEvenIfKeychainDeletionFails() async {
    for deletionFails in [false, true] {
        let gate = ValidationGate()
        var stored = "synthetic-session"
        let session = SessionController(serverURL: "https://example.com", readToken: { stored }, saveToken: {
            if deletionFails { throw URLError(.cannotWriteToFile) }
            stored = $0
        }) { _ in try await gate.send() }
        await session.restore()
        let generation = session.generation
        let refresh = Task { await session.restore() }
        while !(await gate.ready()) { await Task.yield() }
        await gate.finish(status: 401)
        await refresh.value
        #expect(session.phase != .signedIn)
        #expect(session.user == nil)
        #expect(session.generation > generation)
        #expect(stored == (deletionFails ? "synthetic-session" : ""))
    }
}

@MainActor @Test func foregroundMalformedCredentialFailsClosedEvenIfDeletionFails() async {
    for deletionFails in [false, true] {
        var stored = "synthetic-session"
        var deletionAttempts = 0
        let session = SessionController(serverURL: "https://example.com", readToken: { stored }, saveToken: {
            deletionAttempts += 1
            if deletionFails { throw URLError(.cannotWriteToFile) }
            stored = $0
        }) { _ in validSession() }
        await session.restore()
        let generation = session.generation
        stored = "invalid credential\n"
        await session.restore()
        #expect(session.user == nil)
        #expect(session.phase == (deletionFails ? .offline : .signedOut))
        #expect(session.generation > generation)
        #expect(deletionAttempts == 1)
        #expect(stored == (deletionFails ? "invalid credential\n" : ""))
        #expect(session.message != CoreL10n.text("session.offline"), "A definitively invalid credential is not a transient network failure")
    }
}

@MainActor @Test func simultaneousForegroundEventsCoalesceValidation() async {
    let gate = ValidationGate()
    let session = SessionController(serverURL: "https://example.com", readToken: { "synthetic-session" }, saveToken: { _ in }) { _ in try await gate.send() }
    await session.restore()
    let refresh = Task { await session.restore() }
    while !(await gate.ready()) { await Task.yield() }
    await session.restore()
    #expect(await gate.count() == 2)
    await gate.finish(status: 200)
    await refresh.value
}

@MainActor @Test func serverSwitchDuringBackgroundValidationRejectsLateResponse() async throws {
    let gate = ValidationGate()
    var stored = "synthetic-session"
    let session = SessionController(serverURL: "https://example.com", readToken: { stored }, saveToken: { stored = $0 }) { _ in try await gate.send() }
    await session.restore()
    let refresh = Task { await session.restore() }
    while !(await gate.ready()) { await Task.yield() }
    try session.switchServer("https://other.example")
    await gate.finish(status: 200)
    await refresh.value
    #expect(session.phase == .signedOut)
    #expect(session.user == nil)
    #expect(stored.isEmpty)
}

