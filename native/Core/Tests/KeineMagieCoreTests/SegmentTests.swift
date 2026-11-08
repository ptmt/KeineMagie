import Testing
@testable import KeineMagieCore

@Test func segmentsGermanAndRussianWithoutLosingText() {
    #expect(SentenceSegmenter.sentences(in: "  Hallo Welt! Wie geht es dir?\nSehr gut.  ") == ["Hallo Welt!", "Wie geht es dir?", "Sehr gut."])
    #expect(SentenceSegmenter.sentences(in: "Привет! Как дела? Всё хорошо.") == ["Привет!", "Как дела?", "Всё хорошо."])
    #expect(SentenceSegmenter.sentences(in: " \n ").isEmpty)
    #expect(SentenceSegmenter.sentences(in: "Noch kein Punkt") == ["Noch kein Punkt"])
}
