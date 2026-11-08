import SwiftUI
import KeineMagieCore

@MainActor @Observable
final class AppModel {
    let session: SessionController
    private(set) var input = ""
    private(set) var result: TranslationRecord?
    private(set) var history: [TranslationRecord] = []

    init() {
        let url = UserDefaults.standard.string(forKey: "serverURL") ?? "https://keinemagie.tinyserve.org"
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
        // No audio player or provider requests exist until account-scoped provider support is implemented.
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
        case .keychain: "Server nicht gewechselt: Schlüsselbund konnte nicht geleert werden. Bitte erneut abmelden."
        case .revocation: "Server gewechselt und lokal abgemeldet. Widerruf beim bisherigen Server nicht bestätigt; die alte Sitzung könnte bis zum Ablauf gültig sein."
        }
    }
}
