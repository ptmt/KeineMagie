import Foundation
import Testing
@testable import KeineMagieCore

@Test func providerUsesAccountBearerAndNoProviderSecret() throws {
 let api = APIClient(endpoint: try ServerEndpoint("https://example.com"), token: "apple-session")
 let status = try api.providerRequest()
 #expect(status.url?.path == "/v1/provider")
 #expect(status.httpMethod == "GET")
 #expect(status.value(forHTTPHeaderField: "Authorization") == "Bearer apple-session")
 let connect = try api.providerRequest(action: "connect")
 #expect(connect.httpMethod == "POST")
 #expect(connect.httpBody == Data("{}".utf8))
 #expect(throws: (any Error).self) { try api.providerRequest(action: "../../secret") }
 let statusValue = try JSONDecoder().decode(ProviderStatus.self, from: Data("{\"connected\":true,\"status\":\"connected\",\"selected_model\":\"gpt-6-luna\",\"models\":[{\"slug\":\"gpt-6-luna\",\"display_name\":\"Luna\"}],\"message\":\"Connected\"}".utf8))
 #expect(statusValue.selectedModel == "gpt-6-luna")
}
