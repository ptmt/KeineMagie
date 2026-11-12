import Foundation

public struct AppleChallenge: Decodable, Sendable {
    public let challengeID: String
    public let nonce: String
    public let state: String
    enum CodingKeys: String, CodingKey { case challengeID = "challenge_id", nonce, state }
}
public struct AuthResponse: Sendable {
    public let data: Data
    public let status: Int
    public init(data: Data, status: Int) { self.data = data; self.status = status }
}
public struct ValidatedSession: Decodable, Sendable {
    public let user: SessionUser
    public let expiresAt: Date
    enum CodingKeys: String, CodingKey { case user, expiresAt = "expires_at" }
}
public struct SessionUser: Codable, Sendable, Equatable { public let id: String }
public struct AppleSession: Decodable, Sendable {
    public let sessionToken: String
    public let user: SessionUser
    public let expiresAt: Date
    enum CodingKeys: String, CodingKey { case sessionToken = "session_token", user, expiresAt = "expires_at" }
}
public enum AuthError: LocalizedError, Equatable {
    case invalidCredential
    public var errorDescription: String? { CoreL10n.text("auth.invalid") }
}
public struct AuthClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> AuthResponse
    private let endpoint: ServerEndpoint
    private let transport: Transport
    public init(endpoint: ServerEndpoint, transport: @escaping Transport = AuthClient.network) {
        self.endpoint = endpoint
        self.transport = transport
    }
    public func challenge() async throws -> AppleChallenge {
        var request = URLRequest(url: endpoint.url(path: "v1/auth/apple/challenge"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let response = try await transport(request)
        guard (200..<300).contains(response.status) else { throw APIError.http(response.status) }
        return try JSONDecoder().decode(AppleChallenge.self, from: response.data)
    }
    public func signIn(challenge: AppleChallenge, identityToken: String, returnedState: String?) async throws -> AppleSession {
        guard !challenge.state.isEmpty, returnedState == challenge.state,
              !identityToken.isEmpty else { throw AuthError.invalidCredential }
        var request = URLRequest(url: endpoint.url(path: "v1/auth/apple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["challenge_id": challenge.challengeID, "identity_token": identityToken, "state": returnedState ?? ""])
        let response = try await transport(request)
        guard (200..<300).contains(response.status) else { throw APIError.http(response.status) }
        return try APIJSON.decoder().decode(AppleSession.self, from: response.data)
    }
    public func session(token: String) async throws -> ValidatedSession {
        let response = try await authenticated(path: "v1/auth/session", method: "GET", token: token)
        return try APIJSON.decoder().decode(ValidatedSession.self, from: response.data)
    }
    public func logout(token: String) async throws {
        _ = try await authenticated(path: "v1/auth/logout", method: "POST", token: token)
    }
    private func authenticated(path: String, method: String, token: String) async throws -> AuthResponse {
        guard !token.isEmpty, !token.contains(where: { $0.isWhitespace || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }) else { throw AuthError.invalidCredential }
        var request = URLRequest(url: endpoint.url(path: path))
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try await transport(request)
        guard (200..<300).contains(response.status) else { throw APIError.http(response.status) }
        return response
    }
    public static func network(_ request: URLRequest) async throws -> AuthResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: AuthNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return AuthResponse(data: data, status: http.statusCode)
    }
}
private final class AuthNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
