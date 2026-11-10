import Foundation
import Testing
@testable import KeineMagieCore

@Test func translationInstructionsAreOptionalAndBoundedWithoutChangingText() throws {
    let api = APIClient(endpoint: try ServerEndpoint("https://example.com"), token: "token")
    let old = try api.translationRequest(text: "Hallo", source: .german)
    let oldBody = try #require(JSONSerialization.jsonObject(with: old.httpBody ?? Data()) as? [String: Any])
    #expect(oldBody["instructions"] == nil)
    let instruction = String(repeating: "🙂", count: 1000)
    let request = try api.translationRequest(text: "Hallo", source: .german, instructions: instruction)
    let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
    #expect(body["instructions"] as? String == instruction)
    #expect(body["text"] as? String == "Hallo")
    #expect(body["system_prompt"] == nil)
    #expect(throws: (any Error).self) { try api.translationRequest(text: "Hallo", source: .german, instructions: instruction + "x") }
    #expect(throws: (any Error).self) { try JSONEncoder().encode(TranslationRequest(text: "Hallo", sourceLanguage: .german, instructions: String(repeating: "a", count: 1001))) }
    let blank = try api.translationRequest(text: "Hallo", source: .german, instructions: " \n")
    let blankBody = try #require(JSONSerialization.jsonObject(with: blank.httpBody ?? Data()) as? [String: Any])
    #expect(blankBody["instructions"] == nil)
}
