import AgentPulseCore
import Foundation

/// Моргание со случайным интервалом: закрытие 70 ms, открытие 110 ms, иногда двойное.
struct BlinkEngine {
    private var starts: [Double] = []
    private var nextAt: Double = 0

    mutating func trigger(at t: Double, double: Bool, tuning: MascotTuning) {
        let length = tuning.blinkClose + tuning.blinkOpen
        // Не накладываем моргания друг на друга.
        let first = max(t, (starts.last ?? -.infinity) + length)
        starts.append(first)
        if double {
            starts.append(first + length + tuning.doubleBlinkGap)
        }
    }

    /// `interval == nil` — самопроизвольно не моргает (сон).
    mutating func update(t: Double, interval: ClosedRange<Double>?, context: inout BehaviorContext) {
        let tuning = context.tuning
        starts.removeAll { $0 + tuning.blinkClose + tuning.blinkOpen < t }
        guard let interval else {
            nextAt = 0
            return
        }
        if nextAt == 0 {
            nextAt = t + context.random(interval)
        }
        // Состояние сменилось на более «моргучее» — не ждём старый длинный интервал.
        nextAt = min(nextAt, t + interval.upperBound)
        if t >= nextAt {
            trigger(at: t, double: context.chance(tuning.doubleBlinkChance), tuning: tuning)
            nextAt = t + context.random(interval)
        }
    }

    /// 1 — открыты, 0 — закрыты.
    func openness(at t: Double, tuning: MascotTuning) -> Double {
        for start in starts where t >= start {
            let elapsed = t - start
            if elapsed < tuning.blinkClose {
                return 1 - elapsed / tuning.blinkClose
            }
            if elapsed < tuning.blinkClose + tuning.blinkOpen {
                return (elapsed - tuning.blinkClose) / tuning.blinkOpen
            }
        }
        return 1
    }
}
