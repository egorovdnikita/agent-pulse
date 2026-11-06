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
    /// Встреча скоро. Раз на встречу, без названия.
    case meetingSoon
    /// Встреча через минуту: тревога Пульта, мозгу не нужна.
    case meetingLastCall
    /// На сегодня встреч больше нет.
    case dayFree
    /// Файл на полке: маскот смотрит на Пульт. Что за файл, мозг не знает.
    case shelfChanged
    /// Маскот съел брошенный на него файл.
    case fileEaten
    /// Модуль включил или снял тишину.
    case quiet(Bool)

    public static let all: [ToolSignal] = LimitService.allCases.flatMap { service in
        [ToolSignal.limitLow(service), .limitCritical(service), .limitResting(service), .limitRestored(service)]
    } + [.meetingSoon, .meetingLastCall, .dayFree, .shelfChanged, .fileEaten, .quiet(true), .quiet(false)]

    /// Сигнал для мозга; nil — только Пульту.
    public func signal(at date: Date) -> Signal? {
        switch self {
        case .limitLow(let service): Signal(.console, .limitLow, value: service.signalValue, ts: date)
        case .limitCritical(let service): Signal(.console, .limitCritical, value: service.signalValue, ts: date)
        case .limitResting(let service): Signal(.console, .limitResting, value: service.signalValue, ts: date)
        case .limitRestored(let service): Signal(.console, .limitRestored, value: service.signalValue, ts: date)
        case .meetingSoon: Signal(.console, .meetingSoon, ts: date)
        case .dayFree: Signal(.console, .dayFree, ts: date)
        case .fileEaten: Signal(.console, .fileEaten, ts: date)
        case .quiet(let on): Signal(.console, on ? .quietOn : .quietOff, ts: date)
        case .meetingLastCall, .shelfChanged: nil
        }
    }

    /// Разовая тревога в капсуле.
    public var isAlert: Bool {
        switch self {
        case .limitCritical, .limitResting, .meetingLastCall: true
        default: false
        }
    }

    /// Маскот на мгновение смотрит на Пульт.
    public var drawsGlance: Bool { self == .shelfChanged }
}
