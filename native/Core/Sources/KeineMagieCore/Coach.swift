import Foundation

public struct CoachAction: Codable, Sendable {
    public let requestID: String
    public let action: String
    public let text: String
    public let turnID: String
    public let locale: String
    public init(requestID: String = UUID().uuidString, action: String, text: String = "", turnID: String = "", locale: String) {
        self.requestID = requestID; self.action = action; self.text = text; self.turnID = turnID; self.locale = locale
    }
    enum CodingKeys: String, CodingKey { case requestID = "request_id", action, text, turnID = "turn_id", locale }
}
public struct CoachAttempt: Codable, Sendable {
    public let id: String; public let answer: String; public let outcome: String; public let originalOutcome: String
    public let assisted: Bool; public let at: String; public let reviewedAt: String?; public let excluded: Bool
    enum CodingKeys: String, CodingKey { case id, answer, outcome, originalOutcome = "original_outcome", assisted, at, reviewedAt = "reviewed_at", excluded }
}
public struct CoachTurn: Codable, Sendable, Identifiable {
    public let id: String; public let text: String; public let state: String; public let at: String
    public let assisted: Bool; public let language: String
    public let message: String?; public let kind: String?; public let prompt: String?; public let target: String?
    public let sourceID: String?; public let quote: String?; public let explanation: String?; public let attempt: CoachAttempt?
    enum CodingKeys: String, CodingKey { case id, text, state, at, assisted, language, message, kind, prompt, target, sourceID = "source_id", quote, explanation, attempt }
}
public struct CoachObservation: Codable, Sendable, Identifiable {
    public var id: String { language + ":" + target }
    public let target: String; public let language: String; public let count: Int; public let distinctExamples: Int
    public let correct: Int; public let needsPractice: Int; public let assisted: Int; public let confidence: String; public let lastAt: String
    enum CodingKeys: String, CodingKey { case target, language, count, distinctExamples = "distinct_examples", correct, needsPractice = "needs_practice", assisted, confidence, lastAt = "last_at" }
}
public struct CoachSnapshot: Codable, Sendable {
    public let turns: [CoachTurn]; public let observations: [CoachObservation]; public let model: String; public let resetAt: String?
    enum CodingKeys: String, CodingKey { case turns, observations, model, resetAt = "reset_at" }
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
