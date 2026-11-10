import Foundation

/// Явная разметка доклада. Команды допустимы только отдельной строкой и при включённом режиме.
public struct PrompterScore: Sendable {
    public let text: String
    public let pauses: [Int: TimeInterval]
    public init(_ source: String) {
        var lines: [String] = []
        var pauses: [Int: TimeInterval] = [:]
        var count = 0
        let regex = try! NSRegularExpression(pattern: #"^\[(?:пауза|pause)(?:\s+([0-9]+(?:[.,][0-9]+)?))?\]$"#, options: .caseInsensitive)
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
                let value = Range(match.range(at: 1), in: trimmed).flatMap { Double(trimmed[$0].replacingOccurrences(of: ",", with: ".")) } ?? 2
                pauses[count, default: 0] = min(10, pauses[count, default: 0] + min(10, max(0.2, value)))
            } else {
                if trimmed.isEmpty, count > 0 { pauses[count] = max(1, pauses[count] ?? 0) }
                lines.append(line)
                count += line.split(whereSeparator: \.isWhitespace).count
            }
        }
        text = lines.joined(separator: "\n")
        self.pauses = pauses.filter { $0.key > 0 && $0.key < count }
    }
    public var duration: TimeInterval { pauses.values.reduce(0, +) }
}
