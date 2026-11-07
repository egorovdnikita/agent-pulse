import Foundation

// Что показывают день, неделя и месяц страницы «Календарь». Решается здесь и проверяется тестами,
// приложение только рисует. Устройство страницы — по CapaTheNotch (MIT).

public extension MeetingEvent {
    func isRunning(at now: Date) -> Bool { start <= now && end > now }
}

/// Один день сетки.
public struct CalendarGridDay: Equatable, Identifiable, Sendable {
    public var id: Date { start }
    /// Полночь этого дня.
    public let start: Date
    public let number: Int
    /// Понедельник 0 … воскресенье 6.
    public let weekdayIndex: Int
    public let isToday: Bool
    /// Показанного месяца; в неделе всегда true.
    public let isInMonth: Bool
    public let events: [MeetingEvent]

    public var isWeekend: Bool { weekdayIndex >= 5 }

    /// Цвета календарей этого дня: каждый один раз, не больше трёх.
    public var dots: [UInt32?] {
        var colors: [UInt32?] = []
        for event in events where !colors.contains(event.color) {
            colors.append(event.color)
            if colors.count == 3 { break }
        }
        return colors
    }
}

public enum CalendarGrid {
    public static func weekdayIndex(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    static func adding(_ days: Int, to start: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86_400))
    }

    /// Что в этот день: сначала на весь день, потом по времени. Сегодня — только то, что ещё не кончилось.
    public static func agenda(on start: Date, in events: [MeetingEvent], at now: Date, calendar: Calendar) -> [MeetingEvent] {
        let end = adding(1, to: start, calendar: calendar)
        let isToday = start <= now && now < end
        return events
            .filter { $0.start < end && ($0.end > start || $0.start >= start) && (!isToday || $0.end > now) }
            .sorted { $0.isAllDay != $1.isAllDay ? $0.isAllDay : $0.start < $1.start }
    }

    static func day(_ start: Date, inMonth: Bool, events: [MeetingEvent], now: Date, calendar: Calendar) -> CalendarGridDay {
        CalendarGridDay(
            start: start, number: calendar.component(.day, from: start), weekdayIndex: weekdayIndex(of: start, calendar: calendar),
            isToday: start == calendar.startOfDay(for: now), isInMonth: inMonth,
            events: agenda(on: start, in: events, at: now, calendar: calendar)
        )
    }
}

/// День: ближайшее событие крупно, остальное списком. Прошедшего нет.
public struct CalendarDayPlan: Equatable, Sendable {
    public let featured: MeetingEvent?
    public let rest: [MeetingEvent]

    public init(events: [MeetingEvent], at now: Date, calendar: Calendar = .current) {
        let left = CalendarGrid.agenda(on: calendar.startOfDay(for: now), in: events, at: now, calendar: calendar)
        let timed = left.filter { !$0.isAllDay }
        let featured = timed.first { $0.start > now } ?? timed.last { $0.isRunning(at: now) }
        self.featured = featured
        rest = left.filter { $0.id != featured?.id }
    }

    public var isEmpty: Bool { featured == nil && rest.isEmpty }
}

/// Неделя — семь дней от сегодня: что впереди, а не календарная неделя.
public struct CalendarWeekPlan: Equatable, Sendable {
    public let days: [CalendarGridDay]
    public let start: Date
    public let end: Date
    /// Первое событие после этих семи дней.
    public let next: MeetingEvent?

    public init(events: [MeetingEvent], at now: Date, calendar: Calendar = .current) {
        start = calendar.startOfDay(for: now)
        end = CalendarGrid.adding(7, to: start, calendar: calendar)
        let first = start
        days = (0..<7).map {
            CalendarGrid.day(CalendarGrid.adding($0, to: first, calendar: calendar), inMonth: true, events: events, now: now, calendar: calendar)
        }
        next = CalendarAhead.first(after: end, in: events, calendar: calendar)
    }

    /// Событие на несколько дней считается один раз.
    public var eventCount: Int { Set(days.flatMap { $0.events.map(\.id) }).count }
    public var isFree: Bool { days.allSatisfy(\.events.isEmpty) }
}

/// Сколько событий помещается в колонку недели; остальное — «ещё N».
public enum CalendarChips {
    public static let maximum = 3

    public static func fit(_ events: [MeetingEvent]) -> (shown: [MeetingEvent], more: Int) {
        let shown = Array(events.prefix(maximum))
        return (shown, events.count - shown.count)
    }
}

/// Сетка текущего месяца, понедельник первым: пять или шесть недель.
public struct CalendarMonthPlan: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let weeks: [[CalendarGridDay]]

    public init(events: [MeetingEvent], at now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let parts = calendar.dateComponents([.year, .month], from: today)
        year = parts.year ?? 0
        month = parts.month ?? 1
        let first = calendar.date(from: parts) ?? today
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let last = CalendarGrid.adding(count - 1, to: first, calendar: calendar)
        let start = CalendarGrid.adding(-CalendarGrid.weekdayIndex(of: first, calendar: calendar), to: first, calendar: calendar)
        let total = CalendarGrid.weekdayIndex(of: first, calendar: calendar) + count + 6 - CalendarGrid.weekdayIndex(of: last, calendar: calendar)
        let days = (0..<total).map { offset -> CalendarGridDay in
            let day = CalendarGrid.adding(offset, to: start, calendar: calendar)
            return CalendarGrid.day(day, inMonth: calendar.component(.month, from: day) == parts.month, events: events, now: now, calendar: calendar)
        }
        weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    /// День, выбранный кликом; пока его нет в сетке — сегодня.
    public func selected(_ chosen: Date, calendar: Calendar = .current) -> CalendarGridDay? {
        let start = calendar.startOfDay(for: chosen)
        let all = weeks.flatMap { $0 }
        return all.first { $0.start == start } ?? all.first(where: \.isToday)
    }
}

