import AgentPulseCore
import Foundation

/// Орган чувств: слушает систему и сообщает сигналы. Не знает про тело и голос.
/// Новый орган = один файл в `Senses/` + регистрация в `SenseRegistry`.
@MainActor
protocol Sense: AnyObject {
    var id: SenseID { get }
    func start(emit: @escaping @Sendable (Signal) -> Void)
    func stop()
}

@MainActor
enum SenseRegistry {
    /// Какие органы включены — по настройкам `senses`.
    static func make(_ config: PulseConfig, news: @escaping @MainActor ([NewsItem]) -> Void) -> [Sense] {
        var senses: [Sense] = []
        if config.senses.body {
            senses += [PowerSense(), ThermalSense(), MemorySense(), DiskSense(), NetworkSense(), DisplaySense(), KeyboardSense()]
        }
        if config.senses.rhythm {
            senses += [SleepWakeSense(), PresenceSense(), ClockSense(), AppearanceSense(), SpaceSense()]
        }
        if config.senses.audio {
            senses += [AudioSense()]
        }
        senses.append(QuietSense())
        if config.character.designNews {
            senses.append(NewsSense(deliver: news))
        }
        if config.senses.experimental {
            senses.append(LidAngleSense())
        }
        return senses
    }
}
