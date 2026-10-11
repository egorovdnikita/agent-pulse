import Foundation

/// Настроение: четыре оси 0…1, затухают к нейтрали 0.5 с полураспадом ~30 мин.
/// Само реплик не порождает — окрашивает движение (`Baseline`), выбор реплик и шутки (`moodGate`).
public struct Mood: Sendable, Equatable, Codable {
    public var energy = 0.5
    public var stress = 0.5
    public var joy = 0.5
    public var social = 0.5

    public static let halfLife: TimeInterval = 30 * 60

    public init(energy: Double = 0.5, stress: Double = 0.5, joy: Double = 0.5, social: Double = 0.5) {
        self.energy = energy
        self.stress = stress
        self.joy = joy
        self.social = social
    }

    public mutating func decay(over seconds: TimeInterval) {
        guard seconds > 0 else { return }
        let factor = pow(0.5, seconds / Self.halfLife)
        energy = 0.5 + (energy - 0.5) * factor
        stress = 0.5 + (stress - 0.5) * factor
        joy = 0.5 + (joy - 0.5) * factor
        social = 0.5 + (social - 0.5) * factor
    }

    /// Как сигнал сдвигает настроение. Таблица из паспорта.
    public mutating func feel(_ signal: Signal, hour: Int) {
        func bump(_ axis: WritableKeyPath<Mood, Double>, _ delta: Double) {
            self[keyPath: axis] = min(1, max(0, self[keyPath: axis] + delta))
        }
        switch signal.kind {
        case .systemWake, .chargerConnected: bump(\.energy, 0.1)
        case .batteryLow, .batteryCritical: bump(\.energy, -0.15)
        case .uptimeLong, .longWork: bump(\.energy, -0.12)
        case .minute where hour < 5: bump(\.energy, -0.01)
        case .minute where (6..<11).contains(hour): bump(\.energy, 0.005)
        case .thermalHigh: bump(\.stress, 0.2)
        case .memoryPressure: bump(\.stress, 0.15)
        case .diskLow: bump(\.stress, 0.1)
        case .agentError: bump(\.stress, 0.15); bump(\.joy, -0.05)
        case .agentErrorStreak: bump(\.joy, -0.2)
        case .agentDone: bump(\.stress, -0.1); bump(\.joy, 0.1)
        case .thermalNormal, .memoryNormal, .diskOK: bump(\.stress, -0.1)
        case .stroke: bump(\.joy, 0.15); bump(\.social, 0.1)
        case .poke: bump(\.joy, -0.1); bump(\.social, 0.05)
        case .dragged, .dropped: bump(\.social, 0.05)
        case .userBack:
            bump(\.social, 0.1)
            if (signal.value ?? 0) > 3600 { bump(\.social, 0.1) }
        case .userAway: bump(\.social, -0.1)
        default: break
        }
    }
}
