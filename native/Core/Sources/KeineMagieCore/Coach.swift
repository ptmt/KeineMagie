import Foundation

public struct CoachAction: Codable, Sendable {
    public let requestID: String
    public let action: String
    public let text: String
    public let turnID: String
    public let locale: String
    public let ownerID: String?
    public init(requestID: String = UUID().uuidString, action: String, text: String = "", turnID: String = "", locale: String, ownerID: String? = nil) {
        self.requestID = requestID; self.action = action; self.text = text; self.turnID = turnID; self.locale = locale; self.ownerID = ownerID
    }
    enum CodingKeys: String, CodingKey { case requestID = "request_id", action, text, turnID = "turn_id", locale, ownerID = "owner_id" }
}
public struct CoachAssessment: Codable, Sendable {
    public let verdict: String; public let correctedAnswer: String; public let explanation: String; public let uncertaintyReason: String
    enum CodingKeys: String, CodingKey { case verdict, correctedAnswer = "corrected_answer", explanation, uncertaintyReason = "uncertainty_reason" }
}
public struct CoachAttempt: Codable, Sendable {
    public let id: String; public let answer: String; public let outcome: String; public let originalOutcome: String
    public let assisted: Bool; public let at: String; public let reviewedAt: String?; public let excluded: Bool
    public let assessmentState: String?; public let assessment: CoachAssessment?; public let assessmentError: String?; public let sent: Bool?
    public var feedbackKey: String {
        if let state = assessmentState, state != "completed" { return "coach.assessment." + state }
        return "coach." + (excluded ? "excluded" : reviewedAt != nil ? outcome : assessment?.verdict ?? outcome)
    }
    public var canRecheck: Bool { outcome != "skipped" && assessmentState != "pending" && assessmentState != "completed" }
    enum CodingKeys: String, CodingKey { case id, answer, outcome, originalOutcome = "original_outcome", assisted, at, reviewedAt = "reviewed_at", excluded, assessmentState = "assessment_state", assessment, assessmentError = "assessment_error", sent }
}
public struct CoachTurn: Codable, Sendable, Identifiable {
    public let id: String; public let text: String; public let state: String; public let at: String
    public let assisted: Bool; public let language: String
    public let message: String?; public let kind: String?; public let prompt: String?; public let target: String?
    public let sourceID: String?; public let quote: String?; public let explanation: String?; public var attempt: CoachAttempt?
    enum CodingKeys: String, CodingKey { case id, text, state, at, assisted, language, message, kind, prompt, target, sourceID = "source_id", quote, explanation, attempt }
}
extension CoachTurn {
    public var showsInstruction: Bool {
        guard let message, !message.isEmpty else { return false }
        guard ["cloze", "preposition_case"].contains(kind ?? ""), prompt?.contains("___") == true else { return true }
        let generic = #"^(fill in (the )?missing (preposition|word)|ergänze (die fehlende präposition|den satz)|вставьте пропущенн(ый предлог|ое слово)|completa la preposición que falta|complète la préposition manquante)[.!]?$"#
        return message.trimmingCharacters(in: .whitespacesAndNewlines).range(of: generic, options: [.regularExpression, .caseInsensitive]) == nil
    }
}
public struct CoachObservation: Codable, Sendable, Identifiable {
    public var id: String { language + ":" + target }
    public let target: String; public let language: String; public let count: Int; public let distinctExamples: Int
    public let correct: Int; public let needsPractice: Int; public let assisted: Int; public let confidence: String; public let lastAt: String
    enum CodingKeys: String, CodingKey { case target, language, count, distinctExamples = "distinct_examples", correct, needsPractice = "needs_practice", assisted, confidence, lastAt = "last_at" }
}
public struct CoachSnapshot: Codable, Sendable {
    public var turns: [CoachTurn]; public let observations: [CoachObservation]; public let model: String; public let resetAt: String?
    enum CodingKeys: String, CodingKey { case turns, observations, model, resetAt = "reset_at" }
}
extension CoachSnapshot {
    /// Local display/cache only. Server assessment remains authoritative.
    public func pendingAssessment(_ input: CoachAction) -> CoachSnapshot {
        guard ["answer", "recheck"].contains(input.action), let index = turns.firstIndex(where: { $0.id == input.turnID }) else { return self }
        var value = self
        let prior = turns[index].attempt
        value.turns[index].attempt = CoachAttempt(id: input.requestID, answer: input.action == "answer" ? input.text : prior?.answer ?? "", outcome: "ambiguous", originalOutcome: "ambiguous", assisted: input.action == "answer" ? turns[index].assisted : prior?.assisted ?? false, at: ISO8601DateFormatter().string(from: Date()), reviewedAt: nil, excluded: false, assessmentState: "pending", assessment: nil, assessmentError: nil, sent: nil)
        return value
    }
}
public enum CoachSourceTarget: Equatable, Sendable {
    case translation(String), passage(String, Int)
    public init?(_ source: String) {
        let parts = source.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts[1].range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { return nil }
        if parts.count == 2, parts[0] == "translation" { self = .translation(parts[1]); return }
        if parts.count == 3, parts[0] == "passage", parts[2].range(of: "^(0|[1-9][0-9]{0,3})$", options: .regularExpression) != nil, let index = Int(parts[2]) { self = .passage(parts[1], index); return }
        return nil
    }
}
public struct CoachServiceError: Error, Sendable { public let status: Int; public let message: String }
