import Foundation

/// Разметка исполняется только в явно включённом режиме; обычная диктовка буквальная.
public enum DictationFormatting {
    public static func apply(_ source: String, enabled: Bool) -> String {
        guard enabled else { return source }
        let commands = [
            ("новый абзац|new paragraph", "\n\n"),
            ("новая строка|new line", "\n"),
            ("новый пункт|new item", "\n• "),
        ]
        var text = source
        for (words, replacement) in commands {
            let pattern = "(?<![\\p{L}\\p{N}])(?:" + words + ")(?![\\p{L}\\p{N}])[.,!?]?"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range, in: text) else { continue }
                text.replaceSubrange(range, with: replacement)
            }
        }
        text = text.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
