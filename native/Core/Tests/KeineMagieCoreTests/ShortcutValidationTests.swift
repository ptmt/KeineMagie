import Foundation
import Testing
@testable import KeineMagieCore

@Test func shortcutRejectsInvalidAndCorruptPersistedInstructions() throws {
    #expect(throws: (any Error).self) { try TranslationShortcut(title: " ", instruction: "Be formal") }
    #expect(throws: (any Error).self) { try TranslationShortcut(title: "Valid", instruction: " \n") }
    #expect(throws: (any Error).self) { try TranslationShortcut(title: String(repeating: "a", count: 41), instruction: "Be formal") }
    #expect(throws: (any Error).self) { try TranslationShortcut(title: "Valid", instruction: String(repeating: "🙂", count: 1001)) }
    let id = UUID()
    let item = try TranslationShortcut(id: id, title: " Work ", instruction: " Be concise. ")
    #expect(item.title == "Work")
    #expect(item.instruction == "Be concise.")
    #expect(try JSONDecoder().decode(TranslationShortcut.self, from: JSONEncoder().encode(item)) == item)
    let invalid = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "title": "Valid", "instruction": ""])
    #expect(throws: (any Error).self) { try JSONDecoder().decode(TranslationShortcut.self, from: invalid) }
    // Swift grapheme counts differ from Go rune counts. Bound wire values by scalars.
    let composed = String(repeating: "e\u{301}", count: 501)
    #expect(throws: (any Error).self) { try TranslationShortcut(title: "Valid", instruction: composed) }
    #expect(throws: (any Error).self) { try JSONEncoder().encode(TranslationRequest(text: "Hallo", sourceLanguage: .german, instructions: composed)) }
}
