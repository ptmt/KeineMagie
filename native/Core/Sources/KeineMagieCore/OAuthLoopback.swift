import Foundation
@preconcurrency import Network

/// Ephemeral IPv4-only listener. No provider tokens, logging, cookies, or web inspection.
@MainActor public final class OAuthLoopback {
    public private(set) var isClosed = false
    private var listener: NWListener?
    private var ready: CheckedContinuation<URL, any Error>?
    private var result: CheckedContinuation<URL, any Error>?
    private var deadline: Task<Void, Never>?
    private var connections: [UUID: NWConnection] = [:]
    private var redirect: URL?
    private var expectedState: String?
    private var used = false
    public init() {}
    public func start(timeout: TimeInterval = 280) async throws -> URL {
        guard listener == nil, !isClosed, timeout > 0, timeout <= 280 else { throw APIError.invalidResponse }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: parameters)
        listener = server
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(timeout)); self?.cancel() } catch {}
        }
        server.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        server.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                switch state {
                case .ready:
                    guard let port = server.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback") else { self.cancel(); return }
                    self.redirect = url
                    let continuation = self.ready; self.ready = nil; continuation?.resume(returning: url)
                case .failed: self.cancel()
                default: break
                }
            }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                ready = continuation; server.start(queue: .main)
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    public func callback(state: String) async throws -> URL {
        guard !isClosed, !used, !state.isEmpty, result == nil else { throw CancellationError() }
        expectedState = state
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { result = $0 }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    public func cancel() { close(error: CancellationError()) }
    private func close(error: any Error) {
        guard !isClosed else { return }; isClosed = true
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil; deadline?.cancel(); deadline = nil
        connections.values.forEach { $0.cancel() }; connections.removeAll()
        let a = ready; ready = nil; a?.resume(throwing: error)
        let b = result; result = nil; b?.resume(throwing: error)
        expectedState = nil
    }
    private func accept(_ connection: NWConnection) {
        guard !isClosed, connections.count < 8 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: .main)
        // Bound slow/incomplete headers separately from the overall consent window.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.connections.removeValue(forKey: id)?.cancel()
        }
        receive(connection, id: id, accumulated: Data())
    }
    private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: LoopbackPolicy.maximumHeaderBytes + 1) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.isClosed, self.connections[id] != nil else { connection.cancel(); return }
                var bytes = accumulated; if let data { bytes.append(data) }
                do {
                    guard let redirect = self.redirect, let state = self.expectedState else { throw APIError.invalidResponse }
                    if let url = try LoopbackPolicy.callback(bytes, redirect: redirect, state: state) {
                        guard !self.used else { throw APIError.invalidResponse }; self.used = true
                        let continuation = self.result; self.result = nil
                        // Keep only the winning connection long enough to flush a non-sensitive response.
                        self.connections.removeValue(forKey: id)
                        self.close(error: CancellationError())
                        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                        continuation?.resume(returning: url)
                    } else if !complete && error == nil {
                        self.receive(connection, id: id, accumulated: bytes)
                    } else { throw APIError.invalidResponse }
                } catch {
                    self.connections.removeValue(forKey: id)?.cancel()
                }
            }
        }
    }
}
