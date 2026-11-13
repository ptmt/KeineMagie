import Foundation

public struct PodcastShareURL: Sendable {
    public let url: URL
    public init(_ value: String) throws {
        guard value.utf8.count <= 2048, !value.contains(where: { $0.isWhitespace || $0.isNewline }),
              let parts = URLComponents(string: value), ["http", "https"].contains(parts.scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              Self.publicQuery(parts), parts.fragment == nil, let url = parts.url else { throw APIError.invalidResponse }
        self.url = url
    }
    private static func publicQuery(_ parts: URLComponents) -> Bool {
        guard let raw = parts.percentEncodedQuery else { return true }
        guard raw.utf8.count <= 512, let items = parts.queryItems, !items.isEmpty, items.count <= 3,
              Set(items.map(\.name)).count == items.count else { return false }
        return items.allSatisfy { item in
            guard let value = item.value, !value.isEmpty, value.utf8.count <= 64 else { return false }
            switch item.name {
            case "v", "awEpisodeId": return value.range(of: "^[0-9]+$", options: .regularExpression) != nil
            case "awCollectionId": return value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
            default: return false
            }
        }
    }
}
public struct PodcastSegment: Codable, Sendable, Identifiable {
    public var id: Double { start }
    public let start: Double
    public let end: Double
    public let text: String
    public let translation: String?
}
public struct PodcastJob: Codable, Sendable, Identifiable {
    public let id: String
    public let url: String
    public let sourceLanguage: String
    public let targetLanguage: String
    public let state: String
    public let progress: Int
    public let error: String?
    public let segments: [PodcastSegment]
    public let feedID: String?
    public let episodeID: String?
    public let sourceURL: String?
    public let episodeTitle: String?
    public var displayProgress: Double? { active && progress > 0 && progress < 100 ? Double(progress) / 100 : nil }
    public func belongs(to episode: PodcastEpisode, feedID: String) -> Bool {
        if let linked = self.feedID, let episodeID { return linked == feedID && episodeID == episode.id }
        return Self.canonical(sourceURL ?? url) == Self.canonical(episode.url)
    }
    private static func canonical(_ value: String) -> String {
        guard var parts = URLComponents(string: value) else { return value }
        parts.fragment = nil; parts.host = parts.host?.lowercased(); parts.scheme = parts.scheme?.lowercased()
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        return parts.string ?? value
    }
    public var active: Bool { ["queued", "fetching", "downloading", "transcribing", "translating"].contains(state) }
    enum CodingKeys: String, CodingKey {
        case id, url, state, progress, error, segments
        case feedID = "feed_id", episodeID = "episode_id", sourceURL = "source_url", episodeTitle = "episode_title"
        case sourceLanguage = "source_language", targetLanguage = "target_language"
    }
}
public struct PodcastEpisode: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let url: String
    public let published: String?
    public let duration: String?
    public let preparation: PodcastJob?
}
public struct PodcastSubscription: Codable, Sendable, Identifiable {
    public let id: String
    public let url: String
    public let title: String
    public let episodes: [PodcastEpisode]
    public let artworkURL: String?
    public let latestEpisodeTitle: String?
    enum CodingKeys: String, CodingKey {
        case id, url, title, episodes
        case artworkURL = "artwork_url", latestEpisodeTitle = "latest_episode_title"
    }
}
public struct PodcastSubscriptions: Codable, Sendable {
    public let items: [PodcastSubscription]
}
public struct PodcastDiscovery: Codable, Sendable {
    public let url: String
    public let title: String
    public let episodes: [PodcastEpisode]
}
public struct PodcastLibrary: Codable, Sendable {
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
    public func importRequest(url: String, source: String, feedID: String? = nil, episodeID: String? = nil) throws -> URLRequest {
        let value = try PodcastShareURL(url)
        guard ["de", "ru"].contains(source) else { throw APIError.invalidResponse }
        var request = try request(method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = ["url": value.url.absoluteString, "source_language": source]
        body["feed_id"] = feedID; body["episode_id"] = episodeID
        request.httpBody = try JSONEncoder().encode(body)
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
    public func artworkRequest(id: String) throws -> URLRequest {
        guard id.range(of: "^[A-Za-z0-9_-]{20,128}$", options: .regularExpression) != nil else { throw APIError.invalidResponse }
        var value = try request("/subscriptions/" + id + "/artwork")
        value.setValue("image/jpeg, image/png", forHTTPHeaderField: "Accept")
        return value
    }
    public func artwork(id: String) async throws -> Data {
        let data = try await send(artworkRequest(id: id))
        guard data.count <= 2 << 20 else { throw APIError.invalidResponse }
        return data
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
    public enum LearningResource: Sendable { case analysis(String), vocabulary(String, String), profile(String) }
    public func learningRequest(resource: LearningResource, assessment: String? = nil) throws -> URLRequest {
        var path: String
        var query: [URLQueryItem] = []
        func validID(_ id: String) -> Bool { id.range(of: "^[A-Za-z0-9_-]{20,128}$", options: .regularExpression) != nil }
        switch resource {
        case .analysis(let id):
            guard validID(id), assessment == nil else { throw APIError.invalidResponse }
            path = "episodes/" + id + "/analysis"
        case .vocabulary(let id, let language):
            guard validID(id), ["de", "ru"].contains(language), assessment == nil else { throw APIError.invalidResponse }
            path = "vocabulary"
            query = [URLQueryItem(name: "language", value: language), URLQueryItem(name: "job_id", value: id)]
        case .profile(let language):
            guard ["de", "ru"].contains(language), assessment.map(LearningProfile.levels.contains) ?? true else { throw APIError.invalidResponse }
            path = "profiles/" + language
        }
        var value = try request()
        var parts = URLComponents(url: endpoint.url(path: "v1/learning/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        value.url = parts.url
        value.cachePolicy = .reloadIgnoringLocalCacheData
        value.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let assessment {
            value.httpMethod = "PUT"
            value.setValue("application/json", forHTTPHeaderField: "Content-Type")
            value.httpBody = try JSONEncoder().encode(["cefr": assessment])
        }
        return value
    }
    public func analysis(id: String) async throws -> LearningAnalysis {
        do { return try JSONDecoder().decode(LearningAnalysis.self, from: await send(learningRequest(resource: .analysis(id)))) }
        catch APIError.http(409) { return LearningAnalysis(state: "unavailable", result: nil) }
    }
    public func vocabulary(id: String, language: String) async throws -> [LearningVocabulary] {
        struct Response: Decodable { let items: [LearningVocabulary] }
        return try JSONDecoder().decode(Response.self, from: await send(learningRequest(resource: .vocabulary(id, language)))).items
    }
    public func profile(language: String, assessment: String? = nil) async throws -> LearningProfile {
        try JSONDecoder().decode(LearningProfile.self, from: await send(learningRequest(resource: .profile(language), assessment: assessment)))
    }
    public func coach(action: CoachAction? = nil) async throws -> CoachSnapshot {
        var value = try request()
        value.url = endpoint.url(path: "v1/learning/coach")
        value.timeoutInterval = 75
        value.cachePolicy = .reloadIgnoringLocalCacheData
        value.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let action {
            value.httpMethod = "POST"
            value.setValue("application/json", forHTTPHeaderField: "Content-Type")
            value.httpBody = try JSONEncoder().encode(action)
        }
        let response = try await transport(value)
        if response.status == 401 { throw APIError.http(401) }
        guard response.status == 200 else {
            struct Failure: Decodable { let code: String? }
            let code = (try? JSONDecoder().decode(Failure.self, from: response.data).code) ?? ""
            let allowed = ["storage", "session", "invalid", "quota", "canceled", "connection_required", "catalog_unavailable", "model_unavailable", "sources_unavailable", "sources_required", "conflict"]
            let key = code.hasPrefix("coach_") ? String(code.dropFirst(6)) : ""
            let safe = allowed.contains(key) ? key : (response.status == 403 ? "session" : response.status == 429 ? "quota" : "network")
            throw CoachServiceError(status: response.status, message: "coach.error." + safe)
        }
        return try JSONDecoder().decode(CoachSnapshot.self, from: response.data)
    }
    public func library() async throws -> PodcastLibrary {
        try JSONDecoder().decode(PodcastLibrary.self, from: await send(request()))
    }
    public func enqueue(url: String, source: String, feedID: String? = nil, episodeID: String? = nil) async throws -> PodcastJob {
        try JSONDecoder().decode(PodcastJob.self, from: await send(importRequest(url: url, source: source, feedID: feedID, episodeID: episodeID)))
    }
    public func action(id: String, action: String) async throws {
        guard id.range(of: "^[A-Za-z0-9_-]{20,128}$", options: .regularExpression) != nil,
              ["retry", "cancel", "delete"].contains(action) else { throw APIError.invalidResponse }
        _ = try await send(request("/" + id + (action == "delete" ? "" : "/" + action), method: action == "delete" ? "DELETE" : "POST"))
    }
}
