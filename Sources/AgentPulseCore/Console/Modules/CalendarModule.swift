import Foundation

/// Событие календаря. Читается из EventKit и живёт только в памяти; события не пишутся и не меняются.
public struct MeetingEvent: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var link: MeetingLink?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, link: MeetingLink? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.link = link
    }

    /// Только такое событие глушит маскота: блок «Работа» на весь день его не трогает.
    public var isCall: Bool { link != nil && !isAllDay }
}

/// Следующая встреча: лидер за 10 мин до начала, «Войти», если есть ссылка; идущий звонок — тишина маскота.
public struct CalendarModule: ConsoleModule {
    public static let soonWindow: TimeInterval = 10 * 60
    public static let lastCall: TimeInterval = 60
    /// Опоздал — кнопка ещё нужна.
    public static let lateWindow: TimeInterval = 5 * 60

    public let id = ConsoleModuleID.calendar
    public let title = "Календарь"
    public let accent: UInt32 = 0xFF9500
    public private(set) var events: [MeetingEvent] = []
    private var announced: Set<String> = []
    private var lastCalled: Set<String> = []
    private var freeDay: DateComponents?
    public var calendar = Calendar.current

    public init() {}

    public mutating func update(events: [MeetingEvent]) {
        self.events = events.sorted { $0.start < $1.start }
    }

    /// Ближайшая встреча, которая сейчас занимает капсулу.
    public func next(now: Date) -> MeetingEvent? {
        events.first { event in
            guard !event.isAllDay else { return false }
            let until = event.start.timeIntervalSince(now)
            return until <= Self.soonWindow && until > -Self.lateWindow && event.end > now
        }
    }

    public func priority(now: Date) -> ConsolePriority? {
        next(now: now) == nil ? nil : .meetingSoon
    }

    public func capsule(now: Date) -> CapsuleContent {
        guard let event = next(now: now) else { return CapsuleContent(rings: [], label: title) }
        let tail = "· \(Self.countdown(event, now: now))"
        return CapsuleContent(
            rings: [], label: "\(event.title) \(tail)", text: event.title, tail: tail, icon: "calendar",
            action: event.link.map { CapsuleAction.join($0.url) }
        )
    }

    static func countdown(_ event: MeetingEvent, now: Date) -> String {
        let seconds = event.start.timeIntervalSince(now)
        if seconds <= 0 { return "идёт" }
        let minutes = Int((seconds / 60).rounded(.up))
        return "через \(minutes) мин"
    }

    public func wantsQuiet(now: Date) -> Bool {
        events.contains { $0.isCall && $0.start <= now && $0.end > now }
    }

    public mutating func tick(now: Date) -> [ToolSignal] {
        var signals: [ToolSignal] = []
        for event in events where !event.isAllDay && event.end > now {
            let until = event.start.timeIntervalSince(now)
            // Раз на встречу, а не раз в день. Запустили посреди встречи — поздно предупреждать.
            guard until > 0 else { continue }
            if until <= Self.soonWindow, announced.insert(event.id).inserted { signals.append(.meetingSoon) }
            if until <= Self.lastCall, lastCalled.insert(event.id).inserted { signals.append(.meetingLastCall) }
        }
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        if freeDay != today, isDayFree(now: now) {
            freeDay = today
            signals.append(.dayFree)
        }
        return signals
    }

    /// Пустой день до конца: больше нет ни одной встречи со ссылкой.
    func isDayFree(now: Date) -> Bool {
        guard let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) else { return false }
        return !events.contains { $0.isCall && $0.end > now && $0.start <= end }
    }

    public func events(on day: Date) -> [MeetingEvent] {
        events.filter { event in
            let start = calendar.startOfDay(for: day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
            return event.start < next && event.end > start
        }
    }
}
