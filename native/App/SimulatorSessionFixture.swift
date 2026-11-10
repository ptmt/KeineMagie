#if targetEnvironment(simulator)
import Foundation
import KeineMagieCore

/// Test transport only. Device builds do not contain this fixture.
actor SimulatorSessionFixture {
    private var validations = 0
    private let mode: String
    init(mode: String) { self.mode = mode }
    private static let record = #"{"id":"synthetic-account-A-record","created_at":"2026-11-09T12:00:00Z","text":"Synthetic account A history","source_language":"de","target_language":"ru","translation":"Synthetic stale account A result","idioms":[],"patterns":[],"vocabulary":[]}"#
    func send(_ request: URLRequest) async throws -> AuthResponse {
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
            let feed: [String: Any] = ["id": "synthetic-feed-000000001", "url": "https://audio.example/feed.xml", "title": "Synthetic language podcast", "episodes": [["id": "episode-one", "title": "Synthetic episode one", "url": "https://audio.example/episode.mp3", "published": "2026-11-10"]]]
            if request.httpMethod == "POST" { return AuthResponse(data: try JSONSerialization.data(withJSONObject: feed), status: 200) }
            let items = mode == "podcast-populated" ? [feed] : []
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": items]), status: 200)
        default: throw URLError(.unsupportedURL)
        }
    }
    private static func job(_ index: Int) -> [String: Any] {
        ["id": "synthetic-job-0000000\(index)", "url": "https://audio.example/episode-\(index).mp3", "source_language": "de", "target_language": "ru", "state": index == 2 ? "transcribing" : "completed", "progress": index == 2 ? 45 : 100, "segments": [["start": 0, "end": 12, "text": "Synthetic transcript", "translation": "Синтетический перевод"]]]
    }
}
#endif
