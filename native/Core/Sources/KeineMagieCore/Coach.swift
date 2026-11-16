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
    // Cache-only receipt recovery. Never sent as part of an API snapshot.
    public var localRequest: CoachAction? = nil
    public var localPriorAttemptID: String? = nil
    public var localRetryAllowed: Bool? = nil
    public var feedbackKey: String {
        if let state = assessmentState, state != "completed" { return "coach.assessment." + state }
        return "coach." + (excluded ? "excluded" : reviewedAt != nil ? outcome : assessment?.verdict ?? outcome)
    }
    public var canRecheck: Bool { localRequest != nil || (outcome != "skipped" && assessmentState != "pending" && assessmentState != "completed") }
    enum CodingKeys: String, CodingKey { case id, answer, outcome, originalOutcome = "original_outcome", assisted, at, reviewedAt = "reviewed_at", excluded, assessmentState = "assessment_state", assessment, assessmentError = "assessment_error", sent, localRequest, localPriorAttemptID, localRetryAllowed }
}
public struct CoachTurn: Codable, Sendable, Identifiable {
    public var isOffer: Bool?; public var sourceReveals: Int?; public var answerReveals: Int?; public var messageVersion: String?; public var seenVersion: String?
    public var id: String; public let text: String; public let state: String; public let at: String?
    public let assisted: Bool; public let language: String
    public let message: String?; public let kind: String?; public let prompt: String?; public let target: String?
    public let sourceID: String?; public let quote: String?; public let explanation: String?; public var attempt: CoachAttempt?
    enum CodingKeys: String, CodingKey { case isOffer = "is_offer", sourceReveals = "source_reveals", answerReveals = "answer_reveals", messageVersion = "message_version", seenVersion = "seen_version", id, text, state, at, assisted, language, message, kind, prompt, target, sourceID = "source_id", quote, explanation, attempt }
}
extension CoachTurn {
    /// Display-only rolling day. Unknown/future dates remain visible; never erase data.
    public func isRecent(now: Date = Date()) -> Bool {
        let dates = [at, attempt?.at, attempt?.reviewedAt].compactMap { value -> Date? in
            guard let value else { return nil }
            return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value)) ?? (try? Date.ISO8601FormatStyle().parse(value))
        }
        guard let latest = dates.max() else { return true }
        return latest >= now.addingTimeInterval(-86400)
    }
    public static func historyWindow(_ turns: [CoachTurn], now: Date, earlierLimit: Int) -> [CoachTurn] {
        let classified = turns.map { ($0, $0.isRecent(now: now)) }
        let older = classified.filter { !$0.1 }
        let olderIDs = Set(older.suffix(max(0, earlierLimit)).prefix(min(50, max(0, older.count - earlierLimit + 50))).map { $0.0.id })
        return classified.filter { $0.1 || olderIDs.contains($0.0.id) }.map(\.0)
    }
    public var presentationStatus: String {
        if state == "pending" || attempt?.assessmentState == "pending" { return "working" }
        if attempt?.outcome == "skipped" { return "unanswered" }
        return attempt == nil ? "awaiting" : "completed"
    }
    public var isUnread: Bool { state == "completed" && messageVersion != nil && messageVersion != seenVersion }
    public func masksAnswer(latestID: String?) -> Bool { attempt != nil && id != latestID && (answerReveals ?? 0) == 0 }
    public var showsInstruction: Bool {
        guard attempt == nil, let message, !message.isEmpty else { return false }
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
public struct CoachQuickAction: Codable, Sendable {
    public let action: String; public let turnID: String
    enum CodingKeys: String, CodingKey { case action, turnID = "turn_id" }
}
public struct CoachSnapshot: Codable, Sendable {
    public var actions: [CoachQuickAction]? = nil
    public var quickActions: [CoachQuickAction] { actions ?? (turns.isEmpty ? [CoachQuickAction(action: "practice", turnID: "")] : []) }
    public var turns: [CoachTurn]; public let observations: [CoachObservation]; public let model: String; public let resetAt: String?
    enum CodingKeys: String, CodingKey { case actions, turns, observations, model, resetAt = "reset_at" }
}
extension CoachSnapshot {
    /// Local display/cache only. Server assessment remains authoritative.
    public func pendingAssessment(_ input: CoachAction) -> CoachSnapshot {
        guard ["answer", "recheck"].contains(input.action), let index = turns.firstIndex(where: { $0.id == input.turnID }) else { return self }
        var value = self
        let prior = turns[index].attempt
        if prior?.localRequest?.requestID == input.requestID { return self }
        value.turns[index].attempt = CoachAttempt(id: input.requestID, answer: input.action == "answer" ? input.text : prior?.answer ?? "", outcome: "ambiguous", originalOutcome: "ambiguous", assisted: input.action == "answer" ? turns[index].assisted : prior?.assisted ?? false, at: ISO8601DateFormatter().string(from: Date()), reviewedAt: nil, excluded: false, assessmentState: "pending", assessment: nil, assessmentError: nil, sent: nil)
        value.turns[index].attempt?.localRequest = input
        value.turns[index].attempt?.localPriorAttemptID = prior?.id
        return value
    }

    /// Reconcile a read or unrelated write without treating an older recheck result
    /// (or a missing/reset exercise) as acknowledgement of a local request.
    public func preservingUnacknowledged(from local: CoachSnapshot?, removing requestID: String? = nil) -> CoachSnapshot {
        var value = self
        for var turn in local?.turns ?? [] {
            guard var attempt = turn.attempt, attempt.id != requestID else { continue }
            // Migrate snapshots saved before recovery metadata existed. A matching
            // server attempt still takes precedence, including server pending state.
            if attempt.localRequest == nil, attempt.assessmentState == "pending", attempt.sent == nil {
                attempt.localRequest = CoachAction(requestID: attempt.id, action: "answer", text: attempt.answer, turnID: turn.id, locale: "en")
            }
            guard let request = attempt.localRequest else { continue }
            let index = value.turns.firstIndex { $0.id == request.turnID }
            let remote = index.map { value.turns[$0] }
            if remote?.attempt?.id == request.requestID { continue }
            // Preserve the old acknowledged attempt separately when it cannot be
            // the predecessor of this request. Recovery must never overwrite it.
            let predecessor = remote?.attempt?.id == attempt.localPriorAttemptID
            attempt.localRetryAllowed = remote?.state == "completed" && predecessor
            turn.attempt = attempt
            if let index, predecessor {
                value.turns[index].attempt = attempt
            } else {
                if index != nil { turn.id = "local-" + request.requestID }
                value.turns.append(turn)
            }
        }
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
