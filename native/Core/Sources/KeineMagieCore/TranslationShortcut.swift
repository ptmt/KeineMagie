import Foundation

/// Device-local instructions; never credentials, global prompts, or selected defaults.
public struct TranslationShortcut: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let instruction: String
    public init(id: UUID = UUID(), title: String, instruction: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 40, !instruction.isEmpty, instruction.unicodeScalars.count <= 1000 else { throw APIError.invalidResponse }
        self.id = id; self.title = title; self.instruction = instruction
    }
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: fields.decode(UUID.self, forKey: .id), title: fields.decode(String.self, forKey: .title), instruction: fields.decode(String.self, forKey: .instruction))
    }
}

public struct TranslationShortcutStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(server: String, owner: String) throws -> String {
        guard !server.isEmpty, !owner.isEmpty else { throw APIError.missingToken }
        // A length-delimited encoded tuple prevents collisions without including a token.
        let identity = try JSONEncoder().encode([server, owner]).base64EncodedString()
        return "translationShortcuts.v1." + identity
    }
    public func load(server: String, owner: String) throws -> [TranslationShortcut] {
        guard let data = defaults.data(forKey: try key(server: server, owner: owner)) else { return [] }
        return try JSONDecoder().decode([TranslationShortcut].self, from: data)
    }
    public func save(_ shortcuts: [TranslationShortcut], server: String, owner: String) throws {
        defaults.set(try JSONEncoder().encode(shortcuts), forKey: try key(server: server, owner: owner))
    }
}
