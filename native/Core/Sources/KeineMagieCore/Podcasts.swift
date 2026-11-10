import Foundation

public struct PodcastShareURL: Sendable {
    public let url: URL
    public init(_ value: String) throws {
        guard value.utf8.count <= 2048, !value.contains(where: { $0.isWhitespace || $0.isNewline }),
              let parts = URLComponents(string: value), ["http", "https"].contains(parts.scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, let url = parts.url else { throw APIError.invalidResponse }
        self.url = url
    }
}
public struct PodcastSegment: Decodable, Sendable, Identifiable {
    public var id: Double { start }
    public let start: Double
    public let end: Double
    public let text: String
    public let translation: String?
}
public struct PodcastJob: Decodable, Sendable, Identifiable {
    public let id: String
    public let url: String
    public let sourceLanguage: String
    public let targetLanguage: String
    public let state: String
    public let progress: Int
    public let error: String?
    public let segments: [PodcastSegment]
    public var active: Bool { ["queued", "fetching", "transcribing", "translating"].contains(state) }
    enum CodingKeys: String, CodingKey {
        case id, url, state, progress, error, segments
        case sourceLanguage = "source_language", targetLanguage = "target_language"
    }
}
public struct PodcastEpisode: Decodable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let url: String
    public let published: String?
}
public struct PodcastSubscription: Decodable, Sendable, Identifiable {
    public let id: String
    public let url: String
    public let title: String
    public let episodes: [PodcastEpisode]
}
public struct PodcastSubscriptions: Decodable, Sendable {
    public let items: [PodcastSubscription]
}
public struct PodcastDiscovery: Decodable, Sendable {
    public let url: String
    public let title: String
    public let episodes: [PodcastEpisode]
}
public struct PodcastLibrary: Decodable, Sendable {
    public let items: [PodcastJob]
    public let workerAvailable: Bool
    enum CodingKeys: String, CodingKey { case items; case workerAvailable = "worker_available" }
}
// Kept separate from text APIClient: no access to another client's private token.
public struct PodcastAPI: Sendable {
    private let endpoint: ServerEndpoint
    private let token: String
    private let transport: AuthClient.Transport
    public init(endpoint: ServerEndpoint, token: String, transport: @escaping AuthClient.Transport = AuthClient.network) {
        self.endpoint = endpoint; self.token = token; self.transport = transport
    }
    private func request(_ path: String = "", method: String = "GET") throws -> URLRequest {
        guard !token.isEmpty, !token.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }) else { throw APIError.missingToken }
        var request = URLRequest(url: endpoint.url(path: "v1/podcasts" + path))
        request.httpMethod = method; request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    public func importRequest(url: String, source: String) throws -> URLRequest {
        let value = try PodcastShareURL(url)
        guard ["de", "ru"].contains(source) else { throw APIError.invalidResponse }
        var request = try request(method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": value.url.absoluteString, "source_language": source])
        return request
    }
    public func subscriptionRequest(url: String) throws -> URLRequest {
        let value = try PodcastShareURL(url)
        var request = try request("/subscriptions", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": value.url.absoluteString])
        return request
    }
    public func subscriptionActionRequest(id: String, action: String) throws -> URLRequest {
        guard id.range(of: "^[A-Za-z0-9_-]{20,128}$", options: .regularExpression) != nil,
              ["refresh", "delete"].contains(action) else { throw APIError.invalidResponse }
        return try request("/subscriptions/" + id + (action == "delete" ? "" : "/refresh"), method: action == "delete" ? "DELETE" : "POST")
    }
    public func subscriptions() async throws -> [PodcastSubscription] {
        try JSONDecoder().decode(PodcastSubscriptions.self, from: await send(request("/subscriptions"))).items
    }
    public func subscribe(url: String) async throws -> PodcastSubscription {
        try JSONDecoder().decode(PodcastSubscription.self, from: await send(subscriptionRequest(url: url)))
    }
    public func subscriptionAction(id: String, action: String) async throws {
        _ = try await send(subscriptionActionRequest(id: id, action: action))
    }
    private func send(_ request: URLRequest) async throws -> Data {
        let response = try await transport(request)
        guard (200..<300).contains(response.status) else { throw APIError.http(response.status) }
        guard response.data.count <= 8 << 20 else { throw APIError.invalidResponse }
        return response.data
    }
    public func library() async throws -> PodcastLibrary {
        try JSONDecoder().decode(PodcastLibrary.self, from: await send(request()))
    }
    public func enqueue(url: String, source: String) async throws -> PodcastJob {
        try JSONDecoder().decode(PodcastJob.self, from: await send(importRequest(url: url, source: source)))
    }
    public func action(id: String, action: String) async throws {
        guard id.range(of: "^[A-Za-z0-9_-]{20,128}$", options: .regularExpression) != nil,
              ["retry", "cancel", "delete"].contains(action) else { throw APIError.invalidResponse }
        _ = try await send(request("/" + id + (action == "delete" ? "" : "/" + action), method: action == "delete" ? "DELETE" : "POST"))
    }
}
