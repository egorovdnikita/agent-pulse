import Foundation

/// Случайная реплика из пула; одна и та же не повторяется дважды подряд.
public struct PhrasePicker: Sendable {
    private var last: [BubbleTrigger: String] = [:]

    public init() {}

    public mutating func pick<G: RandomNumberGenerator>(_ trigger: BubbleTrigger, using rng: inout G) -> String {
        let pool = Phrases.pool(for: trigger)
        let candidates = pool.count > 1 ? pool.filter { $0 != last[trigger] } : pool
        let phrase = candidates.randomElement(using: &rng) ?? ""
        last[trigger] = phrase
        return phrase
    }
}
