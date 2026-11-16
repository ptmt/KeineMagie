import Foundation
import Testing
@testable import KeineMagieCore

@Test func followupActualGoWire() throws {
    guard let path = ProcessInfo.processInfo.environment["KM_NATIVE_FOLLOWUP_WIRE"] else { return }
    let records = try APIJSON.decoder().decode([TranslationRecord].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    #expect(records.count == 2)
    #expect(records[0].followups.isEmpty)
    #expect(records[1].followups.count == 3)
    #expect(records[1].followups[0].revisedText == nil)
    #expect(records[1].followups[1].proposalSource(original: records[1].text) == "текущий текст")
    #expect(records[1].followups[2].proposalSource(original: records[1].text) == "предложение")
    #expect(try JSONDecoder().decode([TranslationRecord].self, from: JSONEncoder().encode(records))[1].followups.count == 3)
}

@Test func followupWireNullableAndLegacyPair() throws {
    let json = #"{"id":"saved","created_at":"2026-11-16T12:00:00Z","text":"original","source_language":"ru","target_language":"de","translation":"Original","idioms":[],"patterns":[],"vocabulary":[],"followups":[{"request_id":"one","question":"why?","answer":"Explanation","revised_text":"Proposal","current_source":"captured source","created_at":"2026-11-16T12:00:01Z"}]}"#
    let record = try APIJSON.decoder().decode(TranslationRecord.self, from: Data(json.utf8))
    #expect(record.followups.count == 1)
    #expect(record.followups[0].proposalSource(original: record.text) == "captured source")
    let nullable = json.replacingOccurrences(of: #"[{"request_id"# + json.components(separatedBy: #"[{"request_id"#)[1], with: "null}")
    #expect(try APIJSON.decoder().decode(TranslationRecord.self, from: Data(nullable.utf8)).followups.isEmpty)
}
@Test func followupRequestUsesBearerExactContextAndRuneLimits() throws {
    let client = APIClient(endpoint: try ServerEndpoint("https://synthetic.invalid"), token: "synthetic")
    let input = TranslationFollowupInput(historyID: "saved", question: String(repeating: "e\u{301}", count: 1000), locale: "ru", expectedTurns: 0, currentSource: "исходный\n", currentTranslation: "Ergebnis\n")
    let request = try client.translationFollowupRequest(input, owner: "owner")
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/v1/translation-followups")
    #expect(request.timeoutInterval == 90)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
    #expect(request.value(forHTTPHeaderField: "X-CSRF-Token") == nil)
    #expect(request.value(forHTTPHeaderField: "X-Translation-Owner") == "owner")
    let body = try JSONDecoder().decode(TranslationFollowupInput.self, from: request.httpBody!)
    #expect(body.currentSource == "исходный\n")
    #expect(body.requestID == input.requestID)
    let invalid = TranslationFollowupInput(historyID: "saved", question: String(repeating: "e\u{301}", count: 1001), locale: "ru", expectedTurns: 0, currentSource: "s", currentTranslation: "t")
    #expect(throws: APIError.self) { try client.translationFollowupRequest(invalid, owner: "owner") }
}
