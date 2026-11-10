import Foundation

/// Сервис с лимитами. OpenCode Go вне Р1: чтение ключа и сетевой запрос нарушают правило приватности.
public enum LimitService: String, Codable, Sendable, CaseIterable, Hashable {
    case claude, codex

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// Акцент кольца, sRGB hex.
    public var color: UInt32 {
        switch self {
        case .claude: 0xD97757
        case .codex: 0x10A37F
        }
    }

    /// Сервис идёт к мозгу числом: в `Signal` нет строк.
    public var signalValue: Double {
        switch self {
        case .claude: 0
        case .codex: 1
        }
    }

    /// Симулятор шлёт сигнал без значения — это Claude.
    public init(signalValue: Double?) {
        self = signalValue == 1 ? .codex : .claude
    }

    /// Чей лимит упёрся: агент из Orca сюда не попадает, его признак лимита не подтверждён.
    public init?(source: AgentEvent.Source) {
        switch source {
        case .claudeCode: self = .claude
        case .codex: self = .codex
        default: return nil
        }
    }
}

public enum LimitWindowKind: String, Codable, Sendable, CaseIterable, Hashable {
    case fiveHour, week

    public var title: String {
        switch self {
        case .fiveHour: "5 часов"
        case .week: "Неделя"
        }
    }
}

/// Процент везде означает расход, а не остаток: так он приходит из `used_percentage`.
public struct LimitWindow: Codable, Sendable, Equatable {
    public var kind: LimitWindowKind
    public var usedPercent: Double
    public var resetsAt: Date?
    public var observedAt: Date?

    public init(kind: LimitWindowKind, usedPercent: Double, resetsAt: Date?, observedAt: Date? = nil) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
    }
}

public struct LimitSnapshot: Codable, Sendable, Equatable {
    public var service: LimitService
    public var windows: [LimitWindow]
    public var at: Date

    public init(service: LimitService, windows: [LimitWindow], at: Date) {
        self.service = service
        self.windows = windows
        self.at = at
    }
}

public enum LimitZone: Int, Sendable, Comparable, CaseIterable {
    case normal, attention, critical, exhausted

    public static func < (lhs: LimitZone, rhs: LimitZone) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Порог входа, %.
    var threshold: Double {
        switch self {
        case .normal: 0
        case .attention: LimitsBook.attentionAt
        case .critical: LimitsBook.criticalAt
        case .exhausted: 100
        }
    }

    static func entered(_ used: Double) -> LimitZone {
        allCases.last { used >= $0.threshold } ?? .normal
    }

    /// Гистерезис: зона держится, пока расход не упал на 5 п. п. ниже её порога, иначе реакция мигает.
    func next(_ used: Double) -> LimitZone {
        var zone = self
        while zone > .normal, used < zone.threshold - LimitsBook.exitMargin {
            zone = LimitZone(rawValue: zone.rawValue - 1) ?? .normal
        }
        return max(zone, Self.entered(used))
    }
}

/// Что показать про одно окно на этот момент.
public struct LimitReading: Sendable, Equatable {
    public var service: LimitService
    public var kind: LimitWindowKind
    public var usedPercent: Int
    public var resetsAt: Date?
    public var zone: LimitZone
    /// Данные старше 30 мин: кольцо приглушено, подпись «давно не обновлялось».
    public var stale: Bool
}

/// Лимиты всех сервисов: снимки, зоны с гистерезисом, сброс по времени. Чистая структура — тестируется на виртуальных часах.
public struct LimitsBook: Sendable, Equatable {
    public static let attentionAt = 80.0
    public static let criticalAt = 95.0
    public static let exitMargin = 5.0
    public static let staleAfter: TimeInterval = 30 * 60

    private struct Key: Hashable {
        let service: LimitService
        let kind: LimitWindowKind
    }

    public private(set) var snapshots: [LimitService: LimitSnapshot] = [:]
    private var zones: [Key: LimitZone] = [:]
    /// Агент встал по лимиту: отдыхаем до сброса окна.
    public private(set) var resting: Set<LimitService> = []

    public init() {}

    /// Новый снимок. Устаревший игнорируем; окна, которых в нём нет, остаются от прошлого.
    public mutating func ingest(_ snapshot: LimitSnapshot, now: Date) -> [ToolSignal] {
        var signals: [ToolSignal] = []
        var merged = snapshots[snapshot.service]
        if let current = merged, current.at > snapshot.at { return [] }
        var windows = merged?.windows ?? []
        for window in snapshot.windows {
            windows.removeAll { $0.kind == window.kind }
            var received = window
            received.observedAt = min(window.observedAt ?? snapshot.at, snapshot.at)
            windows.append(received)
        }
        merged = LimitSnapshot(service: snapshot.service, windows: windows, at: snapshot.at)
        snapshots[snapshot.service] = merged

        for window in snapshot.windows {
            let key = Key(service: snapshot.service, kind: window.kind)
            let before = zones[key] ?? .normal
            let after = before.next(Self.used(window, now: now))
            zones[key] = after
            guard after > before else { continue }
            switch after {
            case .attention: signals.append(.limitLow(snapshot.service))
            case .critical, .exhausted: signals.append(.limitCritical(snapshot.service))
            case .normal: break
            }
        }
        return signals
    }

