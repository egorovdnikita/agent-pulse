import Foundation

/// Эти команды разбираются только в отдельном режиме исправления, никогда в обычной диктовке.
public enum DictationCorrection: Sendable, Equatable {
    case lastWord(String)
    case phrase(String, String)

    public static func parse(_ utterance: String) -> Self? {
        var text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(".") { text.removeLast() }
        let input = text as NSString
        for pattern in [#"^(?:замени|замените)\s+последнее\s+слово\s+на\s+(.+)$"#, #"^replace\s+(?:the\s+)?last\s+word\s+with\s+(.+)$"#] {
            if let match = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive).firstMatch(in: text, range: NSRange(location: 0, length: input.length)) {
                let replacement = input.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if !replacement.isEmpty { return .lastWord(replacement) }
            }
        }
        for pattern in [#"^(?:замени|замените)\s+(.+?)\s+на\s+(.+)$"#, #"^replace\s+(.+?)\s+with\s+(.+)$"#] {
            if let match = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive).firstMatch(in: text, range: NSRange(location: 0, length: input.length)) {
                let quotes = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "«»\"“”"))
                let old = input.substring(with: match.range(at: 1)).trimmingCharacters(in: quotes)
                let new = input.substring(with: match.range(at: 2)).trimmingCharacters(in: quotes)
                if !old.isEmpty, !new.isEmpty { return .phrase(old, new) }
            }
        }
        return nil
    }

    public func applying(to text: String) -> String? {
        let pattern: String
        let replacement: String
        switch self {
        case .lastWord(let word):
            pattern = #"[\p{L}\p{N}][\p{L}\p{N}\p{M}'’\-]*"#
            replacement = word
        case .phrase(let old, let new):
            pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: old) + #"(?![\p{L}\p{N}])"#
            replacement = new
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range, in: text) else { return nil }
        return text.replacingCharacters(in: range, with: replacement)
    }
}
