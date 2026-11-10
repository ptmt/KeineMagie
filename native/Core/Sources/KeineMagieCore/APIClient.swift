import Foundation

public struct APIClient: Sendable {
    public let endpoint: ServerEndpoint
    private let token: String
    private let transport: AuthClient.Transport
    public init(endpoint: ServerEndpoint, token: String, transport: @escaping AuthClient.Transport = AuthClient.network) {
        self.endpoint = endpoint
        self.token = token
        self.transport = transport
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
    public func bootstrapRequest(token bootstrapToken: String, redirect: URL? = nil, callback: URL? = nil) throws -> URLRequest {
        guard !bootstrapToken.isEmpty, (redirect != nil) != (callback != nil) else { throw APIError.invalidResponse }
        var result = try request(path: "v1/provider/bootstrap/" + (redirect == nil ? "complete" : "start"), method: "POST")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = ["bootstrap_token": bootstrapToken]
        if let redirect { body["redirect_uri"] = redirect.absoluteString }
        if let callback { body["callback_url"] = callback.absoluteString }
        result.httpBody = try JSONEncoder().encode(body)
        return result
    }
    public func bootstrapStart(token: String, redirect: URL) async throws -> String {
        let data = try await send(bootstrapRequest(token: token, redirect: redirect))
        return try JSONDecoder().decode(ProviderAuthorize.self, from: data).authorizeURL
    }
    public func bootstrapComplete(token: String, callback: URL) async throws {
        _ = try await send(bootstrapRequest(token: token, callback: callback))
    }
    public func disconnectProvider() async throws { _ = try await send(providerRequest(action: "disconnect")) }
    public func translationRequest(text: String, direction: TranslationDirection, instructions: String? = nil) throws -> URLRequest {
        try translationRequest(text: text, source: direction.source, target: direction.target, instructions: instructions)
    }
    public func translate(text: String, direction: TranslationDirection, instructions: String? = nil) async throws -> TranslationRecord {
        try APIJSON.decoder().decode(TranslationRecord.self, from: await send(translationRequest(text: text, direction: direction, instructions: instructions)))
    }
    public func translationRequest(text: String, source: Language, target: Language? = nil, instructions: String? = nil) throws -> URLRequest {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.emptyText }
        var result = try request(path: "v1/translations", method: "POST")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.httpBody = try JSONEncoder().encode(TranslationRequest(text: text, sourceLanguage: source, targetLanguage: target, instructions: instructions))
        return result
    }
    public func historyRequest() throws -> URLRequest { try request(path: "v1/translations", method: "GET") }
    private func historyMutationRequest(id: String, method: String) throws -> URLRequest {
        guard !id.isEmpty, id != ".", id != "..",
              let encoded = id.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_~"))) else { throw APIError.invalidResponse }
        var result = try request(path: "v1/history", method: method)
        guard var components = URLComponents(url: result.url!, resolvingAgainstBaseURL: false) else { throw APIError.invalidResponse }
        components.percentEncodedPath += "/" + encoded
        guard let url = components.url else { throw APIError.invalidResponse }
        result.url = url
        return result
    }
    public func deleteHistoryRequest(id: String) throws -> URLRequest {
        try historyMutationRequest(id: id, method: "DELETE")
    }
    public func favoriteHistoryRequest(id: String, favorite: Bool) throws -> URLRequest {
        var result = try historyMutationRequest(id: id, method: "PATCH")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.httpBody = try JSONEncoder().encode(["favorite": favorite])
        return result
    }
    public func deleteHistory(id: String) async throws {
        _ = try await send(deleteHistoryRequest(id: id))
    }
    public func setHistoryFavorite(id: String, favorite: Bool) async throws -> TranslationRecord {
        let record = try APIJSON.decoder().decode(TranslationRecord.self, from: await send(favoriteHistoryRequest(id: id, favorite: favorite)))
        guard record.id == id, record.favorite == favorite else { throw APIError.invalidResponse }
        return record
    }
    public func ttsRequest(text: String) throws -> URLRequest {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.emptyText }
        var result = try request(path: "tts", method: "POST")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        result.httpBody = try JSONEncoder().encode(TTSBody(text: text))
        return result
    }
    public func translate(text: String, source: Language, instructions: String? = nil) async throws -> TranslationRecord {
        try APIJSON.decoder().decode(TranslationRecord.self, from: await send(translationRequest(text: text, source: source, instructions: instructions)))
    }
    public func history() async throws -> [TranslationRecord] {
        try APIJSON.decoder().decode(TranslationHistory.self, from: await send(historyRequest())).items.sorted { $0.createdAt > $1.createdAt }
    }
    public func audio(text: String) async throws -> Data {
        try await send(ttsRequest(text: text))
    }
    private func send(_ request: URLRequest) async throws -> Data {
        // The default transport refuses redirects and cancels its URLSession.
        let response = try await transport(request)
        let data = response.data
        guard (200..<300).contains(response.status) else { throw APIError.http(response.status) }
        if response.status == 204 { return data }
        guard !data.isEmpty else { throw APIError.invalidResponse }
        return data
    }
}
private struct ProviderAuthorize: Decodable {
    let authorizeURL: String
    enum CodingKeys: String, CodingKey { case authorizeURL = "authorize_url" }
}
private struct TTSBody: Encodable {
    let text: String
    let language = "de-DE"
    let voice = "alloy"
    let model = "gpt-4o-mini-tts"
    let format = "mp3"
    let speed = 1.0
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
