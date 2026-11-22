import XCTest
@testable import KeineMagieCore

final class CoachClueTests: XCTestCase {
    func testAdditiveClueDecodesWithoutInventingLegacyClue() throws {
        let base = #"{"id":"clue","text":"","state":"completed","assisted":false,"language":"de","kind":"cloze","prompt":"Ich mache ein ___ bei euch."}"#
        XCTAssertNil(try JSONDecoder().decode(CoachTurn.self, from: Data(base.utf8)).clue)
        for (locale, clue) in [("en","a period of practical work experience"),("ru","период практического знакомства с профессией"),("de","eine zeitlich begrenzte praktische Berufserfahrung"),("es","un periodo de formación práctica"),("fr","une période de formation pratique")] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(base.utf8)) as? [String:Any])
            object["clue"] = clue; object["clue_kind"] = "gloss"; object["clue_language"] = locale
            object["message"] = "Complete the sentence.\n" + clue
            let decoded = try JSONDecoder().decode(CoachTurn.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(decoded.instructionText, "Complete the sentence.")
            XCTAssertEqual(decoded.clue, clue); XCTAssertEqual(decoded.clueLanguage, locale); XCTAssertEqual(decoded.clueKind, "gloss")
            XCTAssertEqual(decoded.prompt, "Ich mache ein ___ bei euch.")
        }
    }
}
