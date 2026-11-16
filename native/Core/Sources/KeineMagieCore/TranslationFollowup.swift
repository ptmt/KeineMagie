import Foundation

public struct TranslationFollowup: Codable, Identifiable, Sendable {
    public let requestID: String
    public var id: String { requestID }
    public let question: String
    public let answer: String
    public let revisedText: String?
    public let revisedSourceText: String?
    public let currentSource: String?
    public let currentTranslation: String?
    public let createdAt: Date
    public func proposalSource(original: String) -> String { revisedSourceText ?? currentSource ?? original }
    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", question, answer, revisedText = "revised_text"
        case revisedSourceText = "revised_source_text", currentSource = "current_source"
        case currentTranslation = "current_translation", createdAt = "created_at"
    }
}

/// Immutable accepted snapshot. Retry reuses this entire body, not a new request ID.
public struct TranslationFollowupInput: Codable, Equatable, Sendable {
    public let historyID: String
    public let requestID: String
    public let question: String
    public let locale: String
    public let expectedTurns: Int
    public let currentSource: String
    public let currentTranslation: String
    public init(historyID: String, requestID: String = UUID().uuidString, question: String, locale: String, expectedTurns: Int, currentSource: String, currentTranslation: String) {
        self.historyID = historyID; self.requestID = requestID; self.question = question; self.locale = locale
        self.expectedTurns = expectedTurns; self.currentSource = currentSource; self.currentTranslation = currentTranslation
    }
    public var isValid: Bool {
        !historyID.isEmpty && historyID.utf8.count <= 128 && !historyID.contains(where: { $0 == "/" || $0 == "\\" }) &&
        !requestID.isEmpty && requestID.utf8.count <= 128 && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        question.unicodeScalars.count <= 2000 && (0..<6).contains(expectedTurns) &&
        ["en", "de", "ru", "es", "fr"].contains(locale) && currentSource.unicodeScalars.count <= 8000 && currentTranslation.unicodeScalars.count <= 8000
    }
    public func validates(_ record: TranslationRecord, original: TranslationRecord) -> Bool {
        record.id == historyID && record.text == original.text && record.translation == original.translation &&
        record.sourceLanguage == original.sourceLanguage && record.targetLanguage == original.targetLanguage &&
        record.instructions == original.instructions &&
        record.followups.count > expectedTurns && record.followups.count <= 6 &&
        record.followups.prefix(original.followups.count).map(\.requestID) == original.followups.map(\.requestID) &&
        record.followups.contains { $0.requestID == requestID && $0.question == question && $0.currentSource == currentSource && $0.currentTranslation == currentTranslation } &&
        Set(record.followups.map(\.requestID)).count == record.followups.count &&
        record.followups.allSatisfy { turn in
            !turn.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && turn.answer.unicodeScalars.count <= 12000 &&
            (turn.revisedText == nil || (!turn.revisedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && turn.revisedText!.unicodeScalars.count <= 16000)) &&
            (turn.revisedSourceText == nil || (turn.revisedText != nil && !turn.revisedSourceText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && turn.revisedSourceText!.unicodeScalars.count <= 8000))
        }
    }
    enum CodingKeys: String, CodingKey {
        case historyID = "history_id", requestID = "request_id", question, locale, expectedTurns = "expected_turns"
        case currentSource = "current_source", currentTranslation = "current_translation"
    }
}

/// Owner-scoped cache only; never grants identity or starts work on restoration.
public struct TranslationDiscussionDraft: Codable, Sendable {
    public var question: String
    public var request: TranslationFollowupInput?
    public init(question: String = "", request: TranslationFollowupInput? = nil) { self.question = question; self.request = request }
}
