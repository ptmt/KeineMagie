import Foundation
import Testing
@testable import KeineMagieCore

@Test func appleExchangeSendsOnlyIdentityTokenChallengeAndMatchingState() async throws {
    let api = AuthClient(endpoint: try ServerEndpoint("https://example.com")) { request in
        #expect(request.url?.path == "/v1/auth/apple")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: String]
        #expect(body == ["challenge_id": "c", "identity_token": "real-identity-token", "state": "s"])
        return AuthResponse(data: Data(#"{"session_token":"session","user":{"id":"u"},"expires_at":"2026-12-01T12:00:00.123Z"}"#.utf8), status: 200)
    }
    let challenge = try JSONDecoder().decode(AppleChallenge.self, from: Data(#"{"challenge_id":"c","nonce":"n","state":"s"}"#.utf8))
    let session = try await api.signIn(challenge: challenge, identityToken: "real-identity-token", returnedState: "s")
    #expect(session.sessionToken == "session")
    #expect(session.user.id == "u")
    #expect(session.expiresAt.timeIntervalSince1970 > 0)
}

@Test func mismatchedOrMissingStateAndEmptyCredentialNeverReachTransport() async throws {
    let api = AuthClient(endpoint: try ServerEndpoint("https://example.com")) { _ in
        Issue.record("Unsafe Apple exchange reached network")
        throw APIError.invalidResponse
    }
    let challenge = try JSONDecoder().decode(AppleChallenge.self, from: Data(#"{"challenge_id":"c","nonce":"n","state":"s"}"#.utf8))
    for state in [nil, "", "different"] as [String?] {
        do { _ = try await api.signIn(challenge: challenge, identityToken: "token", returnedState: state); Issue.record("Accepted invalid state") }
        catch { #expect(error as? AuthError == .invalidCredential) }
    }
    do { _ = try await api.signIn(challenge: challenge, identityToken: "", returnedState: "s"); Issue.record("Accepted empty token") }
    catch { #expect(error as? AuthError == .invalidCredential) }
}

@Test func validatesSessionWithBearerAndRevokesWithEmpty204() async throws {
    let api = AuthClient(endpoint: try ServerEndpoint("https://example.com")) { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer session")
        if request.httpMethod == "GET" {
            #expect(request.url?.path == "/v1/auth/session")
            return AuthResponse(data: Data(#"{"user":{"id":"u"},"expires_at":"2026-12-01T12:00:00Z"}"#.utf8), status: 200)
        }
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/auth/logout")
        return AuthResponse(data: Data(), status: 204)
    }
    let session = try await api.session(token: "session")
    #expect(session.user.id == "u")
    try await api.logout(token: "session")
}

@Test func challengeIsUnauthenticatedAndPreservesNonceAndState() async throws {
    let api = AuthClient(endpoint: try ServerEndpoint("https://example.com/base")) { request in
        #expect(request.url?.path == "/base/v1/auth/apple/challenge")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: String]
        #expect(body == [:])
        return AuthResponse(data: Data(#"{"challenge_id":"c","nonce":"raw-nonce","state":"server-state"}"#.utf8), status: 200)
    }
    let challenge = try await api.challenge()
    #expect(challenge.challengeID == "c")
    #expect(challenge.nonce == "raw-nonce")
    #expect(challenge.state == "server-state")
}
