import Foundation

public enum Language: String, Codable, CaseIterable, Sendable {
    case german = "de", russian = "ru"
    public var opposite: Language { self == .german ? .russian : .german }
    public var title: String { self == .german ? CoreL10n.text("language.german") : CoreL10n.text("language.russian") }
}

public enum TranslationDirection: String, CaseIterable, Codable, Sendable {
    case germanToRussian, russianToGerman, germanPolishing
    public var source: Language { self == .russianToGerman ? .russian : .german }
    public var target: Language { self == .germanToRussian ? .russian : .german }
    public var compactTitle: String { "\(source.rawValue) → \(target.rawValue)" }
}

public struct TranslationRequest: Encodable, Sendable {
    public let text: String
    public let sourceLanguage: Language
    public let instructions: String?
    public let targetLanguage: Language
    public init(text: String, sourceLanguage: Language, targetLanguage: Language? = nil, instructions: String? = nil) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage ?? sourceLanguage.opposite
        self.instructions = instructions
    }
    enum CodingKeys: String, CodingKey {
        case text, instructions, sourceLanguage = "source_language", targetLanguage = "target_language"
    }
    public func encode(to encoder: any Encoder) throws {
        guard instructions.map({ $0.unicodeScalars.count <= 1000 }) ?? true else { throw APIError.invalidResponse }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(sourceLanguage, forKey: .sourceLanguage)
        try container.encode(targetLanguage, forKey: .targetLanguage)
        if let instructions, !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(instructions, forKey: .instructions)
        }
    }
}
