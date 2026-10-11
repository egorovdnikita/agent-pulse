import Foundation

/// Схлопывает шум: серия чтений подряд превращается в одно «Изучает проект».
public struct Aggregator: Sendable {
    public var readStreakThreshold = 3
    private var readStreak = 0

    public init() {}

    public mutating func reset() {
        readStreak = 0
    }

    public mutating func text(for kind: ToolKind, target: WorkTarget, original: String) -> String {
        guard kind == .read else {
            readStreak = 0
            return original
        }
        readStreak += 1
        guard readStreak >= readStreakThreshold else { return original }
        return target == .figma ? "Изучает макет" : "Изучает проект"
    }
}
