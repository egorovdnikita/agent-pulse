import Foundation

/// Фаза Луны без сети и геолокации: средний синодический месяц от известного новолуния.
public enum MoonPhase {
    static let synodicMonth = 29.530588853
    /// Новолуние 6 января 2000, 18:14 UTC.
    static let knownNewMoon = Date(timeIntervalSince1970: 947_182_440)

    /// Возраст Луны в днях, 0…29.5.
    public static func age(_ date: Date) -> Double {
        let days = date.timeIntervalSince(knownNewMoon) / 86_400
        let age = days.truncatingRemainder(dividingBy: synodicMonth)
        return age < 0 ? age + synodicMonth : age
    }

    /// Полнолуние — ±1 день от середины месяца.
    public static func isFull(_ date: Date) -> Bool {
        abs(age(date) - synodicMonth / 2) <= 1
    }
}

/// Сам Mac между запусками: был ли выключен внезапно, обновилась ли система.
/// Хранится локально, только служебные отметки — без содержимого.
public struct LaunchRecord: Codable, Sendable, Equatable {
    /// Время загрузки системы при прошлом запуске (секунды Unix).
    public var bootTime: Double?
    /// Приложение закрылось штатно (выход, перезагрузка, выключение).
    public var cleanExit = true
    public var osVersion: String?
    /// Первая встреча — для «Месяц вместе», «Год вместе».
    public var firstSeen: Date?
    /// Последний раз приложение было живо (отметка раз в минуту и при уходе в сон, секунды Unix).
    public var lastAlive: Double?
    /// Приложение было живо меньше чем за столько до новой загрузки — значит, погасло вместе с Mac.
    /// Упало раньше и Mac потом перезагрузили штатно — не «внезапно»: лучше промолчать, чем соврать.
    public static let aliveWindow: Double = 5 * 60

    public init() {}

    /// Что сказать на старте. Внезапно — это новая загрузка системы, а прошлый раз закрыться не успел.
    public mutating func start(bootTime: Double, osVersion: String, now: Date) -> [SignalKind] {
        var signals: [SignalKind] = []
        if let previous = self.bootTime, abs(previous - bootTime) > 5, !cleanExit,
           let alive = lastAlive, bootTime - alive < Self.aliveWindow {
            signals.append(.unexpectedRestart)
        }
        // Раньше хранилась строка на языке системы («Версия 26.6.2 (Выпуск 25G83)») — смена языка
        // выглядела бы как обновление. Теперь — «26.6.2 25G83»; старую запись просто заменяем.
        if let previous = self.osVersion, !previous.contains("("), previous != osVersion {
            signals.append(.systemUpdated)
        }
        self.bootTime = bootTime
        self.osVersion = osVersion
        if firstSeen == nil { firstSeen = now }
        cleanExit = false
        lastAlive = now.timeIntervalSince1970
        return signals
    }

    /// Версия и сборка системы без перевода на язык системы: «26.6.2 25G83».
    public static func systemVersion(_ version: OperatingSystemVersion, build: String) -> String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) \(build)"
    }

    public static var url: URL { PulsePaths.supportDirectory.appending(path: "launch.json") }

    public static func load() -> LaunchRecord {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(LaunchRecord.self, from: $0) } ?? LaunchRecord()
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
    }
}

/// Годовщины знакомства: месяц, сто дней, каждый год.
public enum Anniversary {
    public static func lines(days: Int) -> [String]? {
        switch days {
        case 30: return ["Месяц вместе", "Уже месяц вместе"]
        case 100: return ["Сто дней вместе", "Уже сто дней рядом"]
        case let d where d > 0 && d % 365 == 0:
            let years = d / 365
            return years == 1
                ? ["Год вместе", "Уже год рядом"]
                : ["\(years) \(HumanTime.plural(years, "год", "года", "лет")) вместе"]
        default: return nil
        }
    }
}

/// Сколько принято между двумя замерами счётчиков интерфейсов. Счётчики 32-битные и на быстрой загрузке
/// переполняются за минуты: разность по каждому интерфейсу берётся по модулю 2³², так переполнение не теряет замер.
public enum TrafficCounter {
    public static func received(from old: [String: UInt32], to new: [String: UInt32]) -> UInt64 {
        new.reduce(0) { total, item in
            guard let before = old[item.key] else { return total }
            return total + UInt64(item.value &- before)
        }
    }
}
