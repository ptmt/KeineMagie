import Foundation
import Testing
@testable import KeineMagieCore

@Test func authorizeTrustAndExactRedirect() throws {
    let redirect = URL(string: "http://127.0.0.1:54321/auth/callback")!
    let good = "https://auth.openai.com/api/accounts/authorize?redirect_uri=http%3A%2F%2F127.0.0.1%3A54321%2Fauth%2Fcallback&state=expected"
    #expect(try LoopbackPolicy.authorize(good, redirect: redirect).state == "expected")
    for bad in [good.replacingOccurrences(of: "auth.openai.com", with: "auth.openai.com.evil.test"), good.replacingOccurrences(of: "https:", with: "http:"), good + "&state=duplicate", good.replacingOccurrences(of: "54321", with: "54322"), good.replacingOccurrences(of: "/authorize?", with: "/authorize/other?")] {
        #expect(throws: (any Error).self) { try LoopbackPolicy.authorize(bad, redirect: redirect) }
    }
}
@Test func callbackParserRejectsMalformedAndDuplicate() throws {
    let redirect = URL(string: "http://127.0.0.1:54321/auth/callback")!
    let good = "GET /auth/callback?state=expected&code=synthetic HTTP/1.1\r\nHost: 127.0.0.1:54321\r\n\r\n"
    #expect(try LoopbackPolicy.callback(Data(good.utf8), redirect: redirect, state: "expected")?.query?.contains("synthetic") == true)
    for bad in [good.replacingOccurrences(of: "GET ", with: "POST "), good.replacingOccurrences(of: "Host: 127.0.0.1", with: "Host: evil.test"), good.replacingOccurrences(of: "/auth/callback?", with: "/other?"), good.replacingOccurrences(of: "state=expected", with: "state=wrong"), good.replacingOccurrences(of: "&code=", with: "&state=expected&code="), good.replacingOccurrences(of: "&code=synthetic", with: "&code=a&code=b"), good.replacingOccurrences(of: "Host:", with: "Content-Length: 4\r\nHost:")] {
        #expect(throws: (any Error).self) { try LoopbackPolicy.callback(Data(bad.utf8), redirect: redirect, state: "expected") }
    }
    #expect(try LoopbackPolicy.callback(Data(good.prefix(20).utf8), redirect: redirect, state: "expected") == nil)
    #expect(throws: (any Error).self) { try LoopbackPolicy.callback(Data(repeating: 65, count: 8193), redirect: redirect, state: "expected") }
}
@MainActor @Test func listenerCancellationAndTimeoutCloseSocket() async throws {
    let canceled = OAuthLoopback()
    _ = try await canceled.start(timeout: 2)
    canceled.cancel()
    #expect(canceled.isClosed)
    await #expect(throws: (any Error).self) { try await canceled.callback(state: "x") }
    let expired = OAuthLoopback()
    _ = try await expired.start(timeout: 0.05)
    await #expect(throws: (any Error).self) { try await expired.callback(state: "x") }
    #expect(expired.isClosed)
}
@MainActor @Test func listenerAcceptsOneCallbackAndCloses() async throws {
    let server = OAuthLoopback()
    let redirect = try await server.start(timeout: 5)
    let request = Task { try await URLSession.shared.data(from: URL(string: redirect.absoluteString + "?state=expected&code=synthetic")!) }
    let callback = try await server.callback(state: "expected")
    #expect(callback.path == "/auth/callback")
    #expect(server.isClosed)
    _ = try await request.value
    await #expect(throws: (any Error).self) { try await server.callback(state: "expected") }
}
@Test func bootstrapPayloadUsesExactCallbackAndNoProviderCredentials() throws {
    let api = APIClient(endpoint: try ServerEndpoint("https://example.com"), token: "apple-session")
    let redirect = URL(string: "http://127.0.0.1:54321/auth/callback")!
    let start = try api.bootstrapRequest(token: "synthetic-one-time", redirect: redirect)
    #expect(start.url?.path == "/v1/provider/bootstrap/start")
    #expect(start.httpMethod == "POST")
    let payload = try JSONDecoder().decode([String: String].self, from: start.httpBody!)
    #expect(payload == ["bootstrap_token": "synthetic-one-time", "redirect_uri": redirect.absoluteString])
    let callback = URL(string: redirect.absoluteString + "?state=expected&code=synthetic")!
    let complete = try api.bootstrapRequest(token: "synthetic-one-time", callback: callback)
    #expect(complete.url?.path == "/v1/provider/bootstrap/complete")
    let completion = try JSONDecoder().decode([String: String].self, from: complete.httpBody!)
    #expect(completion["callback_url"] == callback.absoluteString)
    #expect(completion.count == 2)
    #expect(throws: (any Error).self) { try api.bootstrapRequest(token: "x") }
    #expect(throws: (any Error).self) { try api.bootstrapRequest(token: "x", redirect: redirect, callback: callback) }
}
@MainActor @Test func listenerTaskCancellationClosesSocket() async throws {
    let local = OAuthLoopback()
    _ = try await local.start(timeout: 2)
    let task = Task { try await local.callback(state: "expected") }
    await Task.yield()
    task.cancel()
    await #expect(throws: (any Error).self) { try await task.value }
    #expect(local.isClosed)
}
