import Foundation

public struct ServerEndpoint: Sendable {
    public let baseURL: URL
    public init(_ value: String, allowLocalHTTP: Bool = false) throws {
        guard let parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let url = parts.url else { throw EndpointError.invalid }
        let local = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())
        guard parts.scheme == "https" || (parts.scheme == "http" && allowLocalHTTP && local) else {
            throw EndpointError.insecure
        }
        baseURL = url
    }
    public func url(path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { $0.appendingPathComponent(String($1)) }
    }
}
public enum EndpointError: LocalizedError {
    case invalid, insecure
    public var errorDescription: String? {
        switch self {
        case .invalid: CoreL10n.text("endpoint.invalid")
        case .insecure: CoreL10n.text("endpoint.insecure")
        }
    }
}
