import Foundation

public struct TranslationRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let text: String
    public let sourceLanguage: Language
    public let targetLanguage: Language
    public let translation: String
    public let instructions: String?
    public let favorite: Bool
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        text = try c.decode(String.self, forKey: .text)
        sourceLanguage = try c.decode(Language.self, forKey: .sourceLanguage)
        targetLanguage = try c.decode(Language.self, forKey: .targetLanguage)
        translation = try c.decode(String.self, forKey: .translation)
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions)
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        idioms = try c.decode([Idiom].self, forKey: .idioms)
        patterns = try c.decode([SentencePattern].self, forKey: .patterns)
        vocabulary = try c.decode([Vocabulary].self, forKey: .vocabulary)
    }
    public let idioms: [Idiom]
    public let patterns: [SentencePattern]
    public let vocabulary: [Vocabulary]
    public init(id: String, createdAt: Date, text: String, sourceLanguage: Language, targetLanguage: Language,
                translation: String, instructions: String? = nil, favorite: Bool = false, idioms: [Idiom], patterns: [SentencePattern], vocabulary: [Vocabulary]) {
        self.id = id; self.createdAt = createdAt; self.text = text
        self.sourceLanguage = sourceLanguage; self.targetLanguage = targetLanguage
        self.translation = translation; self.instructions = instructions; self.favorite = favorite
        self.idioms = idioms; self.patterns = patterns; self.vocabulary = vocabulary
    }
    enum CodingKeys: String, CodingKey {
        case id, createdAt = "created_at", text, sourceLanguage = "source_language"
        case targetLanguage = "target_language", translation, instructions, favorite, idioms, patterns, vocabulary
    }
}
public struct Idiom: Codable, Sendable {
    public let expression: String
    public let meaning: String
    public let example: String
}
public struct SentencePattern: Codable, Sendable {
    public let pattern: String
    public let explanation: String
}
public struct Vocabulary: Codable, Sendable {
    public let word: String
    public let meaning: String
}
public struct TranslationHistory: Decodable, Sendable {
    public let items: [TranslationRecord]
}
public enum APIJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected RFC3339 date")
        }
        return decoder
    }
}
