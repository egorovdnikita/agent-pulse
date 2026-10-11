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

    public mutating func reset() {
        days.removeAll()
    }
}
