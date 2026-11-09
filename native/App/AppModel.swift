import SwiftUI
import KeineMagieCore

@MainActor @Observable
final class AppModel {
    let session: SessionController
    private(set) var input = ""
    private(set) var result: TranslationRecord?
    private(set) var history: [TranslationRecord] = []
    var draft = ""
    var source: Language = .german
    private(set) var provider: ProviderStatus?
    private(set) var bootstrap: ProviderBootstrap?
    private(set) var busy = false
    private(set) var translatorError: String?

    func api() throws -> APIClient {
        guard session.phase == .signedIn else { throw APIError.http(401) }
        return APIClient(endpoint: try ServerEndpoint(session.serverURL, allowLocalHTTP: Self.allowLocalHTTP), token: try TokenStore.read())
    }
    func refreshTranslator() async {
        let version = session.generation
        do {
            let client = try api()
            let items = try await client.history()
            let status = try await client.provider()
            guard session.phase == .signedIn, version == session.generation else { return }
            history = items; provider = status; translatorError = nil
            if status.connected { bootstrap = nil }
        } catch { if version == session.generation { translatorError = error.localizedDescription } }
    }
    func connectChatGPT() async {
        let version = session.generation
        busy = true; defer { busy = false }
        do {
            let code = try await api().connectProvider()
            guard version == session.generation, session.phase == .signedIn else { return }
            bootstrap = code; translatorError = nil
        } catch { if version == session.generation { translatorError = error.localizedDescription } }
    }
    func disconnectChatGPT() async {
        let version = session.generation
        busy = true; defer { busy = false }
        do { try await api().disconnectProvider(); guard version == session.generation else { return }; bootstrap = nil; provider = nil; await refreshTranslator() }
        catch { if version == session.generation { translatorError = error.localizedDescription } }
    }
    func translate() async {
        let version = session.generation
        busy = true; defer { busy = false }
        do {
            let item = try await api().translate(text: draft, source: source)
            guard version == session.generation, session.phase == .signedIn else { return }
            result = item; history.insert(item, at: 0); translatorError = nil
        } catch { if version == session.generation { translatorError = error.localizedDescription } }
    }

    init() {
        let url = UserDefaults.standard.string(forKey: "serverURL") ?? ProductIdentity.defaultServerURL
        session = SessionController(serverURL: url, allowLocalHTTP: Self.allowLocalHTTP,
                                    readToken: { try TokenStore.read() }, saveToken: { try TokenStore.save($0) })
    }
    static var allowLocalHTTP: Bool {
        #if DEBUG && targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    func resetSessionContent() {
        input = ""
        result = nil
        history = []
        draft = ""; provider = nil; bootstrap = nil; translatorError = nil; busy = false
    }
    func saveServer(url: String) async throws {
        let endpoint = try ServerEndpoint(url, allowLocalHTTP: Self.allowLocalHTTP)
        guard endpoint.baseURL.absoluteString != session.serverURL else { return }
        // Revoke against the OLD server before changing origin. Offline failure is reported, not hidden.
        await session.logout()
        guard session.phase == .signedOut else { throw SettingsFailure.keychain }
        let warning = session.message
        try session.switchServer(endpoint.baseURL.absoluteString)
        UserDefaults.standard.set(session.serverURL, forKey: "serverURL")
        resetSessionContent()
        if warning != nil { throw SettingsFailure.revocation }
    }
    func logout() async {
        resetSessionContent()
        await session.logout()
    }
}
private enum SettingsFailure: LocalizedError {
    case keychain, revocation
    var errorDescription: String? {
        switch self {
        case .keychain: AppL10n.text("settings.keychain")
        case .revocation: AppL10n.text("settings.revocation")
        }
    }
}
