import Foundation

public struct APIClient: Sendable {
    public let endpoint: ServerEndpoint
    private let token: String
    public init(endpoint: ServerEndpoint, token: String) {
        self.endpoint = endpoint
        self.token = token
    }
    private func request(path: String, method: String) throws -> URLRequest {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !token.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }) else {
            throw APIError.missingToken
        }
        var request = URLRequest(url: endpoint.url(path: path))
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    public func browserPairingRequest(code: String) throws -> URLRequest {
        guard code.range(of: "^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$", options: .regularExpression) != nil else { throw APIError.invalidResponse }
        var result = try request(path: "v1/auth/browser/inspect", method: "POST")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.httpBody = try JSONEncoder().encode(["user_code": code])
        return result
    }
    public func browserApprovalRequest(approval: String, approve: Bool) throws -> URLRequest {
        var result = try request(path: "v1/auth/browser/approve", method: "POST")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.httpBody = try JSONSerialization.data(withJSONObject: ["approval_token": approval, "approve": approve])
        return result
    }
    public func inspectBrowser(code: String) async throws -> BrowserApproval {
        try JSONDecoder().decode(BrowserApproval.self, from: await send(browserPairingRequest(code: code)))
    }
    public func approveBrowser(approval: String, approve: Bool) async throws {
        _ = try await send(browserApprovalRequest(approval: approval, approve: approve))
    }
    public func providerRequest(action: String? = nil) throws -> URLRequest {
        guard action == nil || action == "connect" || action == "disconnect" else { throw APIError.invalidResponse }
        var result = try request(path: "v1/provider" + (action.map { "/" + $0 } ?? ""), method: action == nil ? "GET" : "POST")
        if action != nil { result.httpBody = Data("{}".utf8); result.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return result
    }
    public func provider() async throws -> ProviderStatus { try JSONDecoder().decode(ProviderStatus.self, from: await send(providerRequest())) }
    public func connectProvider() async throws -> ProviderBootstrap { try JSONDecoder().decode(ProviderBootstrap.self, from: await send(providerRequest(action: "connect"))) }
    public func disconnectProvider() async throws { _ = try await send(providerRequest(action: "disconnect")) }
    public func translationRequest(text: String, source: Language) throws -> URLRequest {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.emptyText }
        var result = try request(path: "v1/translations", method: "POST")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.httpBody = try JSONEncoder().encode(TranslationRequest(text: text, sourceLanguage: source))
        return result
    }
    public func historyRequest() throws -> URLRequest { try request(path: "v1/translations", method: "GET") }
    public func ttsRequest(text: String) throws -> URLRequest {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.emptyText }
        var result = try request(path: "tts", method: "POST")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        result.httpBody = try JSONEncoder().encode(TTSBody(text: text))
        return result
    }
    public func translate(text: String, source: Language) async throws -> TranslationRecord {
        try APIJSON.decoder().decode(TranslationRecord.self, from: await send(translationRequest(text: text, source: source)))
    }
    public func history() async throws -> [TranslationRecord] {
        try APIJSON.decoder().decode(TranslationHistory.self, from: await send(historyRequest())).items.sorted { $0.createdAt > $1.createdAt }
    }
    public func audio(text: String) async throws -> Data {
        try await send(ttsRequest(text: text))
    }
    private func send(_ request: URLRequest) async throws -> Data {
        // Never forward the shared bearer token through an HTTP redirect.
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw APIError.http(response.statusCode) }
        if response.statusCode == 204 { return data }
        guard !data.isEmpty else { throw APIError.invalidResponse }
        return data
    }
}
private struct TTSBody: Encodable {
    let text: String
    let language = "de-DE"
    let voice = "alloy"
    let model = "gpt-4o-mini-tts"
    let format = "mp3"
    let speed = 1.0
}
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public enum APIError: LocalizedError {
    case missingToken, emptyText, invalidResponse, http(Int)
    public var errorDescription: String? {
        switch self {
        case .missingToken: CoreL10n.text("api.token")
        case .emptyText: CoreL10n.text("api.empty")
        case .invalidResponse: CoreL10n.text("api.response")
        case .http(401), .http(403): CoreL10n.text("api.denied")
        case .http(let status): CoreL10n.text("api.http", status)
        }
    }
}
