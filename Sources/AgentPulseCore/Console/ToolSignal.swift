import Foundation

/// Обезличенный сигнал Пульта для мозга маскота: без текста, названий встреч, треков и файлов.
/// Перечисление без строк — это проверяется тестом.
public enum ToolSignal: Sendable, Equatable, Hashable {
    case limitLow(LimitService)
    case limitCritical(LimitService)
    /// Агент упёрся в лимит и отдыхает до сброса.
    case limitResting(LimitService)
    /// Окно сброшено после исчерпания.
    case limitRestored(LimitService)

    public static let all: [ToolSignal] = LimitService.allCases.flatMap { service in
        [.limitLow(service), .limitCritical(service), .limitResting(service), .limitRestored(service)]
    }

    public var service: LimitService {
        switch self {
        case .limitLow(let service), .limitCritical(let service), .limitResting(let service), .limitRestored(let service): service
        }
    }

    public var kind: SignalKind {
        switch self {
        case .limitLow: .limitLow
        case .limitCritical: .limitCritical
        case .limitResting: .limitResting
        case .limitRestored: .limitRestored
        }
    }

    public func signal(at date: Date) -> Signal {
        Signal(.console, kind, value: service.signalValue, ts: date)
    }

    /// Разовая тревога в капсуле: критичная зона.
    public var isAlert: Bool {
        switch self {
        case .limitCritical, .limitResting: true
        case .limitLow, .limitRestored: false
        }
    }
}
