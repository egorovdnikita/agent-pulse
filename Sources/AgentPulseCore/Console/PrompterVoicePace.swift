import Foundation

/// Темп берётся только из подтверждённого продвижения по тексту, без пауз и повторов ASR.
public struct PrompterVoicePace: Sendable {
    public private(set) var estimate: Double?
    private var anchor: (word: Int, date: Date)?
    public init() {}
    public mutating func reset() { anchor = nil }
    public mutating func observe(word: Int, now: Date) -> Int? {
        guard let previous = anchor else { anchor = (word, now); return nil }
        let elapsed = now.timeIntervalSince(previous.date)
        let progress = word - previous.word
        guard elapsed >= 0, progress >= 0 else { anchor = (word, now); return nil }
        if elapsed > 3 || progress > 12 { anchor = (word, now); return nil }
        guard progress > 0, elapsed >= 0.4 else { return nil }
        anchor = (word, now)
        let sample = min(260, max(65, Double(progress) / elapsed * 60))
        let smoothed = estimate.map { $0 * 0.75 + sample * 0.25 } ?? sample
        estimate = smoothed
        return Int(smoothed.rounded())
    }
}
