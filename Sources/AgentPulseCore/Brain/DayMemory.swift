import Foundation

/// Память дня и привычек. Только агрегаты, никаких содержимых; хранится 30 дней, сбрасывается одной кнопкой.
public struct DayMemory: Sendable, Codable, Equatable {
    public struct Day: Sendable, Codable, Equatable {
        public var date: String
        public var agentTasks = 0
        public var agentErrors = 0
        public var breaks = 0
        public var strokes = 0
        public var pokes = 0
        /// Минуты от полуночи.
        public var firstPresence: Int?
        public var lastPresence: Int?

        public init(date: String) {
            self.date = date
        }
    }

    public static let retentionDays = 30
    public static let habitWindow = 14

    public private(set) var days: [Day] = []

    public init() {}

    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Сумма счётчиков за последние 7 дней, включая сегодня.
    public func week(_ now: Date, calendar: Calendar = .current) -> Day {
        let keys = Set((0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: now).map { Self.key($0, calendar: calendar) } })
        var total = Day(date: "week")
        for day in days where keys.contains(day.date) {
            total.agentTasks += day.agentTasks
            total.agentErrors += day.agentErrors
            total.breaks += day.breaks
            total.strokes += day.strokes
            total.pokes += day.pokes
        }
        return total
    }

    public func today(_ now: Date, calendar: Calendar = .current) -> Day {
        let key = Self.key(now, calendar: calendar)
        return days.last(where: { $0.date == key }) ?? Day(date: key)
    }

    public mutating func update(_ now: Date, calendar: Calendar = .current, _ change: (inout Day) -> Void) {
        let key = Self.key(now, calendar: calendar)
        if let index = days.lastIndex(where: { $0.date == key }) {
            change(&days[index])
        } else {
            var day = Day(date: key)
            change(&day)
            days.append(day)
            days = Array(days.suffix(Self.retentionDays))
        }
    }

    /// Отметить присутствие пользователя. Возвращает `true`, если это первое присутствие за день.
    @discardableResult
    public mutating func notePresence(_ now: Date, calendar: Calendar = .current) -> Bool {
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        var first = false
        update(now, calendar: calendar) { day in
            if day.firstPresence == nil {
                day.firstPresence = minutes
                first = true
            }
            day.lastPresence = minutes
        }
        return first
    }

    /// Медианное время начала дня за последние 14 дней (кроме сегодня), минуты от полуночи.
    public func medianStart(before now: Date, calendar: Calendar = .current) -> Int? {
        let todayKey = Self.key(now, calendar: calendar)
        let starts = days.filter { $0.date != todayKey }.suffix(Self.habitWindow).compactMap(\.firstPresence).sorted()
        guard starts.count >= 3 else { return nil }
        return starts[starts.count / 2]
    }

    /// Знакомство 0…1: растёт с днями рядом и поглаживаниями. Две недели вместе — уже свои.
    public var familiarity: Double {
        let together = Double(days.filter { $0.firstPresence != nil }.count)
        let strokes = Double(days.reduce(0) { $0 + $1.strokes })
        return min(1, together / 14 * 0.7 + min(1, strokes / 40) * 0.3)
    }

    /// Сколько дней прошло с прошлого присутствия (не считая сегодня).
    public func daysSinceLastVisit(before now: Date, calendar: Calendar = .current) -> Int? {
        let todayKey = Self.key(now, calendar: calendar)
        guard let last = days.last(where: { $0.date != todayKey && $0.firstPresence != nil }) else { return nil }
        let parts = last.date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return nil
        }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
    }

    public mutating func reset() {
        days.removeAll()
    }

    public static var defaultURL: URL {
        PulsePaths.supportDirectory.appending(path: "memory.json")
    }

    public static func load(from url: URL = defaultURL) -> DayMemory {
        guard let data = try? Data(contentsOf: url), let memory = try? JSONDecoder().decode(DayMemory.self, from: data) else {
            return DayMemory()
        }
        return memory
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
