import Foundation

public enum ConsoleModuleID: String, Sendable, Codable, CaseIterable {
    case limits, prompter, dictation, calendar, translate, shelf, media
}

/// Кто занимает свёрнутый Пульт, сверху вниз. Порядок не настраивается.
/// По умолчанию там лимиты: их вытесняют только запись, встреча и тревога. Музыка и полка видны точками.
public enum ConsolePriority: Int, Sendable, Comparable, CaseIterable {
    case activeMode = 0, meetingSoon, limitCritical, limitsNormal, music, shelf

    public static func < (lhs: ConsolePriority, rhs: ConsolePriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Кольцо в капсуле: заполнение — самое тесное окно сервиса.
public struct CapsuleRing: Sendable, Equatable, Identifiable {
    public var id: String { service.rawValue }
    public var service: LimitService
    /// nil — нет данных: пустое кольцо, а не 0%.
    public var fraction: Double?
    public var zone: LimitZone
    public var stale: Bool

    public init(service: LimitService, fraction: Double?, zone: LimitZone, stale: Bool) {
        self.service = service
        self.fraction = fraction
        self.zone = zone
        self.stale = stale
    }
}

/// Кнопка в капсуле.
public enum CapsuleAction: Sendable, Equatable {
    case join(URL)
}

/// Что модуль кладёт в свёрнутую капсулу.
public struct CapsuleContent: Sendable, Equatable {
    public var rings: [CapsuleRing]
    /// Строка, видная и без наведения: встреча, трек, файлы.
    public var text: String?
    /// Хвост строки, который не обрезается: обратный отсчёт важнее названия.
    public var tail: String?
    /// Иконка Solar.
    public var icon: String?
    public var action: CapsuleAction?
    /// Подпись при наведении, одна строка.
    public var label: String
    /// Чьё кольцо стоит рядом с подписью: на два кольца и текст 220 pt не хватает.
    public var labelService: LimitService?
    /// Живая волна вместо текста: идёт диктовка.
    public var wave: Bool

    public init(
        rings: [CapsuleRing], label: String, labelService: LimitService? = nil, text: String? = nil, tail: String? = nil,
        icon: String? = nil, action: CapsuleAction? = nil, wave: Bool = false
    ) {
        self.wave = wave
        self.tail = tail
        self.rings = rings
        self.label = label
        self.labelService = labelService
        self.text = text
        self.icon = icon
        self.action = action
    }
}

/// Новый модуль — одна регистрация, ядро не трогается. Мозг маскота получает от него только `ToolSignal`.
public protocol ConsoleModule: Sendable {
    var id: ConsoleModuleID { get }
    var title: String { get }
    /// Цвет модуля — только как акцент: точка-индикатор.
    var accent: UInt32 { get }
    /// nil — модулю сейчас нечего показать.
    func priority(now: Date) -> ConsolePriority?
    func capsule(now: Date) -> CapsuleContent
    mutating func tick(now: Date) -> [ToolSignal]
    /// Модулю нужна тишина маскота прямо сейчас.
    func wantsQuiet(now: Date) -> Bool
}

extension ConsoleModule {
    public func wantsQuiet(now: Date) -> Bool { false }
}
