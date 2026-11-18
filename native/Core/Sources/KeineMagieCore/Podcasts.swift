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
/// Durable passage counts from the owner-scoped batch library, never playback or vocabulary.
public struct PodcastCoverage: Codable, Sendable {
    public let passageRevision: UInt64?
    public let recognizedSegments: Int?
    public let translatedSegments: Int?
    public let favoritePassages: Int?
    public var knownTotal: Int? { recognizedSegments.flatMap { $0 > 0 ? $0 : nil } }
    public func favoritePassageCount(groups: PassageGroups?) -> Int? {
        if let groups, groups.revision > (passageRevision ?? 0) { return groups.favoriteSegmentIDs.count }
        return favoritePassages
    }
    enum CodingKeys: String, CodingKey {
        case passageRevision = "passage_revision"
        case recognizedSegments = "recognized_segments", translatedSegments = "translated_segments", favoritePassages = "favorite_passages"
    }
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
    public let coverage: PodcastCoverage?
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
        case id, url, state, progress, error, segments, coverage
        case feedID = "feed_id", episodeID = "episode_id", sourceURL = "source_url", episodeTitle = "title"
        case sourceLanguage = "source_language", targetLanguage = "target_language"
    }
    private enum LegacyKeys: String, CodingKey { case episodeTitle = "episode_title" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        sourceLanguage = try c.decode(String.self, forKey: .sourceLanguage)
        targetLanguage = try c.decode(String.self, forKey: .targetLanguage)
        state = try c.decode(String.self, forKey: .state)
        progress = try c.decode(Int.self, forKey: .progress)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        coverage = try c.decodeIfPresent(PodcastCoverage.self, forKey: .coverage)
        // Subscription preparation summaries deliberately omit transcript bytes.
        segments = try c.decodeIfPresent([PodcastSegment].self, forKey: .segments) ?? []
        feedID = try c.decodeIfPresent(String.self, forKey: .feedID)
        episodeID = try c.decodeIfPresent(String.self, forKey: .episodeID)
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        episodeTitle = try c.decodeIfPresent(String.self, forKey: .episodeTitle)
            ?? legacy.decodeIfPresent(String.self, forKey: .episodeTitle)
    }
}
public struct PodcastEpisode: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let url: String
    public let published: String?
    public let duration: String?
    public let preparation: PodcastJob?
    public var publicationDate: Date? {
        guard let published else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: published) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: published) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd", "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: published) { return date }
        }
        return nil
    }
}
public struct PodcastSubscription: Codable, Sendable, Identifiable {
    public let id: String
    public let url: String
    public let title: String
    public let episodes: [PodcastEpisode]
    public let artworkURL: String?
    public let latestEpisodeTitle: String?
    public let author: String?
    public var latestEpisodes: [PodcastEpisode] {
        episodes.enumerated().map { (index: $0.offset, episode: $0.element, date: $0.element.publicationDate) }
            .sorted { a, b in
                if let lhs = a.date, let rhs = b.date, lhs != rhs { return lhs > rhs }
                if a.date != nil && b.date == nil { return true }
                if a.date == nil && b.date != nil { return false }
                return a.index < b.index
            }.prefix(3).map(\.episode)
    }
    enum CodingKeys: String, CodingKey {
        case id, url, title, episodes, author
        case artworkURL = "artwork_url", latestEpisodeTitle = "latest_episode_title"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        episodes = try c.decodeIfPresent([PodcastEpisode].self, forKey: .episodes) ?? []
        artworkURL = try c.decodeIfPresent(String.self, forKey: .artworkURL)
        latestEpisodeTitle = try c.decodeIfPresent(String.self, forKey: .latestEpisodeTitle)
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
    public func dictationRequest(id: String = "", action: String = "", method: String = "GET", body: Data? = nil) throws -> URLRequest {
        guard id.isEmpty || id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil,
              action.isEmpty || ["check", "reveal", "attempts", "playback"].contains(action) || action.range(of: "^audio/(0|[1-9][0-9]{0,2})$", options: .regularExpression) != nil else { throw APIError.invalidResponse }
        var r = try request(method: method)
        r.url = endpoint.url(path: "v1/learning/dictations" + (id.isEmpty ? "" : "/" + id) + (action.isEmpty ? "" : "/" + action))
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.timeoutInterval = method == "POST" && action.hasPrefix("audio/") ? 250 : 50
        if action == "playback" {r.timeoutInterval=8}
        r.httpBody = body
        if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }
    public func dictationPlayback(id: String, command: DictationPlaybackRequest, owner: String? = nil) async throws -> DictationPlayback {
        try Task.checkCancellation()
        var request=try dictationRequest(id:id,action:"playback",method:"POST",body:JSONEncoder().encode(command))
        if let owner {request.setValue(owner,forHTTPHeaderField:"X-Dictation-Owner")}
        let data=try await send(request)
        try Task.checkCancellation()
        return try JSONDecoder().decode(DictationPlayback.self,from:data)
    }
    public func dictations() async throws -> DictationHistory {
        let data = try await send(dictationRequest())
        try Task.checkCancellation()
        return try JSONDecoder().decode(DictationHistory.self, from: data)
    }
    public func deleteDictation(id: String, revision: Int) async throws {
        _ = try await send(dictationRequest(id: id, method: "DELETE", body: JSONEncoder().encode(["revision":revision])))
        try Task.checkCancellation()
    }
    public func dictation(id: String = "", action: String = "", method: String = "GET", body: Data? = nil) async throws -> DictationRecord {
        let data = try await send(dictationRequest(id: id, action: action, method: method, body: body))
        try Task.checkCancellation()
        return try JSONDecoder().decode(DictationRecord.self, from: data)
    }
    public func dictationAudio(id: String, index: Int, prepare: Bool) async throws -> Data {
        let r = try dictationRequest(id: id, action: "audio/\(index)", method: prepare ? "POST" : "GET", body: prepare ? Data("{}".utf8) : nil)
        let response = try await transport(r)
        guard response.status == 200 else { throw APIError.http(response.status) }
        try Task.checkCancellation()
        guard response.data.count <= 16 << 20 else { throw APIError.invalidResponse }
        return response.data
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
    public func passageRequest(id: String, segment: Int? = nil, favorite: Bool? = nil, owner: String) throws -> URLRequest {
        guard id.range(of: "^[A-Za-z0-9_-]{20,128}$", options: .regularExpression) != nil,
              !owner.isEmpty, !owner.contains(where: { $0.isNewline }),
              (segment == nil && favorite == nil) || (segment.map { $0 >= 0 } == true && favorite != nil) else { throw APIError.invalidResponse }
        var r = try request(method: segment == nil ? "GET" : "PUT")
        r.url = endpoint.url(path: "v1/learning/episodes/" + id + (segment.map { "/passages/\($0)" } ?? "/passage-groups"))
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.setValue(owner, forHTTPHeaderField: "X-Passage-Owner")
        if let favorite {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONEncoder().encode(["favorite": favorite])
        }
        return r
    }
    public func passageGroups(id: String, owner: String) async throws -> PassageGroups {
        let data = try await send(passageRequest(id: id, owner: owner))
        try Task.checkCancellation()
        let value = try JSONDecoder().decode(PassageGroups.self, from: data)
        guard value.jobID == id else { throw APIError.invalidResponse }
        return value
    }
    public func setPassage(id: String, segment: Int, favorite: Bool, owner: String) async throws -> PassageGroups {
        let data = try await send(passageRequest(id: id, segment: segment, favorite: favorite, owner: owner))
        try Task.checkCancellation()
        struct Reply: Decodable { let passage_groups: PassageGroups }
        let value = try JSONDecoder().decode(Reply.self, from: data).passage_groups
        guard value.jobID == id, value.starredIDs.contains(segment) == favorite else { throw APIError.invalidResponse }
        return value
    }
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
        let response: AuthResponse
        do { response = try await transport(value) }
        catch let error as URLError {
            let key = error.code == .timedOut ? "timeout" : error.code == .cancelled ? "canceled" : "network"
            throw CoachServiceError(status: 0, message: "coach.error." + key)
        }
        catch is CancellationError { throw CoachServiceError(status: 0, message: "coach.error.canceled") }
        catch { throw CoachServiceError(status: 0, message: "coach.error.unknown") }
        if response.status == 401 { throw APIError.http(401) }
        guard response.status == 200 else {
            struct Failure: Decodable { let code: String? }
            let code = (try? JSONDecoder().decode(Failure.self, from: response.data).code) ?? ""
            let allowed = ["storage", "session", "invalid", "quota", "canceled", "connection_required", "catalog_unavailable", "model_unavailable", "sources_unavailable", "sources_required", "conflict"]
            let key = code.hasPrefix("coach_") ? String(code.dropFirst(6)) : ""
            let safe = allowed.contains(key) ? key : (response.status == 403 ? "session" : response.status == 429 ? "quota" : "server")
            throw CoachServiceError(status: response.status, message: "coach.error." + safe)
        }
        do { return try JSONDecoder().decode(CoachSnapshot.self, from: response.data) }
        catch { throw CoachServiceError(status: response.status, message: "coach.error.response") }
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
