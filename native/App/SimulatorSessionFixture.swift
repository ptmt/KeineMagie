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
        default: throw URLError(.unsupportedURL)
        }
    }
}
#endif