/// Размеры сетки: она заполняет высоту вида при любом числе недель.
public struct CalendarMonthMetrics: Equatable, Sendable {
    public static let dotSize = 3.0

    public let weekdayHeight = 14.0
    public let rowHeight: Double
    /// Квадрат числа и круг сегодняшнего или выбранного дня.
    public let numberFrame: Double

    public init(weeks: Int, height: Double) {
        rowHeight = min(((height - weekdayHeight) / Double(max(weeks, 1))).rounded(.down), 26)
        numberFrame = min(rowHeight - Self.dotSize - 1, 20)
    }
}

public enum CalendarAhead {
    /// Первое событие не раньше этого момента: в его дне сначала с временем, потом на весь день.
    public static func first(after moment: Date, in events: [MeetingEvent], calendar: Calendar = .current) -> MeetingEvent? {
        let coming = events.filter { $0.start >= moment }
        guard let earliest = coming.min(by: { $0.start < $1.start }) else { return nil }
        let day = coming.filter { calendar.isDate($0.start, inSameDayAs: earliest.start) }.sorted { $0.start < $1.start }
        return day.first { !$0.isAllDay } ?? day.first
    }
}

/// Слова страницы.
public enum CalendarWords {
    private static let weekdays = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
    private static let months = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
    private static let monthsIn = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    public static func weekday(_ index: Int) -> String { weekdays[min(max(index, 0), 6)] }
    public static func month(_ number: Int) -> String { months[min(max(number - 1, 0), 11)] }

    /// «вс, 8 ноября».
    public static func date(_ date: Date, calendar: Calendar = .current) -> String {
        let index = CalendarGrid.weekdayIndex(of: date, calendar: calendar)
        let month = calendar.component(.month, from: date)
        return "\(weekday(index)), \(calendar.component(.day, from: date)) \(monthsIn[min(max(month - 1, 0), 11)])"
    }

    /// «8-14.11», через месяц — «28.09-4.10».
    public static func weekRange(_ week: CalendarWeekPlan, calendar: Calendar = .current) -> String {
        let last = CalendarGrid.adding(-1, to: week.end, calendar: calendar)
        let (a, b) = (calendar.component(.month, from: week.start), calendar.component(.month, from: last))
        let two = { (number: Int) in number < 10 ? "0\(number)" : "\(number)" }
        let (from, to) = (calendar.component(.day, from: week.start), calendar.component(.day, from: last))
        return a == b ? "\(from)-\(to).\(two(b))" : "\(from).\(two(a))-\(to).\(two(b))"
    }

    /// «1 встреча», «3 встречи», «14 встреч», «нет встреч».
    public static func count(_ count: Int) -> String {
        count == 0 ? "нет встреч" : "\(count) \(HumanTime.plural(count, "встреча", "встречи", "встреч"))"
    }

    public static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    public static func range(_ event: MeetingEvent, calendar: Calendar = .current) -> String {
        event.isAllDay ? "Весь день" : "\(time(event.start, calendar: calendar))–\(time(event.end, calendar: calendar))"
    }

    /// «Через 8 мин», «Через 1 ч 20 мин», «Сейчас, ещё 25 мин».
    public static func relative(_ event: MeetingEvent, at now: Date) -> String {
        if event.isAllDay { return "Весь день" }
        if event.start > now {
            let minutes = max(Int((event.start.timeIntervalSince(now) / 60).rounded(.up)), 1)
            if minutes < 60 { return "Через \(minutes) мин" }
            return minutes % 60 == 0 ? "Через \(minutes / 60) ч" : "Через \(minutes / 60) ч \(minutes % 60) мин"
        }
        return "Сейчас, ещё \(max(Int((event.end.timeIntervalSince(now) / 60).rounded(.up)), 1)) мин"
    }

    /// «Ближайшее — завтра, 10:00 · Стендап», «Ближайшее — пн, 12 октября, 10:00 · Стендап», «Впереди пусто».
    public static func hint(_ next: MeetingEvent?, at now: Date, calendar: Calendar = .current) -> String {
        guard let next else { return "Впереди пусто" }
        let hour = next.isAllDay ? "весь день" : time(next.start, calendar: calendar)
        let tomorrow = calendar.isDate(next.start, inSameDayAs: CalendarGrid.adding(1, to: calendar.startOfDay(for: now), calendar: calendar))
        return "Ближайшее — \(tomorrow ? "завтра" : date(next.start, calendar: calendar)), \(hour) · \(next.title)"
    }
}
