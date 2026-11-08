import Foundation

/// Обезличенный сигнал Пульта для мозга маскота: без текста и имён файлов.
/// Перечисление без строк — это проверяется тестом.
public enum ToolSignal: Sendable, Equatable, Hashable {
    case limitLow(LimitService)
    case limitCritical(LimitService)
    /// Агент упёрся в лимит и отдыхает до сброса.
    case limitResting(LimitService)
    /// Окно сброшено после исчерпания.
    case limitRestored(LimitService)
    /// Файл на полке: маскот смотрит на Пульт. Что за файл, мозг не знает.
    case shelfChanged
    /// Маскот съел брошенный на него файл.
    case fileEaten
    /// Модуль включил или снял тишину.
    case quiet(Bool)

    public static let all: [ToolSignal] = LimitService.allCases.flatMap { service in
        [ToolSignal.limitLow(service), .limitCritical(service), .limitResting(service), .limitRestored(service)]
    } + [.shelfChanged, .fileEaten, .quiet(true), .quiet(false)]

    /// Сигнал для мозга; nil — только Пульту.
    public func signal(at date: Date) -> Signal? {
        switch self {
        case .limitLow(let service): Signal(.console, .limitLow, value: service.signalValue, ts: date)
        case .limitCritical(let service): Signal(.console, .limitCritical, value: service.signalValue, ts: date)
        case .limitResting(let service): Signal(.console, .limitResting, value: service.signalValue, ts: date)
        case .limitRestored(let service): Signal(.console, .limitRestored, value: service.signalValue, ts: date)
        case .fileEaten: Signal(.console, .fileEaten, ts: date)
        case .quiet(let on): Signal(.console, on ? .quietOn : .quietOff, ts: date)
        case .shelfChanged: nil
        }
    }

    /// Разовая тревога в капсуле.
    public var isAlert: Bool {
        switch self {
        case .limitCritical, .limitResting: true
        default: false
        }
    }

    /// Маскот на мгновение смотрит на Пульт.
    public var drawsGlance: Bool { self == .shelfChanged }
}
