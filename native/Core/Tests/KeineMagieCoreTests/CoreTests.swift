import Foundation
import Testing
@testable import KeineMagieCore

@Test func translationRequestUsesContractAndSwapsLanguages() throws {
    let request = TranslationRequest(text: "Guten Tag", sourceLanguage: .german)
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: String])
    #expect(object == ["text": "Guten Tag", "source_language": "de", "target_language": "ru"])
    #expect(Language.german.opposite == .russian)
    #expect(Language.russian.opposite == .german)
    #expect(TranslationRequest(text: "Привет", sourceLanguage: .russian).targetLanguage == .german)
}

@Test func resultDecodesServerHistoryAndRFC3339Dates() throws {
    let json = #"{"items":[{"id":"abc","created_at":"2026-11-08T12:30:00.123Z","text":"Hallo","source_language":"de","target_language":"ru","translation":"Привет","idioms":[{"expression":"Daumen drücken","meaning":"Glück wünschen","example":"Ich drücke dir die Daumen."}],"patterns":[{"pattern":"Ich bin …","explanation":"Vorstellung"}],"vocabulary":[{"word":"Hallo","meaning":"Привет"}]}]}"#
    let history = try APIJSON.decoder().decode(TranslationHistory.self, from: Data(json.utf8))
    let record = try #require(history.items.first)
    #expect(record.id == "abc")
    #expect(record.translation == "Привет")
    #expect(record.idioms.first?.expression == "Daumen drücken")
    #expect(record.patterns.first?.explanation == "Vorstellung")
    #expect(record.vocabulary.first?.meaning == "Привет")
    #expect(record.createdAt.timeIntervalSince1970 > 0)
    let seconds = json.replacingOccurrences(of: ".123Z", with: "Z")
    _ = try APIJSON.decoder().decode(TranslationHistory.self, from: Data(seconds.utf8))
    #expect(throws: (any Error).self) {
        try APIJSON.decoder().decode(TranslationHistory.self, from: Data(json.replacingOccurrences(of: "2026-11-08T12:30:00.123Z", with: "bad").utf8))
    }
}
