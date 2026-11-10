import Foundation
import NaturalLanguage

extension PrompterScript {
    /// Начало предложения, содержащего текущее слово; системная сегментация понимает сокращения.
    public func sentenceStart(at word: Int) -> Int {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return 0 }
        let index = min(max(0, word), tokens.count - 1)
        let position = tokens[index].startIndex
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let sentence = tokenizer.tokenRange(at: position)
        return tokens.prefix { $0.startIndex < sentence.lowerBound }.count
    }
}

extension PrompterModule {
    public mutating func restartSentence(now: Date) {
        guard isActive else { return }
        let beginning = script.sentenceStart(at: word)
        seek(toFraction: Double(beginning) / Double(max(1, script.words.count)), now: now)
    }
}
