import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public enum SentenceSegmenter {
    public static func sentences(in text: String) -> [String] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        #if canImport(NaturalLanguage)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = clean
        var result: [String] = []
        tokenizer.enumerateTokens(in: clean.startIndex..<clean.endIndex) { range, _ in
            let sentence = String(clean[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        return result
        #else
        let regex = try! NSRegularExpression(pattern: #"[^.!?\n]+(?:[.!?]+|$)"#)
        return regex.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)).compactMap {
            guard let range = Range($0.range, in: clean) else { return nil }
            let sentence = String(clean[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence.isEmpty ? nil : sentence
        }
        #endif
    }
}
