import Foundation

public enum ConsoleModuleID: String, Sendable, Codable, CaseIterable {
    case limits, prompter, dictation, calendar, translate, shelf, media
}

/// Кто занимает свёрнутый Пульт, сверху вниз. Порядок не настраивается.
public enum ConsolePriority: Int, Sendable, Comparable, CaseIterable {
    case activeMode = 0, meetingSoon, limitCritical, music, shelf, limitsNormal

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

/// Что модуль кладёт в свёрнутую капсулу.
public struct CapsuleContent: Sendable, Equatable {
    public var rings: [CapsuleRing]
    /// Подпись при наведении, одна строка.
    public var label: String
    /// Чьё кольцо стоит рядом с подписью: на два кольца и текст 220 pt не хватает.
    public var labelService: LimitService?

    public init(rings: [CapsuleRing], label: String, labelService: LimitService? = nil) {
        self.rings = rings
        self.label = label
        self.labelService = labelService
    }
}

/// Новый модуль — одна регистрация, ядро не трогается. Мозг маскота получает от него только `ToolSignal`.
public protocol ConsoleModule: Sendable {
    var id: ConsoleModuleID { get }
    var title: String { get }
    /// nil — модулю сейчас нечего показать.
    func priority(now: Date) -> ConsolePriority?
    func capsule(now: Date) -> CapsuleContent
    mutating func tick(now: Date) -> [ToolSignal]
}
