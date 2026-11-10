import Foundation

/// Исправляется только последняя подтверждённая вставка и только две минуты после неё.
public struct RecentDictation: Sendable {
    public static let lifetime: TimeInterval = 120
    public let text: String
    public let insertedAt: Date
    public init(text: String, now: Date) { self.text = text; insertedAt = now }
    public func isCurrent(now: Date) -> Bool {
        let age = now.timeIntervalSince(insertedAt)
        return !text.isEmpty && age >= 0 && age <= Self.lifetime
    }
    public func correcting(_ utterance: String, now: Date) -> String? {
        guard isCurrent(now: now) else { return nil }
        return DictationCorrection.parse(utterance)?.applying(to: text)
    }
}
