import Foundation

/// Набор имени работает только в Библиотеке, без чтения глобальной клавиатуры.
public struct ShelfTypeSearch: Sendable {
    public private(set) var query = ""
    private var lastInput: Date?
    public init() {}
    public mutating func reset() { query = ""; lastInput = nil }
    public mutating func match(_ input: String, names: [String], now: Date) -> Int? {
        guard !input.isEmpty, input.allSatisfy({ !$0.isNewline && !$0.isASCIIControl }) else { return nil }
        if lastInput.map({ now.timeIntervalSince($0) < 0 || now.timeIntervalSince($0) > 1 }) ?? true { query = "" }
        lastInput = now
        query += input
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if let index = names.firstIndex(where: { $0.range(of: query, options: options)?.lowerBound == $0.startIndex }) { return index }
        return names.firstIndex { $0.range(of: query, options: options) != nil }
    }
}

private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}
