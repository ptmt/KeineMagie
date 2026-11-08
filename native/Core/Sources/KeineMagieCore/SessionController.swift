import Foundation
import Observation

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
    public init(serverURL: String, allowLocalHTTP: Bool = false, readToken: @escaping () throws -> String, saveToken: @escaping (String) throws -> Void, transport: @escaping AuthClient.Transport = AuthClient.network) {
        self.serverURL = serverURL; self.allowLocalHTTP = allowLocalHTTP
        self.readToken = readToken; self.saveToken = saveToken; self.transport = transport
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
            user = session.user; phase = .signedIn
        } catch {
            guard attempt.generation == generation else { return }
            user = nil; phase = .signedOut; message = loginMessage(error)
        }
    }
    private func loginMessage(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .http(401), .http(403): return "Anmeldung vom Server abgelehnt. Bitte erneut mit Apple anmelden."
            case .http(let status): return "Anmeldung derzeit nicht möglich (HTTP \(status)). Bitte später erneut versuchen."
            default: break
            }
        }
        if error is URLError { return "Anmeldung konnte den Server nicht erreichen. Bitte Verbindung und Server-URL prüfen." }
        if error is DecodingError { return "Anmeldung fehlgeschlagen: unerwartetes Serverformat." }
        return error.localizedDescription
    }
    public func failLogin(attempt: LoginAttempt, cancelled: Bool) {
        guard attempt.generation == generation, phase == .authorizing else { return }
        generation += 1; user = nil; phase = .signedOut
        message = cancelled ? "Apple-Anmeldung abgebrochen." : "Apple-Anmeldung fehlgeschlagen. Bitte erneut versuchen."
    }
    public func cancelLogin() {
        generation += 1; user = nil; phase = .signedOut; message = "Apple-Anmeldung abgebrochen."
    }
    public func switchServer(_ url: String) throws {
        let endpoint = try ServerEndpoint(url, allowLocalHTTP: allowLocalHTTP)
        guard endpoint.baseURL.absoluteString != serverURL else { return }
        try saveToken("")
        generation += 1; user = nil; phase = .signedOut; message = nil
        serverURL = endpoint.baseURL.absoluteString
    }
    public func logout() async {
        generation += 1
        let version = generation
        user = nil; phase = .loggingOut; message = nil
        var revocationFailed = false
        do {
            let token = try readToken()
            if !token.isEmpty { try await client().logout(token: token) }
        } catch APIError.http(401) { /* Already expired/revoked. */ }
        catch { revocationFailed = true }
        guard version == generation else { return }
        do {
            try saveToken(""); phase = .signedOut
            if revocationFailed { message = "Lokal abgemeldet. Server-Widerruf nicht bestätigt; die Sitzung könnte bis zum Ablauf weiter gültig sein." }
        } catch { phase = .offline; message = "Schlüsselbund konnte nicht geleert werden. Bitte Abmelden erneut versuchen." }
    }
    private func client() throws -> AuthClient { AuthClient(endpoint: try ServerEndpoint(serverURL, allowLocalHTTP: allowLocalHTTP), transport: transport) }
    public func restore() async {
        generation += 1
        let version = generation
        phase = .restoring; user = nil; message = nil
        do {
            let token = try readToken()
            guard !token.isEmpty else { phase = .signedOut; return }
            let session = try await client().session(token: token)
            guard version == generation else { return }
            guard session.expiresAt > Date(), !session.user.id.isEmpty else { throw APIError.http(401) }
            user = session.user; phase = .signedIn
        } catch APIError.http(401) {
            guard version == generation else { return }
            do { try saveToken(""); phase = .signedOut; message = "Sitzung abgelaufen. Bitte erneut anmelden." }
            catch { phase = .offline; message = error.localizedDescription }
        } catch {
            guard version == generation else { return }
            phase = .offline
            message = "Sitzung konnte nicht bestätigt werden. Keine Verbindung hergestellt. Bitte Verbindung und Server prüfen und erneut versuchen."
        }
    }
}
