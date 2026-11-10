import Foundation

/// Выделенный фрагмент с проверкой UTF-16 границ; никакого чтения чужих окон.
public struct TextFragment: Sendable, Equatable {
    public let source: String
    public let range: NSRange
    public let text: String
    public init?(source: String, range: NSRange) {
        guard range.length > 0, let indices = Range(range, in: source) else { return nil }
        let selected = String(source[indices])
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.source = source; self.range = range; text = selected
    }
    public func replacing(with result: String, in current: String) -> String? {
        guard current == source, let indices = Range(range, in: current) else { return nil }
        var output = current
        output.replaceSubrange(indices, with: result)
        return output
    }
}
