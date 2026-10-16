import Foundation

/// Что случилось у агентов, пока тебя не было.
public struct AwayNews: Sendable, Equatable {
    public var done = 0
    public var failed = 0
    public var waiting = 0

    public init(done: Int = 0, failed: Int = 0, waiting: Int = 0) {
        self.done = done
        self.failed = failed
        self.waiting = waiting
    }

    public var isEmpty: Bool { done == 0 && failed == 0 && waiting == 0 }

    /// «Пока тебя не было, у меня готовы 3 задачи, одна ждёт тебя».
    public var summary: String {
        func tasks(_ n: Int) -> String { "\(n) \(HumanTime.plural(n, "задача", "задачи", "задач"))" }
        var parts: [String] = []
        if done > 0 { parts.append("у меня \(HumanTime.plural(done, "готова", "готовы", "готово")) \(tasks(done))") }
        if failed > 0 { parts.append("\(tasks(failed)) не \(failed == 1 ? "вышла" : "вышли")") }
        if waiting > 0 { parts.append(waiting == 1 ? "одна ждёт тебя" : "\(tasks(waiting)) ждут тебя") }
        return "Пока тебя не было, " + parts.joined(separator: ", ")
    }
}

/// Решение «реагировать сейчас»: что сыграть телом и что (если можно) сказать.
public struct Decision: Sendable, Equatable {
    public let reaction: String
    public let tier: Tier
    public let behavior: MascotReaction?
    /// nil — только глазами (тишина, болтливость или у реакции нет реплик).
    public let line: String?
    public let bubbleDuration: TimeInterval
    public let special: SpecialAction?
}

public struct DirectorSettings: Sendable, Equatable {
    /// 0…1: частота облачков вне агентов.
    public var talkativeness = 0.5
    /// 0…1: бюджет приколов, 0 — без приколов, 1 — до 5 в день.
    public var mischief = 0.5
    public var birthday: DateComponents?
    /// Тихие часы, минуты от полуночи; могут переходить через полночь.
    public var quietFrom: Int?
    public var quietTo: Int?

    public init() {}

    public var funDailyLimit: Int { Int((mischief * 8).rounded()) }

    /// Чем лучше знакомы, тем смелее: незнакомому — половина бюджета приколов.
    public func funLimit(familiarity: Double) -> Int {
        Int((mischief * 8 * (0.5 + 0.5 * familiarity)).rounded())
    }
}

/// Единственное место, где решается «реагировать ли сейчас»: приоритет, бюджет, кулдауны, тишина, настроение.
/// Чистая структура на переданном времени — тестируется на виртуальных часах.
public struct Director: Sendable {
    public static let funMinGap: TimeInterval = 25 * 60
    public static let pokeWindow: TimeInterval = 4
    public static let spaceWindow: TimeInterval = 10
    /// «Не шутить в стрессе»: нейтраль — 0.5, стресс — заметно выше неё.
    public static let funStressLimit = 0.55

    public var settings: DirectorSettings
    public private(set) var mood = Mood()
    public var memory = DayMemory()
    public var catalog: [ReactionSpec]

    public private(set) var quietReasons: Set<String> = []
    public private(set) var userPresent = true
    /// Агент работает или ждёт — приколы молчат, важное не тонет в милом.
    public var agentBusy = false

    private var lastFired: [String: Date] = [:]
    private var dailyCount: [String: Int] = [:]
    private var dayKey = ""
    private var funToday = 0
    private var lastFunAt: Date = .distantPast
    private var exclaimedToday = false
    private var lastMoodUpdate: Date?
    private var idleSince: Date?
    private var pokeTimes: [Date] = []
    private var spaceTimes: [Date] = []
    /// Свежих новостей дизайна ждёт рассказа.
    public private(set) var newsWaiting = 0
    /// Новости агентов, накопленные, пока тебя нет.
    public private(set) var news = AwayNews()
    /// Новости, отданные при последнем возвращении.
    public private(set) var deliveredNews: AwayNews?
    private let calendar: Calendar

