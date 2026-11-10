#if targetEnvironment(simulator)
import Foundation
import UIKit
import KeineMagieCore

/// Test transport only. Device builds do not contain this fixture.
actor SimulatorSessionFixture {
    private var validations = 0
    private var podcastRefreshed = false
    private let mode: String
    private func podcastFeed() -> [String: Any] {
        ["id": "synthetic-feed-000000001", "url": "https://audio.example/feed.xml", "title": "Synthetic language podcast", "artwork_url": "https://audio.example/cover.png?v=5", "latest_episode_title": "Synthetic latest episode", "episodes": [["id": "episode-one", "title": podcastRefreshed ? "Synthetic refreshed episode" : "Synthetic episode one", "url": "https://audio.example/episode.mp3", "published": "2026-11-10"]]]
    }
    private var historyItems: [[String: Any]] = (1...4).map { index in
        ["id": "synthetic-history-\(index)", "created_at": "2026-11-10T12:00:00Z", "text": "Synthetic history \(index)", "source_language": "de", "target_language": "ru", "translation": "Синтетический перевод \(index)", "favorite": false, "idioms": [], "patterns": [], "vocabulary": []]
    }
    init(mode: String) { self.mode = mode }
    private static let record = #"{"id":"synthetic-account-A-record","created_at":"2026-11-09T12:00:00Z","text":"Synthetic account A history","source_language":"de","target_language":"ru","translation":"Synthetic stale account A result","idioms":[],"patterns":[],"vocabulary":[]}"#
    func send(_ request: URLRequest) async throws -> AuthResponse {
        if mode.hasPrefix("history-"), let path = request.url?.path, path.hasPrefix("/v1/history/") {
            try await Task.sleep(for: .milliseconds(700))
            if mode == "history-failure" { return AuthResponse(data: Data(), status: 503) }
            let id = String(path.dropFirst("/v1/history/".count))
            guard let index = historyItems.firstIndex(where: { $0["id"] as? String == id }) else { return AuthResponse(data: Data(), status: 404) }
            if request.httpMethod == "DELETE" { historyItems.remove(at: index); return AuthResponse(data: Data(), status: 204) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Bool]
            historyItems[index]["favorite"] = body?["favorite"] ?? false
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: historyItems[index]), status: 200)
        }
        switch request.url?.path {
        case "/v1/auth/session":
            validations += 1
            if validations > 1 {
                try await Task.sleep(for: .seconds(2))
                if mode == "revoked" { return AuthResponse(data: Data(), status: 401) }
            }
            let user = mode == "account-change" && validations > 1 ? "synthetic-account-B" : "synthetic-ui-fixture"
            return AuthResponse(data: Data("{\"user\":{\"id\":\"\(user)\"},\"expires_at\":\"2099-12-01T12:00:00Z\"}".utf8), status: 200)
        case "/v1/translations":
            if mode.hasPrefix("history-") {
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
            let connected = mode == "account-change" && validations == 1
            return AuthResponse(data: Data("{\"connected\":\(connected),\"status\":\"\(connected ? "connected" : "disconnected")\",\"message\":\"Synthetic simulator fixture — no Apple or ChatGPT login\"}".utf8), status: 200)
        case "/v1/podcasts":
            if request.httpMethod == "POST" {
                if mode == "podcast-failure" { return AuthResponse(data: Data(), status: 503) }
                try? await Task.sleep(for: .seconds(mode == "account-change" ? 7 : 1))
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: Self.job(1)), status: 200)
            }
            let populated = mode == "podcast-populated" || (mode == "account-change" && validations == 1)
            let items = populated ? (1...18).map { Self.job($0) } : []
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": items, "worker_available": true]), status: 200)
        case "/v1/podcasts/subscriptions":
            let feed = podcastFeed()
            if request.httpMethod == "POST" { return AuthResponse(data: try JSONSerialization.data(withJSONObject: feed), status: 200) }
            let items = ["podcast-populated", "podcast-refresh-failure"].contains(mode) ? [feed] : []
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
#endif
