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
    var chatGPTBrowser: ChatGPTBrowser?
    private var loopback: OAuthLoopback?
    private var connectionID: UUID?
    private let connectionTasks = ChatGPTConnectionTasks()
    private(set) var busy = false
    private(set) var translatorError: String?

    #if targetEnvironment(simulator)
    private var fixtureTransport: AuthClient.Transport?
    #endif
    func api() throws -> APIClient {
        guard session.phase == .signedIn else { throw APIError.http(401) }
        #if targetEnvironment(simulator)
        if let fixtureTransport {
            return APIClient(endpoint: try ServerEndpoint(session.serverURL), token: "synthetic-session-not-a-credential", transport: fixtureTransport)
        }
        #endif
        return APIClient(endpoint: try ServerEndpoint(session.serverURL, allowLocalHTTP: Self.allowLocalHTTP), token: try TokenStore.read())
    }
    func refreshTranslator(connection: UUID? = nil) async {
        let version = session.generation
        do {
            let client = try api()
            let items = try await client.history()
            guard !Task.isCancelled, version == session.generation, session.phase == .signedIn,
                  connection == nil || connectionID == connection else { return }
            let status = try await client.provider()
            guard !Task.isCancelled, session.phase == .signedIn, version == session.generation,
                  connection == nil || connectionID == connection else { return }
            history = items; provider = status; translatorError = nil
            if status.connected { bootstrap = nil }
        } catch {
            if !Task.isCancelled, session.phase == .signedIn, version == session.generation,
               connection == nil || connectionID == connection { translatorError = error.localizedDescription }
        }
    }
    func connectChatGPT() async {
        cancelChatGPT()
        let version = session.generation
        let id = UUID(); connectionID = id
        let local = OAuthLoopback(); loopback = local
        busy = true
        await connectionTasks.run { [self] in
        defer { if connectionID == id { cancelChatGPT() } }
        do {
            guard !Task.isCancelled, version == session.generation, connectionID == id, session.phase == .signedIn else { return }
            let client = try api()
            let redirect = try await local.start()
            guard !Task.isCancelled, version == session.generation, connectionID == id, session.phase == .signedIn else { return }
            let code = try await client.connectProvider()
            guard !Task.isCancelled, version == session.generation, connectionID == id, session.phase == .signedIn else { return }
            let raw = try await client.bootstrapStart(token: code.bootstrapToken, redirect: redirect)
            let auth = try LoopbackPolicy.authorize(raw, redirect: redirect)
            guard !Task.isCancelled, version == session.generation, connectionID == id, !local.isClosed, session.phase == .signedIn else { return }
            chatGPTBrowser = ChatGPTBrowser(url: auth.url)
            let callback = try await local.callback(state: auth.state)
            guard !Task.isCancelled, version == session.generation, connectionID == id, session.phase == .signedIn else { return }
            chatGPTBrowser = nil
            try await client.bootstrapComplete(token: code.bootstrapToken, callback: callback)
            guard !Task.isCancelled, version == session.generation, connectionID == id, session.phase == .signedIn else { return }
            translatorError = nil
            await refreshTranslator(connection: id)
        } catch {
            if !Task.isCancelled, session.phase == .signedIn, version == session.generation, connectionID == id {
                translatorError = AppL10n.text("chatgpt.failed")
            }
        }
        }
    }
    func cancelChatGPT() {
        connectionTasks.cancel()
        connectionID = nil; loopback?.cancel(); loopback = nil
        chatGPTBrowser = nil; busy = false
    }
    func disconnectChatGPT() async {
        cancelChatGPT()
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
        #if targetEnvironment(simulator)
        // Explicit simulator-only, in-memory fixture. Never reads/writes Keychain,
        // contacts a server, signs in with Apple, or claims a provider connection.
        if let mode = ProcessInfo.processInfo.environment["KM_SIMULATOR_SESSION_FIXTURE"] {
            let fixture = SimulatorSessionFixture(mode: mode)
            fixtureTransport = { request in try await fixture.send(request) }
            session = SessionController(serverURL: "https://fixture.invalid", readToken: { "synthetic-session-not-a-credential" }, saveToken: { _ in }, transport: { request in try await fixture.send(request) })
            return
        }
        #endif
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
        cancelChatGPT()
        input = ""
        result = nil
        history = []
        draft = ""; provider = nil; bootstrap = nil; translatorError = nil; busy = false
    }
    func saveServer(url: String) async throws {
        let endpoint = try ServerEndpoint(url, allowLocalHTTP: Self.allowLocalHTTP)
        guard endpoint.baseURL.absoluteString != session.serverURL else { return }
        cancelChatGPT()
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
