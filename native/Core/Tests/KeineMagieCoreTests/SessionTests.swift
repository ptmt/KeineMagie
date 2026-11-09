import Foundation
import Testing
@testable import KeineMagieCore

@MainActor @Test func restoreRequiresServerValidationAnd401ClearsCredentialButOfflineRetainsIt() async throws {
    for status in [200, 401, 0] {
        var token = "saved-session"
        let controller = SessionController(serverURL: "https://example.com", readToken: { token }, saveToken: { token = $0 }) { request in
            #expect(request.url?.path == "/v1/auth/session")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer saved-session")
            if status == 0 { throw URLError(.notConnectedToInternet) }
            return AuthResponse(data: Data(#"{"user":{"id":"u"},"expires_at":"2099-12-01T12:00:00Z"}"#.utf8), status: status)
        }
        await controller.restore()
        #expect(controller.phase == (status == 200 ? .signedIn : status == 401 ? .signedOut : .offline))
        #expect(token == (status == 401 ? "" : "saved-session"))
        #expect((controller.user != nil) == (status == 200))
        #expect(!controller.providerAvailable)
    }
}

@MainActor @Test func loginPersistsOnlyRealSessionAndCancellationReturnsSignedOut() async throws {
    var stored = ""
    let controller = SessionController(serverURL: "https://example.com", readToken: { stored }, saveToken: { stored = $0 }) { request in
        if request.url?.path.hasSuffix("challenge") == true {
            return AuthResponse(data: Data(#"{"challenge_id":"c","nonce":"raw","state":"s"}"#.utf8), status: 200)
        }
        return AuthResponse(data: Data(#"{"session_token":"session","user":{"id":"u"},"expires_at":"2099-12-01T12:00:00Z"}"#.utf8), status: 200)
    }
    let attempt = try #require(await controller.prepareLogin())
    #expect(attempt.challenge.nonce == "raw")
    #expect(controller.phase == .authorizing)
    #expect(stored.isEmpty)
    await controller.completeLogin(attempt: attempt, identityToken: "identity", state: "s")
    #expect(stored == "session")
    #expect(controller.phase == .signedIn)
    let other = SessionController(serverURL: "https://example.com", readToken: { "" }, saveToken: { _ in })
    other.cancelLogin()
    #expect(other.phase == .signedOut)
    #expect(other.message == CoreL10n.text("login.cancelled"))
}

private actor SuspendedAuth {
    var continuation: CheckedContinuation<AuthResponse, Never>?
    func send(_ request: URLRequest) async -> AuthResponse { await withCheckedContinuation { continuation = $0 } }
    func ready() -> Bool { continuation != nil }
    func finish(_ json: String) { continuation?.resume(returning: AuthResponse(data: Data(json.utf8), status: 200)); continuation = nil }
}

@MainActor @Test func serverSwitchRejectsLateLoginAndClearsCredential() async throws {
    let pending = SuspendedAuth()
    var stored = ""
    let controller = SessionController(serverURL: "https://old.example", readToken: { stored }, saveToken: { stored = $0 }) { request in
        if request.url?.path.hasSuffix("challenge") == true { return AuthResponse(data: Data(#"{"challenge_id":"c","nonce":"n","state":"s"}"#.utf8), status: 200) }
        return await pending.send(request)
    }
    let attempt = try #require(await controller.prepareLogin())
    let task = Task { await controller.completeLogin(attempt: attempt, identityToken: "identity", state: "s") }
    while !(await pending.ready()) { await Task.yield() }
    try controller.switchServer("https://new.example")
    await pending.finish(#"{"session_token":"late","user":{"id":"u"},"expires_at":"2099-12-01T12:00:00Z"}"#)
    await task.value
    #expect(stored.isEmpty)
    #expect(controller.phase == .signedOut)
    #expect(controller.user == nil)
    #expect(controller.serverURL == "https://new.example")
}

@MainActor @Test func logoutRevokesBeforeLocalClearAndExplainsFailure() async throws {
    for status in [204, 503] {
        var stored = "session"
        let controller = SessionController(serverURL: "https://example.com", readToken: { stored }, saveToken: { stored = $0 }) { request in
            #expect(request.url?.path == "/v1/auth/logout")
            #expect(request.httpMethod == "POST")
            return AuthResponse(data: Data(), status: status)
        }
        await controller.logout()
        #expect(stored.isEmpty)
        #expect(controller.phase == .signedOut)
        if status == 503 { #expect(controller.message == CoreL10n.text("session.revocation")) }
    }
}

@MainActor @Test func oldAppleCancellationCannotCancelNewConfiguration() async throws {
    let controller = SessionController(serverURL: "https://example.com", readToken: { "" }, saveToken: { _ in }) { _ in
        AuthResponse(data: Data(#"{"challenge_id":"c","nonce":"n","state":"s"}"#.utf8), status: 200)
    }
    let oldAttempt = try #require(await controller.prepareLogin())
    try controller.switchServer("https://new.example")
    _ = await controller.prepareLogin()
    controller.failLogin(attempt: oldAttempt, cancelled: true)
    #expect(controller.phase == .authorizing)
    #expect(controller.message == nil)
}

@MainActor @Test func logoutInvalidatesPendingExchangeBeforeCredentialCanPersist() async throws {
    let pending = SuspendedAuth()
    var stored = ""
    let controller = SessionController(serverURL: "https://example.com", readToken: { stored }, saveToken: { stored = $0 }) { request in
        if request.url?.path.hasSuffix("challenge") == true { return AuthResponse(data: Data(#"{"challenge_id":"c","nonce":"n","state":"s"}"#.utf8), status: 200) }
        return await pending.send(request)
    }
    let attempt = try #require(await controller.prepareLogin())
    let task = Task { await controller.completeLogin(attempt: attempt, identityToken: "identity", state: "s") }
    while !(await pending.ready()) { await Task.yield() }
    await controller.logout()
    await pending.finish(#"{"session_token":"late","user":{"id":"u"},"expires_at":"2099-12-01T12:00:00Z"}"#)
    await task.value
    #expect(stored.isEmpty)
    #expect(controller.phase == .signedOut)
    #expect(controller.user == nil)
}

@MainActor @Test func logoutDoesNotEraseCredentialBeforeServerResponds() async throws {
    let pending = SuspendedAuth()
    var stored = "session"
    let controller = SessionController(serverURL: "https://example.com", readToken: { stored }, saveToken: { stored = $0 }) { request in await pending.send(request) }
    let task = Task { await controller.logout() }
    while !(await pending.ready()) { await Task.yield() }
    #expect(stored == "session")
    #expect(controller.phase == .loggingOut)
    await pending.finish("")
    await task.value
    #expect(stored.isEmpty)
}

@MainActor @Test func loginServerRejectionDoesNotSuggestManualTokenSettings() async throws {
    let controller = SessionController(serverURL: "https://example.com", readToken: { "" }, saveToken: { _ in }) { _ in
        AuthResponse(data: Data(), status: 401)
    }
    #expect(await controller.prepareLogin() == nil)
    #expect(controller.phase == .signedOut)
    #expect(controller.message?.contains("Server-Token") == false)
    #expect(controller.message == CoreL10n.text("login.denied"))
}

@MainActor @Test func signedOutStartupNeverRequestsHistoryOrAnyNetwork() async throws {
    let controller = SessionController(serverURL: "https://example.com", readToken: { "" }, saveToken: { _ in }) { _ in
        Issue.record("Signed-out startup made network request")
        throw URLError(.badURL)
    }
    await controller.restore()
    #expect(controller.phase == .signedOut)
    #expect(controller.user == nil)
    #expect(!controller.providerAvailable)
}
