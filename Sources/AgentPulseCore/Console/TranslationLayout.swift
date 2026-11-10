import Foundation

/// Разметка остаётся локально, переводятся только текстовые части.
public struct TranslationLayout: Sendable {
    public enum Segment: Sendable { case literal(String), text(String) }
    public let segments: [Segment]
    public var texts: [String] { segments.compactMap { if case .text(let text) = $0 { text } else { nil } } }

    public init(_ source: String) {
        let input = source as NSString
        let lines = try! NSRegularExpression(pattern: #"([^\r\n]*)(\r\n|\r|\n|$)"#)
        let prefix = try! NSRegularExpression(pattern: #"^[ \t]*(?:(?:#{1,6}|[-*+]|\d+[.)]|>)[ \t]+)?"#)
        var result: [Segment] = []
        for match in lines.matches(in: source, range: NSRange(location: 0, length: input.length)) where match.range.length > 0 {
            let line = input.substring(with: match.range(at: 1))
            let newline = input.substring(with: match.range(at: 2))
            let nsLine = line as NSString
            let start = prefix.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length))?.range.length ?? 0
            if start > 0 { result.append(.literal(nsLine.substring(to: start))) }
            Self.appendText(nsLine.substring(from: start), to: &result)
            if !newline.isEmpty { result.append(.literal(newline)) }
        }
        segments = result
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
