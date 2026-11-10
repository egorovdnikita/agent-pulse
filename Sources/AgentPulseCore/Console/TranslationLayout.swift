import Foundation

/// Разметка остаётся локально, переводятся только текстовые части.
public struct TranslationLayout: Sendable {
    public enum Segment: Sendable { case literal(String), text(String) }
    public let segments: [Segment]
    public var texts: [String] { segments.compactMap { if case .text(let text) = $0 { text } else { nil } } }

    public init(_ source: String, protectedTerms: [String] = []) {
        let input = source as NSString
        let lines = try! NSRegularExpression(pattern: #"([^\r\n]*)(\r\n|\r|\n|$)"#)
        let prefix = try! NSRegularExpression(pattern: #"^[ \t]*(?:(?:#{1,6}|[-*+]|\d+[.)]|>)[ \t]+)?"#)
        var result: [Segment] = []
        var fence: (Character, Int)?
        for match in lines.matches(in: source, range: NSRange(location: 0, length: input.length)) where match.range.length > 0 {
            let line = input.substring(with: match.range(at: 1))
            let newline = input.substring(with: match.range(at: 2))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.first
            let count = marker.map { first in trimmed.prefix(while: { $0 == first }).count } ?? 0
            if let active = fence {
                result.append(.literal(line + newline))
                if marker == active.0, count >= active.1 { fence = nil }
                continue
            }
            if let marker, (marker == "`" || marker == "~"), count >= 3 {
                fence = (marker, count)
                result.append(.literal(line + newline))
                continue
            }
            let nsLine = line as NSString
            let start = prefix.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length))?.range.length ?? 0
            if start > 0 { result.append(.literal(nsLine.substring(to: start))) }
            Self.appendProtectedText(nsLine.substring(from: start), terms: protectedTerms, to: &result)
            if !newline.isEmpty { result.append(.literal(newline)) }
        }
        segments = result
    }

    private static func appendProtectedText(_ raw: String, terms: [String], to result: inout [Segment]) {
        let termPattern = terms.filter { !$0.isEmpty }.sorted { $0.count > $1.count }.map { "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: $0) + "(?![\\p{L}\\p{N}_])" }.joined(separator: "|")
        let regex = try! NSRegularExpression(pattern: (termPattern.isEmpty ? "" : termPattern + "|") + #"`+[^`\r\n]*`+|https?://[^\s<>()]+|\[[^\]\r\n]*\]\([^\)\r\n]*\)"#)
        let input = raw as NSString
        var cursor = 0
        for match in regex.matches(in: raw, range: NSRange(location: 0, length: input.length)) {
            appendText(input.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), to: &result)
            result.append(.literal(input.substring(with: match.range)))
            cursor = NSMaxRange(match.range)
        }
        appendText(input.substring(from: cursor), to: &result)
    }

    private static func appendText(_ raw: String, to result: inout [Segment]) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { if !raw.isEmpty { result.append(.literal(raw)) }; return }
        let leading = String(raw.prefix(while: \.isWhitespace))
        let trailing = String(raw.reversed().prefix(while: \.isWhitespace).reversed())
        if !leading.isEmpty { result.append(.literal(leading)) }
        result.append(.text(text))
        if !trailing.isEmpty { result.append(.literal(trailing)) }
    }

    public func assembling(_ translated: [String]) -> String? {
        guard translated.count == texts.count else { return nil }
        var index = 0
        return segments.map { segment in
            switch segment {
            case .literal(let text): return text
            case .text:
                defer { index += 1 }
                return translated[index]
            }
        }.joined()
    }
}
