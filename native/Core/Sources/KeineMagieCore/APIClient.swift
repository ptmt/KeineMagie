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
        case .missingToken: "Bitte einen gültigen Server-Token in den Einstellungen hinterlegen."
        case .emptyText: "Bitte zuerst Text eingeben."
        case .invalidResponse: "Der Server hat keine gültige Antwort geliefert."
        case .http(401), .http(403): "Zugriff verweigert. Server-Token prüfen."
        case .http(let status): "Serverfehler (HTTP \(status)). Bitte später erneut versuchen."
        }
    }
}
