import Foundation

/// Only the server creates state/PKCE; native code constrains transport and echoes the callback.
public enum LoopbackPolicy {
    public static let maximumHeaderBytes = 8192
    public static func callback(_ data: Data, redirect: URL, state: String) throws -> URL? {
        guard data.count <= maximumHeaderBytes else { throw APIError.invalidResponse }
        guard let text = String(data: data, encoding: .utf8) else { throw APIError.invalidResponse }
        guard let end = text.range(of: "\r\n\r\n") else { return nil }
        guard end.upperBound == text.endIndex else { throw APIError.invalidResponse }
        let lines = text[..<end.lowerBound].components(separatedBy: "\r\n")
        let first = lines[0].components(separatedBy: " ")
        guard first.count == 3, first[0] == "GET", first[2] == "HTTP/1.1",
              first[1].hasPrefix("/auth/callback?"), !first[1].contains("#"),
              !first[1].contains(where: { $0.asciiValue.map { $0 < 33 || $0 > 126 } ?? true }) else { throw APIError.invalidResponse }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw APIError.invalidResponse }
            let name = line[..<colon].lowercased()
            guard headers[name] == nil, name != "transfer-encoding", name != "content-length" else { throw APIError.invalidResponse }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["host"] == "127.0.0.1:\(redirect.port ?? 0)",
              let c = URLComponents(string: "http://127.0.0.1:\(redirect.port ?? 0)" + first[1]),
              c.percentEncodedPath == "/auth/callback", let url = c.url else { throw APIError.invalidResponse }
        let items = c.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count,
              items.first(where: { $0.name == "state" })?.value == state,
              items.first(where: { $0.name == "code" })?.value?.isEmpty == false || items.first(where: { $0.name == "error" })?.value?.isEmpty == false else { throw APIError.invalidResponse }
        return url
    }
    public static func authorize(_ raw: String, redirect: URL) throws -> (url: URL, state: String) {
        guard let c = URLComponents(string: raw), c.scheme == "https", c.host == "auth.openai.com",
              c.port == nil, c.user == nil, c.password == nil, c.fragment == nil,
              c.percentEncodedPath == "/api/accounts/authorize", let url = c.url else { throw APIError.invalidResponse }
        let items = c.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count,
              items.first(where: { $0.name == "redirect_uri" })?.value == redirect.absoluteString,
              let state = items.first(where: { $0.name == "state" })?.value, !state.isEmpty else { throw APIError.invalidResponse }
        return (url, state)
    }
}
