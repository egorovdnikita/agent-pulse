import Foundation

/// Диапазон AX — UTF-16. Подмена разрешена лишь пока исходный фрагмент не изменился.
public struct TextReplacement: Sendable {
    public let original: String
    public let range: NSRange
    public init(original: String, range: NSRange) { self.original = original; self.range = range }
    public func matches(_ value: String) -> Bool {
        guard !original.isEmpty, range.location >= 0, range.length == original.utf16.count,
              range.location <= value.utf16.count, range.length <= value.utf16.count - range.location,
              let range = Range(range, in: value) else { return false }
        return value[range] == original
    }
    public static func inserted(_ text: String, endingAt cursor: Int, in value: String) -> TextReplacement? {
        guard cursor >= text.utf16.count else { return nil }
        let result = TextReplacement(original: text, range: NSRange(location: cursor - text.utf16.count, length: text.utf16.count))
        return result.matches(value) ? result : nil
    }
}
