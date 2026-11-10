import Foundation
import Testing
@testable import KeineMagieCore

private actor InstructionWire {
    var requests: [URLRequest] = []
    let record = #"{"id":"saved","created_at":"2026-11-09T12:00:00Z","text":"Hallo","source_language":"de","target_language":"ru","translation":"Привет","instructions":"Use a formal tone.","idioms":[],"patterns":[],"vocabulary":[]}"#
    func send(_ request: URLRequest) -> AuthResponse {
        requests.append(request)
        let body = request.httpMethod == "GET" ? "{\"items\":[\(record)]}" : record
        return AuthResponse(data: Data(body.utf8), status: 200)
    }
    func captured() -> [URLRequest] { requests }
}

@Test func actualTranslationTransportSendsBoundedStyleAndPreservesHistorySnapshot() async throws {
    let wire = InstructionWire()
    let api = APIClient(endpoint: try ServerEndpoint("https://synthetic.invalid"), token: "synthetic-account-A", transport: { await wire.send($0) })
    let instructions = String(repeating: "e\u{301}", count: 500)
    let result = try await api.translate(text: "Hallo", source: .german, instructions: instructions)
    #expect(result.instructions == "Use a formal tone.")
    let history = try await api.history()
    #expect(history.first?.instructions == "Use a formal tone.")
    do {
        _ = try await api.translate(text: "Hallo", source: .german, instructions: instructions + "a")
        Issue.record("1001 Unicode scalars must be rejected before transport")
    } catch APIError.invalidResponse { }
    let sent = await wire.captured()
    #expect(sent.count == 2)
    #expect(sent[0].httpMethod == "POST")
    #expect(sent[0].value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-account-A")
    let body = try #require(JSONSerialization.jsonObject(with: sent[0].httpBody!) as? [String: String])
    #expect(body == ["text": "Hallo", "source_language": "de", "target_language": "ru", "instructions": instructions])
    #expect(sent[1].httpMethod == "GET")
    #expect(sent[1].httpBody == nil)
    #expect(sent[1].value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-account-A")
}

@Test func legacyHistoryWithoutInstructionsStillDecodes() throws {
    let record = #"{"id":"old","created_at":"2026-11-09T12:00:00Z","text":"Hallo","source_language":"de","target_language":"ru","translation":"Привет","idioms":[],"patterns":[],"vocabulary":[]}"#
    #expect(try APIJSON.decoder().decode(TranslationRecord.self, from: Data(record.utf8)).instructions == nil)
}
