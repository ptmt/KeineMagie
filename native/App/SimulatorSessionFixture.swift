#if targetEnvironment(simulator)
import Foundation
import UIKit
import KeineMagieCore

/// Test transport only. Device builds do not contain this fixture.
actor SimulatorSessionFixture {
    private var coachAnswered = false
    private var coachAnswer = ""
    private var coachOutcome = "correct"
    private var coachPending = false
    private var coachCanceled = false
    private var coachClarified = false
    private var coachRevealed = false
    private var validations = 0
    private var profileLevels: [String: String] = [:]
    private var podcastRefreshed = false
    private var preparedJob: [String: Any]?
    private var prepareRequests = 0
    private let mode: String
    private func podcastFeed() -> [String: Any] {
        ["id": "synthetic-feed-000000001", "url": "https://audio.example/feed.xml", "title": "Synthetic language podcast", "artwork_url": "https://audio.example/cover.png?v=5", "latest_episode_title": "Synthetic latest episode", "episodes": [["id": "episode-one", "title": podcastRefreshed ? "Synthetic refreshed episode" : "Synthetic episode one", "url": "https://audio.example/episode.mp3", "published": "2026-11-10"]]]
    }
    private var historyItems: [[String: Any]] = (1...4).map { index in
        ["id": "synthetic-history-\(index)", "created_at": "2026-11-10T12:00:00Z", "text": "Synthetic history \(index)", "source_language": "de", "target_language": "ru", "translation": "Синтетический перевод \(index)", "favorite": false, "idioms": [], "patterns": [], "vocabulary": []]
    }
    init(mode: String) { self.mode = mode }
    static let copyTranslation = "  Übersetzung 👩🏽‍💻 Привет e\u{0301}\n\n" + String(repeating: "Zeile 日本語\t  {\"nested\":{\"literal\":\"\\n\",\"items\":[1,2]}}\n", count: 1200) + "  Ende\n "
    private static let record = #"{"id":"synthetic-account-A-record","created_at":"2026-11-09T12:00:00Z","text":"Synthetic account A history","source_language":"de","target_language":"ru","translation":"Synthetic stale account A result","idioms":[],"patterns":[],"vocabulary":[]}"#
    func send(_ request: URLRequest) async throws -> AuthResponse {
        if mode == "translation-outbox-status", request.url?.path == "/v1/provider" {
            try await Task.sleep(for: .seconds(30)); throw URLError(.timedOut)
        }
        if mode == "translation-outbox-offline", request.url?.path == "/v1/translations", request.httpMethod == "POST" { throw URLError(.notConnectedToInternet) }
        if mode == "translation-outbox-status", request.url?.path == "/v1/auth/session", validations > 0 { try await Task.sleep(for: .seconds(15)) }
        if mode == "cache-offline" || mode == "cache-blackhole" {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OfflineFixtureProtocol.self]
            configuration.timeoutIntervalForRequest = 3
            configuration.timeoutIntervalForResource = 3
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var probe = request
            probe.timeoutInterval = 3
            probe.setValue(mode, forHTTPHeaderField: "X-Synthetic-Network")
            let _ = try await session.data(for: probe)
            throw URLError(.badServerResponse)
        }
        if mode == "cache-delayed-error", ["/v1/translations", "/v1/podcasts", "/v1/podcasts/subscriptions"].contains(request.url?.path ?? "") {
            try await Task.sleep(for: .seconds(10))
            return AuthResponse(data: Data(), status: 503)
        }
        if mode == "delayed-populated", ["/v1/translations", "/v1/podcasts", "/v1/podcasts/subscriptions"].contains(request.url?.path ?? "") {
            try await Task.sleep(for: .seconds(15))
        }
        if mode.hasPrefix("history-") || mode.hasPrefix("cache-"), let path = request.url?.path, path.hasPrefix("/v1/history/") {
            try await Task.sleep(for: .milliseconds(700))
            if mode == "history-failure" { return AuthResponse(data: Data(), status: 503) }
            let id = String(path.dropFirst("/v1/history/".count))
            guard let index = historyItems.firstIndex(where: { $0["id"] as? String == id }) else { return AuthResponse(data: Data(), status: 404) }
            if request.httpMethod == "DELETE" { historyItems.remove(at: index); return AuthResponse(data: Data(), status: 204) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Bool]
            historyItems[index]["favorite"] = body?["favorite"] ?? false
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: historyItems[index]), status: 200)
        }
        if request.url?.path == "/v1/learning/coach" {
            if mode != "coach" { return AuthResponse(data: Data(#"{"turns":[],"observations":[],"model":"gpt-6.1-terra"}"#.utf8), status: 200) }
            if request.httpMethod == "POST", let data = request.httpBody {
                let action = try JSONDecoder().decode(CoachAction.self, from: data)
                if action.action == "answer" || action.action == "skip" {
                    coachAnswered = true; coachAnswer = action.text
                    coachOutcome = action.action == "skip" ? "skipped" : action.text == "auf" ? "correct" : action.text == "für" ? "wrong" : "ambiguous"
                }
                if action.action == "cancel" { coachPending = false; coachCanceled = true }
                if action.action == "reveal" { coachRevealed = true }
                if action.action == "message" { if action.text == "pending" { coachPending = true } else { coachClarified = true } }
            }
            var turn: [String: Any] = ["id": "synthetic-coach", "text": "Practice · synthetic fixture", "state": "completed", "at": "2026-11-13T12:00:00Z", "assisted": coachRevealed, "language": "de", "message": "Synthetic exercise, not live AI.", "kind": "cloze", "prompt": "Ich warte ___ den Bus.", "target": "verb_government", "source_id": "translation:synthetic"]
            if coachAnswered { turn["attempt"] = ["id": "synthetic-attempt", "answer": coachAnswer, "outcome": coachOutcome, "original_outcome": coachOutcome, "assisted": coachRevealed, "at": "2026-11-13T12:00:00Z", "excluded": false] }
            if coachAnswered || coachRevealed { turn["quote"] = "Ich warte auf den Bus."; turn["explanation"] = "warten auf + Akkusativ" }
            if coachPending || coachCanceled { turn["state"] = coachPending ? "pending" : "canceled"; turn.removeValue(forKey: "kind") }
            var turns = [turn]
            if coachClarified { turns.append(["id": "synthetic-clarification", "text": "Can you clarify this?", "state": "completed", "at": "2026-11-13T12:01:00Z", "assisted": false, "language": "de", "message": "Synthetic clarification, not live AI.", "kind": "clarification", "prompt": "", "target": "verb_government", "source_id": "translation:synthetic", "quote": "Ich warte auf den Bus.", "explanation": "warten auf + Akkusativ"]) }
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["turns": turns, "observations": [], "model": "gpt-6.1-terra"]), status: 200)
        }
        if let path = request.url?.path, path.hasPrefix("/v1/learning/") {
            guard request.httpMethod == "GET" || (path.hasPrefix("/v1/learning/profiles/") && request.httpMethod == "PUT") else { return AuthResponse(data: Data(), status: 405) }
            let citation: [String: Any] = ["segment_id": 2012, "quote": "Synthetic segment 2012", "start": 20120, "end": 20128]
            let response: [String: Any]
            if path.hasSuffix("/analysis") {
                response = ["state": "completed", "result": ["narrative": [["text": "Synthetic saved summary", "citations": [citation]]], "topics": [["title": "Synthetic topic", "key_points": [["text": "Synthetic topic detail", "citations": [citation]]]]], "recommendations": [["term": "Alltag", "translation": "повседневность", "cefr": "B1", "reason": "Synthetic recommendation", "citation": citation]]]]
            } else if path.hasSuffix("/vocabulary") {
                response = ["items": [["id": "synthetic-word", "term": "Alltag", "translation": "повседневность", "segment_id": 2012, "quote": "Synthetic segment 2012", "favorite": true, "status": "learning"]]]
            } else {
                let language = request.url?.lastPathComponent ?? "de"
                if request.httpMethod == "PUT", let data = request.httpBody, let body = try JSONSerialization.jsonObject(with: data) as? [String: String], let level = body["cefr"] { profileLevels[language] = level }
                response = ["language": language, "cefr": profileLevels[language] ?? "B1", "self_assessments": [["cefr": profileLevels[language] ?? "B1", "assessed_at": "2026-11-12T12:00:00Z"]]]
            }
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: response), status: 200)
        }
        switch request.url?.path {
        case "/v1/auth/session":
            validations += 1
            if validations > 1 {
                try await Task.sleep(for: .seconds(2))
                if mode == "revoked" { return AuthResponse(data: Data(), status: 401) }
            }
            let user = mode == "account-change" && validations > 1 ? "synthetic-account-B" : (mode == "translation-controls" ? "synthetic-quiet-controls" : "synthetic-ui-fixture")
            return AuthResponse(data: Data("{\"user\":{\"id\":\"\(user)\"},\"expires_at\":\"2099-12-01T12:00:00Z\"}".utf8), status: 200)
        case "/v1/translations":
            if mode == "coach" { return AuthResponse(data: Data(#"{"items":[{"id":"synthetic","created_at":"2026-11-13T00:00:00Z","text":"Synthetic original source","translation":"Synthetic original translation","source_language":"ru","target_language":"de","idioms":[],"patterns":[],"vocabulary":[]}]}"#.utf8), status: 200) }
            if mode.hasPrefix("translation-"), request.httpMethod == "POST" {
                if mode == "translation-pending" { try await Task.sleep(for: .seconds(8)) }
                let translation = mode == "translation-controls" ? "Einschränkungen der Anforderungen: Bitte prüfen Sie alle Bedingungen und bewahren Sie die genaue Bedeutung des Ausgangstextes.\n\nZusätzliche Zeile zur Prüfung des Eingabefelds. (Synthetic fixture)" : Self.copyTranslation
                let item: [String: Any] = ["id": "synthetic-copy", "created_at": "2026-11-11T12:00:00Z", "text": "SOURCE NOT OUTPUT", "source_language": "ru", "target_language": "de", "translation": translation, "idioms": [], "patterns": [], "vocabulary": []]
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: item), status: 200)
            }
            if mode.hasPrefix("history-") || mode.hasPrefix("cache-") {
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": historyItems]), status: 200)
            }
            if mode == "account-change" && request.httpMethod == "POST" {
                // Ignore cancellation like a response already in flight at the boundary.
                try? await Task.sleep(for: .seconds(7))
                return AuthResponse(data: Data(Self.record.utf8), status: 200)
            }
            let items = mode == "account-change" && validations == 1 ? Self.record : ""
            return AuthResponse(data: Data("{\"items\":[\(items)]}".utf8), status: 200)
        case "/v1/provider":
            if mode.hasPrefix("translation-") {
                return AuthResponse(data: Data(#"{"connected":true,"status":"connected","message":"Synthetic only","selected_model":"synthetic-only"}"#.utf8), status: 200)
            }
            let connected = mode == "account-change" && validations == 1
            return AuthResponse(data: Data("{\"connected\":\(connected),\"status\":\"\(connected ? "connected" : "disconnected")\",\"message\":\"Synthetic simulator fixture — no Apple or ChatGPT login\"}".utf8), status: 200)
        case "/v1/podcasts":
            if request.httpMethod == "POST" {
                if mode == "podcast-prepare" {
                    prepareRequests += 1
                    guard prepareRequests == 1 else { return AuthResponse(data: Data(), status: 409) }
                    try await Task.sleep(for: .seconds(6))
                    guard prepareRequests == 1 else { return AuthResponse(data: Data(), status: 409) }
                    var job = Self.job(2)
                    job["feed_id"] = "synthetic-feed-000000001"; job["episode_id"] = "episode-one"
                    job["source_url"] = "https://audio.example/episode.mp3"
                    preparedJob = job
                    return AuthResponse(data: try JSONSerialization.data(withJSONObject: job), status: 202)
                }
                if mode == "podcast-failure" { return AuthResponse(data: Data(), status: 503) }
                try? await Task.sleep(for: .seconds(mode == "account-change" ? 7 : 1))
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: Self.job(1)), status: 200)
            }
            let populated = ["podcast-populated", "podcast-timeline", "delayed-populated", "cache-populated"].contains(mode)
            var items = populated ? (1...18).map { Self.job($0) } : preparedJob.map { [$0] } ?? []
            if mode == "podcast-timeline", !items.isEmpty {
                items[0]["segments"] = (0..<2113).map { ["start": $0 * 10, "end": $0 * 10 + 8, "text": "Synthetic segment \($0)", "translation": "Перевод \($0)"] as [String: Any] }
            }
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": items, "worker_available": true]), status: 200)
        case "/v1/podcasts/subscriptions":
            let feed = podcastFeed()
            if request.httpMethod == "POST" { return AuthResponse(data: try JSONSerialization.data(withJSONObject: feed), status: 200) }
            let items = ["podcast-populated", "podcast-refresh-failure", "delayed-populated", "podcast-prepare", "cache-populated"].contains(mode) ? [feed] : []
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": items]), status: 200)
        case "/v1/podcasts/subscriptions/synthetic-feed-000000001/refresh":
            try await Task.sleep(for: .milliseconds(700))
            if mode == "podcast-refresh-failure" { return AuthResponse(data: Data(), status: 503) }
            podcastRefreshed = true
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: podcastFeed()), status: 200)
        case "/v1/podcasts/subscriptions/synthetic-feed-000000001/artwork":
            let image = await MainActor.run {
                UIGraphicsImageRenderer(size: CGSize(width: 52, height: 52)).pngData { context in
                    UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 0, y: 0, width: 52, height: 52))
                    ("RTW" as NSString).draw(at: CGPoint(x: 7, y: 18), withAttributes: [.foregroundColor: UIColor.white, .font: UIFont.boldSystemFont(ofSize: 15)])
                }
            }
            return AuthResponse(data: image, status: 200)
        default: throw URLError(.unsupportedURL)
        }
    }
    private static func job(_ index: Int) -> [String: Any] {
        ["id": "synthetic-job-0000000\(index)", "url": "https://audio.example/episode-\(index).mp3", "source_language": "de", "target_language": "ru", "state": index == 2 ? "transcribing" : "completed", "progress": index == 2 ? 45 : 100, "segments": [["start": 0, "end": 12, "text": "Synthetic transcript", "translation": "Синтетический перевод"]]]
    }
}

/// Real URLSession failure/blackhole, confined to simulator synthetic requests.
private final class OfflineFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.value(forHTTPHeaderField: "X-Synthetic-Network") != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.value(forHTTPHeaderField: "X-Synthetic-Network") == "cache-offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
        // Blackhole intentionally sends nothing; URLSession's resource deadline expires.
    }
    override func stopLoading() {}
}

enum SimulatorIdentityStore {
    static func read(_ root: URL) throws -> SavedNativeIdentity? {
        let file = root.appendingPathComponent("synthetic-identity.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(SavedNativeIdentity.self, from: Data(contentsOf: file))
    }
    static func save(_ identity: SavedNativeIdentity?, root: URL) throws {
        let file = root.appendingPathComponent("synthetic-identity.json")
        if let identity {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(identity).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
#endif
