import Foundation

/// Additive transport only. Native assessment presentation is not implemented here.
public struct DictationAssessmentReceipt: Codable, Sendable {
 public let id: String
 public let revision: Int
 public let source: String
 public let answer: String
 public let at: String
 public let assisted: Bool
 public let replayTracking: String
 public let assistanceSummary: DictationAssistanceSummary?
 public let alignment: DictationAlignment
 public let state: String
 public let sent: Bool
 public let error: String?
 public let model: String?
 public let result: DictationAssessmentResult?
 enum CodingKeys: String, CodingKey { case id, revision, source, answer, at, assisted, alignment, state, sent, error, model, result; case replayTracking = "replay_tracking", assistanceSummary = "assistance_summary" }
}
public struct DictationAlignment: Codable, Sendable {
 public let version: Int
 public let complete: Bool
 public let spans: [DictationAlignmentSpan]
 public let sourceWords: Int
 public let attemptedWords: Int
 public let exactWords: Int
 public let omissions: Int
 public let additions: Int
 public let substitutions: Int
 public let unattemptedWords: Int
 enum CodingKeys: String, CodingKey { case version, complete, spans, omissions, additions, substitutions; case sourceWords = "source_words", attemptedWords = "attempted_words", exactWords = "exact_words", unattemptedWords = "unattempted_words" }
}
public struct DictationAlignmentSpan: Codable, Sendable {
 public let id: String
 public let kind: String
 /// Byte offsets into UTF-8, not Swift Character or UTF-16 indices.
 public let sourceStart: Int
 public let sourceEnd: Int
 public let answerStart: Int
 public let answerEnd: Int
 public let original: String
 public let written: String
 enum CodingKeys: String, CodingKey { case id, kind, original, written; case sourceStart = "source_start", sourceEnd = "source_end", answerStart = "answer_start", answerEnd = "answer_end" }
}
public struct DictationAssessmentResult: Codable, Sendable { public let notes: [DictationAssessmentNote] }
public struct DictationAssessmentNote: Codable, Sendable {
 public let spanID: String
 public let category: String
 public let sourceQuote: String
 public let answerQuote: String
 public let explanation: String
 enum CodingKeys: String, CodingKey { case category, explanation; case spanID = "span_id", sourceQuote = "source_quote", answerQuote = "answer_quote" }
}