    public init(settings: DirectorSettings = DirectorSettings(), catalog: [ReactionSpec] = ReactionCatalog.all, calendar: Calendar = .current) {
        self.settings = settings
        self.catalog = catalog
        self.calendar = calendar
    }

    public var isQuiet: Bool { !quietReasons.isEmpty }

    public func isQuietHours(_ now: Date) -> Bool {
        guard let from = settings.quietFrom, let to = settings.quietTo else { return false }
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return from <= to ? (from..<to).contains(minutes) : (minutes >= from || minutes < to)
    }

    public mutating func setMood(_ mood: Mood) {
        self.mood = mood
    }

    public mutating func handle(_ signal: Signal, now: Date, rng: inout some RandomNumberGenerator) -> Decision? {
        rollDay(now)
        if let last = lastMoodUpdate { mood.decay(over: now.timeIntervalSince(last)) }
        lastMoodUpdate = now
        mood.feel(signal, hour: calendar.component(.hour, from: now))

        // Состояние, которое ведёт сам Director.
        var firstPresence = false
        deliveredNews = nil
        if !userPresent {
            switch signal.kind {
            case .agentDone: news.done += 1
            case .agentError: news.failed += 1
            case .agentWaitingLong: news.waiting += 1
            default: break
            }
        }
        let returning = !userPresent && [.userBack, .screenUnlocked, .systemWake].contains(signal.kind)
        let newsOnReturn = returning ? news : AwayNews()
        switch signal.kind {
        case .quietOn: quietReasons.insert(signal.sense.rawValue)
        case .quietOff: quietReasons.remove(signal.sense.rawValue)
        case .userAway:
            userPresent = false
            idleSince = now.addingTimeInterval(-(signal.value ?? 300))
            memory.update(now, calendar: calendar) { $0.breaks += 1 }
        case .userBack, .screenUnlocked, .systemWake:
            userPresent = true
            idleSince = nil
        case .agentDone: memory.update(now, calendar: calendar) { $0.agentTasks += 1 }
        case .agentError: memory.update(now, calendar: calendar) { $0.agentErrors += 1 }
        case .stroke: memory.update(now, calendar: calendar) { $0.strokes += 1 }
        case .poke:
            memory.update(now, calendar: calendar) { $0.pokes += 1 }
            pokeTimes = pokeTimes.filter { now.timeIntervalSince($0) < Self.pokeWindow } + [now]
        case .newsFresh:
            newsWaiting = Int(signal.value ?? 0)
        case .spaceChanged:
            spaceTimes = spaceTimes.filter { now.timeIntervalSince($0) < Self.spaceWindow } + [now]
        default: break
        }
        if userPresent && ReactionCatalog.present.contains(signal.kind) {
            firstPresence = memory.notePresence(now, calendar: calendar)
        }

        var context = DirectorContext(
            now: now, calendar: calendar, mood: mood, today: memory.today(now, calendar: calendar),
            firstPresenceToday: firstPresence, earlyBy: earlyBy(now),
            idleSeconds: idleSince.map { now.timeIntervalSince($0) } ?? 0,
            userPresent: userPresent, birthday: settings.birthday,
            pokeStreak: signal.kind == .poke ? pokeTimes.count : 0,
            spaceChangesRecent: spaceTimes.count,
            news: newsOnReturn
        )
        context.familiarity = memory.familiarity
        context.newsWaiting = newsWaiting
        context.quiet = isQuiet || isQuietHours(now)
        context.agentBusy = agentBusy
        context.daysAway = memory.daysSinceLastVisit(before: now, calendar: calendar)
        if returning, !news.isEmpty {
            deliveredNews = news
            news = AwayNews()
        }
        let quiet = isQuiet || isQuietHours(now)

        for spec in catalog where spec.kinds.contains(signal.kind) {
            guard spec.condition(signal, context), allowed(spec, now: now, quiet: quiet, context: context) else { continue }
            if spec.chance < 1, Double.random(in: 0..<1, using: &rng) >= spec.chance { continue }
            return fire(spec, signal: signal, context: context, now: now, quiet: quiet, rng: &rng)
        }
        return nil
    }

