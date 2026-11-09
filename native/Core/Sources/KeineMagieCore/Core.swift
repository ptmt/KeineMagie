import Foundation

public enum Language: String, Codable, CaseIterable, Sendable {
    case german = "de", russian = "ru"
    public var opposite: Language { self == .german ? .russian : .german }
    public var title: String { self == .german ? CoreL10n.text("language.german") : CoreL10n.text("language.russian") }
}

public struct TranslationRequest: Encodable, Sendable {
    public let text: String
    public let sourceLanguage: Language
    public var targetLanguage: Language { sourceLanguage.opposite }
    public init(text: String, sourceLanguage: Language) {
        self.text = text
        self.sourceLanguage = sourceLanguage
    }
    enum CodingKeys: String, CodingKey {
        case text, sourceLanguage = "source_language", targetLanguage = "target_language"
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(sourceLanguage, forKey: .sourceLanguage)
        try container.encode(targetLanguage, forKey: .targetLanguage)
    }
}
