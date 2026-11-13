import Foundation
import Observation
import CryptoKit

/// Persist only through a device-only Keychain adapter. Never infer identity from disk caches or JWT claims.
public struct SavedNativeIdentity: Codable, Sendable {
    public let server: String
    public let user: SessionUser
    public let tokenDigest: String
    public let verifiedAt: Date
    public init(server: String, user: SessionUser, token: String) {
        self.server = server; self.user = user; self.verifiedAt = Date()
        self.tokenDigest = Self.digest(token)
    }
    public func matches(server: String, token: String) -> Bool {
        self.server == server && !user.id.isEmpty && !token.isEmpty && verifiedAt <= Date() && tokenDigest == Self.digest(token)
    }
    private static func digest(_ token: String) -> String { SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined() }
}

/// Session policy shared by the UI and CLT tests; credentials never enter preferences.
@MainActor @Observable
public final class SessionController {
    public enum Phase: Equatable { case signedOut, restoring, offline, preparing, authorizing, exchanging, signedIn, loggingOut }
    public private(set) var phase: Phase = .signedOut
    public private(set) var user: SessionUser?
    public private(set) var serverURL: String
    public private(set) var generation = 0
    public private(set) var message: String?
    public let providerAvailable = false
    private let readToken: () throws -> String
    private let saveToken: (String) throws -> Void
    private let transport: AuthClient.Transport
    private let allowLocalHTTP: Bool
    private let readIdentity: () throws -> SavedNativeIdentity?
    private let saveIdentity: (SavedNativeIdentity?) throws -> Void
    public private(set) var isOffline = false
    public private(set) var checking = false
    private var verifiedOnline = false
    /// Successful server identity validation grants automatic outbox work.
    /// Advisory endpoint failures/checks do not revoke it; 401/logout do.
    public private(set) var translationOwnerValidated = false
    public var canWrite: Bool { phase == .signedIn && verifiedOnline && !isOffline && !checking }
    public convenience init(serverURL: String, allowLocalHTTP: Bool = false, readToken: @escaping () throws -> String, saveToken: @escaping (String) throws -> Void, transport: @escaping AuthClient.Transport = AuthClient.network) {
        self.init(serverURL: serverURL, allowLocalHTTP: allowLocalHTTP, readToken: readToken, saveToken: saveToken, readIdentity: { nil }, saveIdentity: { _ in }, transport: transport)
    }
    public init(serverURL: String, allowLocalHTTP: Bool = false, readToken: @escaping () throws -> String, saveToken: @escaping (String) throws -> Void, readIdentity: @escaping () throws -> SavedNativeIdentity?, saveIdentity: @escaping (SavedNativeIdentity?) throws -> Void, transport: @escaping AuthClient.Transport = AuthClient.network) {
        self.serverURL = serverURL; self.allowLocalHTTP = allowLocalHTTP
        self.readToken = readToken; self.saveToken = saveToken; self.transport = transport
        self.readIdentity = readIdentity; self.saveIdentity = saveIdentity
    }
    public struct LoginAttempt: Sendable { public let challenge: AppleChallenge; fileprivate let generation: Int }
    public func prepareLogin() async -> LoginAttempt? {
        guard phase == .signedOut else { return nil }
        generation += 1
        let version = generation
        phase = .preparing; message = nil
        do {
            let challenge = try await client().challenge()
            guard version == generation else { return nil }
            guard !challenge.nonce.isEmpty, !challenge.state.isEmpty, !challenge.challengeID.isEmpty else { throw AuthError.invalidCredential }
            phase = .authorizing
            return LoginAttempt(challenge: challenge, generation: version)
        } catch {
            guard version == generation else { return nil }
            phase = .signedOut; message = loginMessage(error); return nil
        }
    }
    public func completeLogin(attempt: LoginAttempt, identityToken: String, state: String?) async {
        guard attempt.generation == generation, phase == .authorizing else { return }
        phase = .exchanging
        do {
            let session = try await client().signIn(challenge: attempt.challenge, identityToken: identityToken, returnedState: state)
            guard attempt.generation == generation else { return }
            guard session.expiresAt > Date(), !session.sessionToken.isEmpty, !session.user.id.isEmpty else { throw AuthError.invalidCredential }
            try saveToken(session.sessionToken)
            try saveIdentity(SavedNativeIdentity(server: serverURL, user: session.user, token: session.sessionToken))
            translationOwnerValidated = true
            verifiedOnline = true; isOffline = false
            user = session.user; phase = .signedIn
        } catch {
            guard attempt.generation == generation else { return }
            user = nil; phase = .signedOut; message = loginMessage(error)
        }
    }
    private func loginMessage(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .http(401), .http(403): return CoreL10n.text("login.denied")
            case .http(let status): return CoreL10n.text("login.http", status)
            default: break
            }
        }
        if error is URLError { return CoreL10n.text("login.network") }
        if error is DecodingError { return CoreL10n.text("login.format") }
        return error.localizedDescription
    }
    public func failLogin(attempt: LoginAttempt, cancelled: Bool) {
        guard attempt.generation == generation, phase == .authorizing else { return }
        generation += 1; user = nil; phase = .signedOut
        message = cancelled ? CoreL10n.text("login.cancelled") : CoreL10n.text("login.failed")
    }
    public func cancelLogin() {
        generation += 1; user = nil; phase = .signedOut; message = CoreL10n.text("login.cancelled")
    }
    public func switchServer(_ url: String) throws {
        let endpoint = try ServerEndpoint(url, allowLocalHTTP: allowLocalHTTP)
        guard endpoint.baseURL.absoluteString != serverURL else { return }
        try saveIdentity(nil)
        try saveToken("")
        generation += 1; user = nil; phase = .signedOut; message = nil
        translationOwnerValidated = false
        serverURL = endpoint.baseURL.absoluteString
    }
    public func logout() async {
        translationOwnerValidated = false
        generation += 1
        verifiedOnline = false; isOffline = false
        let tokenForRevocation = try? readToken()
        var identityDeletionFailed = false
        do { try saveIdentity(nil) } catch { identityDeletionFailed = true }
        let version = generation
        user = nil; phase = .loggingOut; message = nil
        var revocationFailed = false
        do {
            let token = tokenForRevocation ?? ""
            if !token.isEmpty { try await client().logout(token: token) }
        } catch APIError.http(401) { /* Already expired/revoked. */ }
        catch { revocationFailed = true }
        guard version == generation else { return }
        do {
            try saveToken(""); phase = .signedOut
            if identityDeletionFailed { message = CoreL10n.text("session.keychain") }
            else if revocationFailed { message = CoreL10n.text("session.revocation") }
        } catch { phase = .offline; message = CoreL10n.text("session.keychain") }
    }
    private func client() throws -> AuthClient { AuthClient(endpoint: try ServerEndpoint(serverURL, allowLocalHTTP: allowLocalHTTP), transport: transport) }
    private func invalidateCredential() {
        translationOwnerValidated = false
        // Fail closed before touching Keychain: deletion can fail independently.
        generation += 1; user = nil
        verifiedOnline = false; isOffline = false
        do { try saveIdentity(nil); try saveToken(""); phase = .signedOut; message = CoreL10n.text("session.expired") }
        catch { phase = .offline; message = CoreL10n.text("session.keychain") }
    }
    private var validationID: UUID?
    public func restore() async {
        guard validationID == nil, [.signedOut, .offline, .signedIn].contains(phase) else { return }
        let id = UUID()
        validationID = id
        checking = true
        defer { if validationID == id { validationID = nil; checking = false } }
        let preservesContent = phase == .signedIn && user != nil
        if !preservesContent { generation += 1 }
        let version = generation
        if !preservesContent { phase = .restoring; user = nil }
        message = nil
        do {
            let token = try readToken()
            guard !token.isEmpty else {
                user = nil; phase = .signedOut
                if preservesContent { generation += 1 }
                return
            }
            guard !token.contains(where: { $0.isWhitespace || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }) else { throw AuthError.invalidCredential }
            if !preservesContent, let saved = try readIdentity(), saved.matches(server: serverURL, token: token) {
                user = saved.user; phase = .signedIn; verifiedOnline = false
            }
            let session = try await client().session(token: token)
            guard version == generation else { return }
            guard session.expiresAt > Date(), !session.user.id.isEmpty else { throw APIError.http(401) }
            // Silent validation preserves content only for the same account. Root's
            // generation observer clears content; pending API work rejects this epoch.
            let ownerChanged = user.map { $0.id != session.user.id } ?? false
            do { try saveIdentity(SavedNativeIdentity(server: serverURL, user: session.user, token: token)) }
            catch {
                if ownerChanged { invalidateCredential(); return }
                throw error
            }
            if ownerChanged { generation += 1 }
            translationOwnerValidated = true
            verifiedOnline = true; isOffline = false
            user = session.user; phase = .signedIn
        } catch APIError.http(401) {
            guard version == generation else { return }
            invalidateCredential()
        } catch AuthError.invalidCredential {
            guard version == generation else { return }
            invalidateCredential()
        } catch {
            guard version == generation else { return }
            if user == nil { phase = .offline }
            if error is URLError { isOffline = true }
            verifiedOnline = false
            message = CoreL10n.text("session.offline")
        }
    }
    public func recordNetworkFailure(_ error: Error) {
        guard error is URLError, phase == .signedIn else { return }
        isOffline = true; verifiedOnline = false
    }
    public func rejectUnauthorized() { invalidateCredential() }
}