    private func allowed(_ spec: ReactionSpec, now: Date, quiet: Bool, context: DirectorContext) -> Bool {
        if let last = lastFired[spec.group], now.timeIntervalSince(last) < spec.cooldown { return false }
        if let limit = spec.dailyLimit, dailyCount[spec.group, default: 0] >= limit { return false }
        if let gate = spec.moodGate, !gate(mood) { return false }
        guard spec.tier == .fun else { return true }
        // Приколы: тишина и агенты выключают их полностью; бюджет на день; не чаще раза в 25 мин; не в стрессе.
        return !quiet && !agentBusy
            && funToday < settings.funLimit(familiarity: context.familiarity)
            && now.timeIntervalSince(lastFunAt) >= Self.funMinGap
            && mood.stress < Self.funStressLimit
            && (spec.needsPresence ? context.userPresent && context.idleSeconds < 120 : !context.userPresent)
    }

    private mutating func fire(
        _ spec: ReactionSpec, signal: Signal, context: DirectorContext, now: Date, quiet: Bool,
        rng: inout some RandomNumberGenerator
    ) -> Decision {
        lastFired[spec.group] = now
        dailyCount[spec.group, default: 0] += 1
        if spec.tier == .fun {
            funToday += 1
            lastFunAt = now
        }

        var line = spec.lines(signal, context).randomElement(using: &rng)
        // Облачко вне агентов — по болтливости; в тишине — только глаза.
        let talk = spec.tier == .agent ? 1 : min(1, settings.talkativeness * 2)
        if quiet && spec.tier != .agent { line = nil }
        if line != nil, talk < 1, Double.random(in: 0..<1, using: &rng) >= talk { line = nil }
        // Восклицательный знак — не чаще раза в день.
        if let text = line, text.contains("!") {
            if exclaimedToday {
                line = text.replacingOccurrences(of: "!", with: "")
            } else {
                exclaimedToday = true
            }
        }
        return Decision(
            reaction: spec.id, tier: spec.tier, behavior: spec.behavior(signal, context),
            line: line, bubbleDuration: spec.bubbleDuration, special: spec.special
        )
    }

    private func earlyBy(_ now: Date) -> Double? {
        guard let median = memory.medianStart(before: now, calendar: calendar),
              let first = memory.today(now, calendar: calendar).firstPresence else { return nil }
        return Double(median - first) / 60
    }

    private mutating func rollDay(_ now: Date) {
        let key = DayMemory.key(now, calendar: calendar)
        guard key != dayKey else { return }
        dayKey = key
        dailyCount.removeAll()
        funToday = 0
        exclaimedToday = false
    }
}

/// Итог одного сигнала для приложения.
public struct DirectorOutcome: Sendable {
    public let decision: Decision?
    public let mood: Mood
    /// Тишина сейчас: созвон, полный экран или тихие часы.
    public let quiet: Bool
    /// Пока тебя нет, у агентов что-то случилось — маскот ждёт с новостями.
    public let newsPending: Bool
    /// Ты вернулся — что случилось без тебя.
    public let deliveredNews: AwayNews?
    /// Счётчики сегодняшнего дня — для итога при наведении.
    public let today: DayMemory.Day
    /// Сумма за последние 7 дней — итог недели при наведении.
    public let week: DayMemory.Day
}

/// Актор-обёртка: решения принимаются последовательно, вне главного потока.
public actor DirectorActor {
    private var director: Director
    private var rng = SystemRandomNumberGenerator()

    public init(_ director: Director = Director()) {
        self.director = director
    }

    public func handle(_ signal: Signal) -> DirectorOutcome {
        let decision = director.handle(signal, now: signal.ts, rng: &rng)
        return DirectorOutcome(
            decision: decision, mood: director.mood,
            quiet: director.isQuiet || director.isQuietHours(signal.ts),
            newsPending: !director.news.isEmpty, deliveredNews: director.deliveredNews,
            today: director.memory.today(signal.ts),
            week: director.memory.week(signal.ts)
        )
    }

    public func update(_ change: @Sendable (inout Director) -> Void) {
        change(&director)
    }

    public var snapshot: Director { director }
}
