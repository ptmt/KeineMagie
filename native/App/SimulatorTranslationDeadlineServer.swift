#if targetEnvironment(simulator)
import Foundation
import Network

/// Opt-in local HTTP fixture. Uses production URLSession, never a provider.
final class SimulatorTranslationDeadlineServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "translation-deadline-ui-fixture")
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
    func url() async throws -> URL {
        for _ in 0..<200 {
            if let port = listener.port, port.rawValue != 0 { return URL(string: "http://127.0.0.1:\(port.rawValue)/v1/translations")! }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.cannotConnectToHost)
    }
    deinit { listener.cancel() }
}
#endif
