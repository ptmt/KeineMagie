import Foundation
import Network
import Testing
@testable import KeineMagieCore

/// Real loopback HTTP, no URLProtocol/mock transport and no external provider.
private final class DelayedTranslationServer: @unchecked Sendable {
    let listener: NWListener
    let queue = DispatchQueue(label: "translation-deadline-fixture")
    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                queue.asyncAfter(deadline: .now() + 10) {
                    let body = #"{"id":"fixture","created_at":"2026-11-19T08:15:16Z","text":"сплетни","source_language":"ru","target_language":"de","translation":"Gerüchte","idioms":[],"patterns":[],"vocabulary":[]}"#
                    let data = Data(body.utf8)
                    let header = "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(header.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        listener.start(queue: queue)
    }
    func endpoint() async throws -> ServerEndpoint {
        for _ in 0..<200 {
            if let port = listener.port, port.rawValue != 0 { return try ServerEndpoint("http://127.0.0.1:\(port.rawValue)", allowLocalHTTP: true) }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.cannotConnectToHost)
    }
    deinit { listener.cancel() }
}

@Test func authRequestsKeepEightSecondDeadline() async throws {
    let client = AuthClient(endpoint: try ServerEndpoint("https://fixture.invalid"), transport: { request in
        #expect(request.timeoutInterval == 8)
        throw URLError(.cancelled)
    })
    do { _ = try await client.challenge() } catch {}
    let challenge = try JSONDecoder().decode(AppleChallenge.self, from: Data(#"{"challenge_id":"fixture","nonce":"fixture","state":"fixture"}"#.utf8))
    do { _ = try await client.signIn(challenge: challenge, identityToken: "fixture", returnedState: "fixture") } catch {}
    do { _ = try await client.session(token: "fixture") } catch {}
    do { try await client.logout(token: "fixture") } catch {}
}

@Test func translationRealTransportHonorsNinetySecondDeadline() async throws {
    let server = try DelayedTranslationServer()
    let client = APIClient(endpoint: try await server.endpoint(), token: "synthetic-fixture-only")
    let request = try client.translationRequest(text: "сплетни", direction: .russianToGerman)
    #expect(request.timeoutInterval == 90)
    let result = try await client.translate(text: "сплетни", direction: .russianToGerman, requestID: UUID(), owner: "synthetic")
    #expect(result.translation == "Gerüchte")
}
