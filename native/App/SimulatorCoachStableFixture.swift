#if targetEnvironment(simulator)
import Foundation
import KeineMagieCore

/// Explicit synthetic transport for native presentation acceptance; never live AI.
actor SimulatorCoachStableFixture {
    private var attempt: [String: Any]?
    private var discussion = false
    func send(_ request: URLRequest) async throws -> AuthResponse {
        if request.httpMethod == "POST", let body = request.httpBody {
            let action = try JSONDecoder().decode(CoachAction.self, from: body)
            if action.action == "answer" || action.action == "recheck" {
                let recheck = action.action == "recheck"
                let answer = recheck ? (attempt?["answer"] as? String ?? "") : action.text
                let at = recheck ? (attempt?["at"] as? String ?? "") : ISO8601DateFormatter().string(from: Date())
                attempt = ["id": action.requestID, "answer": answer, "outcome": "ambiguous", "original_outcome": "ambiguous", "assisted": false, "excluded": false, "at": at, "assessment_state": "pending"]
                try await Task.sleep(for: .seconds(8))
                if ProcessInfo.processInfo.environment["KM_COACH_STABLE_ERROR"] == "1" { return AuthResponse(data: Data(), status: 503) }
                guard attempt?["assessment_state"] as? String == "pending" else { return try snapshot() }
                let clueFixture = ProcessInfo.processInfo.environment["KM_COACH_STABLE_CLUE"] == "1"
                if clueFixture && !recheck {
                    attempt?["assessment_state"] = "failed"
                    attempt?["assessment_error"] = "Synthetic assessment unavailable."
                    return try snapshot()
                }
                let correct = ProcessInfo.processInfo.environment["KM_COACH_STABLE_CORRECT"] == "1" || clueFixture
                attempt?["assessment_state"] = "completed"
                attempt?["outcome"] = correct ? "correct" : "wrong"
                attempt?["original_outcome"] = correct ? "correct" : "wrong"
                attempt?["assessment"] = ["verdict": correct ? "correct" : "incorrect", "corrected_answer": clueFixture ? "Praktikum" : "pick up", "explanation": recheck ? "Recheck kept the exact answer and clue." : correct ? "Both collect and pick up fit this context." : "Here abholen means to collect or pick up the parcel.", "uncertainty_reason": ""]
            }
            if action.action == "cancel", attempt?["id"] as? String == action.turnID { attempt?["assessment_state"] = "canceled" }
            if action.action == "message" { discussion = true }
        }
        return try snapshot()
    }
    private func snapshot() throws -> AuthResponse {
        var current: [String: Any] = ["id":"stable-word", "text":"", "state":"completed", "at":"2020-01-02T00:00:00Z", "language":"de", "assisted":false, "kind":"context_translation", "prompt":"Ich muss das Paket abholen.", "target_text":"abholen", "answer_language":"en", "target":"vocabulary.word_choice", "message":"Translate only the highlighted word into English.", "source_id":"translation:synthetic", "answer_reveals":1]
        if ProcessInfo.processInfo.environment["KM_COACH_STABLE_CLUE"] == "1" {
            current["kind"] = "cloze"
            current["prompt"] = "Ich mache ein ___ bei euch."
            current["target"] = "vocabulary.word_choice"
            current["target_text"] = nil; current["answer_language"] = nil
            current["message"] = "Complete the sentence.\na period of practical work experience"
            current["clue"] = "a period of practical work experience"
            current["clue_kind"] = "gloss"; current["clue_language"] = "en"
        }
        if let attempt { current["attempt"] = attempt }
        let archived: [String: Any] = ["id":"stable-archive", "text":"", "state":"completed", "at":"2020-01-01T00:00:00Z", "language":"de", "assisted":false, "kind":"clarification", "message":"Archived synthetic conversation remains collapsed."]
        var turns = [archived, current]
        if discussion { turns.append(["id":"stable-discussion", "text":"Discussion draft", "state":"completed", "at":ISO8601DateFormatter().string(from: Date()), "language":"de", "assisted":false, "kind":"clarification", "message":"Synthetic discussion response, not an answer check."]) }
        return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["turns":turns, "observations":[], "model":"synthetic-only", "actions":[["action":"progress", "turn_id":""], ["action":"reveal", "turn_id":"stable-word"]]]), status:200)
    }
}
#endif