    /// Сброс считается по `resetsAt`, а не по новому снимку: кольцо обнуляется в срок, даже если агент молчит.
    public mutating func tick(now: Date) -> [ToolSignal] {
        var signals: [ToolSignal] = []
        for service in LimitService.allCases {
            guard var snapshot = snapshots[service] else { continue }
            var changed = false
            for index in snapshot.windows.indices {
                let window = snapshot.windows[index]
                guard let resetsAt = window.resetsAt, resetsAt <= now, window.usedPercent > 0 else { continue }
                let key = Key(service: service, kind: window.kind)
                let wasExhausted = (zones[key] ?? .normal) == .exhausted
                snapshot.windows[index].usedPercent = 0
                snapshot.windows[index].resetsAt = nil
                zones[key] = .normal
                changed = true
                if wasExhausted || resting.contains(service) {
                    resting.remove(service)
                    signals.append(.limitRestored(service))
                }
            }
            if changed { snapshots[service] = snapshot }
        }
        return signals
    }

    /// Агент упёрся в лимит: признак приходит событием, без догадок по снимку.
    public mutating func markResting(_ service: LimitService) -> [ToolSignal] {
        resting.insert(service).inserted ? [.limitResting(service)] : []
    }

    static func used(_ window: LimitWindow, now: Date) -> Double {
        if let resetsAt = window.resetsAt, resetsAt <= now { return 0 }
        return window.usedPercent
    }

    public func reading(_ service: LimitService, _ kind: LimitWindowKind, now: Date) -> LimitReading? {
        guard let snapshot = snapshots[service], let window = snapshot.windows.first(where: { $0.kind == kind }) else { return nil }
        let expired = window.resetsAt.map { $0 <= now } ?? false
        return LimitReading(
            service: service, kind: kind, usedPercent: Int(Self.used(window, now: now).rounded()),
            resetsAt: expired ? nil : window.resetsAt, zone: expired ? .normal : zones[Key(service: service, kind: kind)] ?? .normal,
            stale: now.timeIntervalSince(window.observedAt ?? snapshot.at) > Self.staleAfter
        )
    }

    /// Самое тесное окно сервиса: оно заполняет кольцо.
    public func tightest(_ service: LimitService, now: Date) -> LimitReading? {
        LimitWindowKind.allCases.compactMap { reading(service, $0, now: now) }.max { $0.usedPercent < $1.usedPercent }
    }

    /// Сервис в зоне «критично», исчерпан или отдыхает.
    public func isCritical(_ service: LimitService, now: Date) -> Bool {
        resting.contains(service) || LimitWindowKind.allCases.contains { (reading(service, $0, now: now)?.zone ?? .normal) >= .critical }
    }
}

/// Подписи лимитов. Формат один: «Claude · 76% · сброс 19:00».
public enum LimitText {
    public static let noData = "нет данных"
    public static let stale = "давно не обновлялось"

    public static func label(_ reading: LimitReading, now: Date, calendar: Calendar = .current) -> String {
        var parts = [reading.service.title, "\(reading.usedPercent)%"]
        if let resetsAt = reading.resetsAt { parts.append("сброс \(clock(resetsAt, now: now, calendar: calendar))") }
        return parts.joined(separator: " · ")
    }

    /// Под шкалой места мало: сегодня — «19:00», дальше — «4 д 6 ч».
    public static func gaugeReset(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) || date.timeIntervalSince(now) < 12 * 3600 {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
        let text = countdown(date, now: now)
        return text.hasPrefix("через ") ? String(text.dropFirst(6)) : text
    }

    /// Пятичасовое окно показывает оставшееся ожидание; недельное — дату/время сброса.
    public static func gaugeReset(_ reading: LimitReading, now: Date, calendar: Calendar = .current) -> String {
        guard let resetsAt = reading.resetsAt else { return " " }
        guard reading.kind == .fiveHour else { return gaugeReset(resetsAt, now: now, calendar: calendar) }
        let text = countdown(resetsAt, now: now)
        return text.hasPrefix("через ") ? String(text.dropFirst(6)) : text
    }

    /// «19:00» сегодня, «пт 19:00» на другой день.
    public static func clock(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        guard !calendar.isDate(date, inSameDayAs: now) else { return time }
        let names = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
        return "\(names[calendar.component(.weekday, from: date) - 1]) \(time)"
    }

    /// Обратный отсчёт: «через 2 ч 14 мин», «через 3 д 4 ч», «меньше минуты».
    public static func countdown(_ date: Date, now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes < 1 { return "меньше минуты" }
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        if hours == 0 { return "через \(rest) мин" }
        let (days, hoursLeft) = hours.quotientAndRemainder(dividingBy: 24)
        if days == 0 { return rest == 0 ? "через \(hours) ч" : "через \(hours) ч \(rest) мин" }
        return hoursLeft == 0 ? "через \(days) д" : "через \(days) д \(hoursLeft) ч"
    }
}

/// Только проценты, время сброса и дата получения. После перезапуска данные не становятся свежими.
extension LimitsBook {
    public static var cacheURL: URL { PulsePaths.supportDirectory.appending(path: "limits.json") }

    public static func load(from url: URL = cacheURL, now: Date = Date()) -> LimitsBook {
        var book = LimitsBook()
        guard let data = try? Data(contentsOf: url),
              let snapshots = try? JSONDecoder().decode([LimitSnapshot].self, from: data) else { return book }
        for snapshot in snapshots.sorted(by: { $0.at < $1.at }) {
            guard snapshot.at <= now, now.timeIntervalSince(snapshot.at) <= 30 * 24 * 60 * 60,
                  snapshot.windows.allSatisfy({ $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) }) else { continue }
            // Зоны восстанавливаются без отправки повторных тревог мозгу.
            _ = book.ingest(snapshot, now: now)
        }
        _ = book.tick(now: now)
        return book
    }

    public func save(to url: URL = cacheURL) {
        guard let data = try? JSONEncoder().encode(Array(snapshots.values)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
    }
}
