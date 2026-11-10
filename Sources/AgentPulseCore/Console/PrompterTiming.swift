import Foundation

public struct PrompterTiming: Sendable, Equatable {
    public let speed: Int
    public let seconds: TimeInterval
    public let limited: Bool
    public init?(words: Int, target: TimeInterval, pauses: TimeInterval = 0) {
        guard words > 0, target.isFinite, pauses.isFinite, target > pauses, pauses >= 0 else { return nil }
        let wanted = Double(words) / (target - pauses) * 60
        let lower = Double(PrompterModule.speedRange.lowerBound), upper = Double(PrompterModule.speedRange.upperBound)
        speed = Int(min(upper, max(lower, wanted)).rounded())
        seconds = Double(words) / Double(speed) * 60 + pauses
        limited = wanted < lower || wanted > upper
    }
    /// Минуты либо м:с; ввод ограничен двумя часами.
    public static func parse(_ input: String) -> TimeInterval? {
        let text = input.trimmingCharacters(in: .whitespaces)
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        let result: Double?
        if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]), minutes >= 0, minutes.rounded(.towardZero) == minutes, seconds >= 0, seconds < 60 {
            result = minutes * 60 + seconds
        } else if parts.count == 1, let minutes = Double(text.replacingOccurrences(of: ",", with: ".")) { result = minutes * 60 }
        else { result = nil }
        guard let result, result.isFinite, result >= 1, result <= 7200 else { return nil }
        return result
    }
}

extension PrompterModule {
    /// Точная скорость для времени, без округления к шагу кнопок множителя.
    public mutating func fitDuration(_ seconds: TimeInterval) -> PrompterTiming? {
        guard let timing = PrompterTiming(words: script.words.count, target: seconds, pauses: followsVoice ? 0 : markupPauseDuration) else { return nil }
        setExactSpeed(timing.speed)
        return timing
    }
}
