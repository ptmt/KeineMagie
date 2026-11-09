import Foundation
import Testing
@testable import KeineMagieCore

@MainActor private final class RequestGate {
    var entered = false
    var continuation: CheckedContinuation<Void, Never>?
    func request() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func network(_ request: URLRequest) async -> AuthResponse {
        #expect(request.url?.path == "/v1/provider/connect")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old-session")
        await self.request()
        return AuthResponse(data: Data(#"{"bootstrap_token":"A","expires_in":300,"message":"test"}"#.utf8), status: 200)
    }
    func release() { let c = continuation; continuation = nil; c?.resume() }
}

@Test @MainActor func canceledIssuanceFinishesBeforeReplacementStarts() async {
    let tasks = ChatGPTConnectionTasks()
    let gate = RequestGate()
    var canceled = false
    var replacementIssued = false
    var stalePublished = false
    let client = APIClient(endpoint: try! ServerEndpoint("https://example.com"), token: "old-session", transport: { request in await gate.network(request) })
    let a = Task { await tasks.run {
        _ = try? await client.connectProvider() // Accepted transport deliberately ignores cancellation.
        canceled = Task.isCancelled
        if !Task.isCancelled { stalePublished = true }
    } }
    while !gate.entered { await Task.yield() }
    tasks.cancel()
    let b = Task { await tasks.run { replacementIssued = true } }
    for _ in 0..<20 { await Task.yield() }
    #expect(!replacementIssued)
    gate.release()
    await a.value; await b.value
    #expect(canceled)
    #expect(!stalePublished)
    #expect(replacementIssued)
}

@Test @MainActor func canceledWaiterNeverIssuesAfterSessionReset() async {
    let tasks = ChatGPTConnectionTasks()
    let gate = RequestGate()
    var issued = false
    let a = Task { await tasks.run { await gate.request() } }
    while !gate.entered { await Task.yield() }
    let b = Task { await tasks.run { issued = true } }
    for _ in 0..<20 { await Task.yield() }
    tasks.cancel() // AppModel reset/logout/server switch uses this same cancellation seam.
    gate.release()
    await a.value; await b.value
    #expect(!issued)
}
