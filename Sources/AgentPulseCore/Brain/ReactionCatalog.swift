import Foundation

/// Порядок = приоритет.
public enum Tier: Int, Sendable, Comparable, Codable, CaseIterable {
    case agent = 0, body, rhythm, interaction, fun

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Особые поведения, которые двигают саму панель — их исполняет приложение.
public enum SpecialAction: String, Sendable, Codable {
    case peekaboo, sleepwalk
    /// Рассказать свежую новость дизайна — текст и ссылку подставляет приложение.
    case news
}

/// Что известно в момент решения.
public struct DirectorContext: Sendable {
    public let now: Date
    public let calendar: Calendar
    public let mood: Mood
    public let today: DayMemory.Day
    public let firstPresenceToday: Bool
    /// Насколько раньше обычного начался день, часы (nil — привычки ещё нет).
    public let earlyBy: Double?
    public let idleSeconds: TimeInterval
    public let userPresent: Bool
    public let birthday: DateComponents?
    public let pokeStreak: Int
    public let spaceChangesRecent: Int
    /// Что случилось у агентов, пока тебя не было (заполнено на сигнале возвращения).
    public let news: AwayNews
    /// Знакомство 0…1 и сколько дней не виделись.
    public var familiarity = 0.0
    public var daysAway: Int?
    /// Сколько свежих новостей дизайна ждёт; тишина и занятость агента — новости молчат.
    public var newsWaiting = 0
    public var quiet = false
    public var agentBusy = false

    public init(
        now: Date, calendar: Calendar, mood: Mood, today: DayMemory.Day, firstPresenceToday: Bool, earlyBy: Double?,
        idleSeconds: TimeInterval, userPresent: Bool, birthday: DateComponents?, pokeStreak: Int, spaceChangesRecent: Int,
        news: AwayNews = AwayNews()
    ) {
        self.now = now
        self.calendar = calendar
        self.mood = mood
        self.today = today
        self.firstPresenceToday = firstPresenceToday
        self.earlyBy = earlyBy
        self.idleSeconds = idleSeconds
        self.userPresent = userPresent
        self.birthday = birthday
        self.pokeStreak = pokeStreak
        self.spaceChangesRecent = spaceChangesRecent
        self.news = news
    }

    public var hour: Int { calendar.component(.hour, from: now) }
    /// 1 — воскресенье, 2 — понедельник, …, 6 — пятница.
    public var weekday: Int { calendar.component(.weekday, from: now) }
    public var day: Int { calendar.component(.day, from: now) }
    public var month: Int { calendar.component(.month, from: now) }
}

public struct ReactionSpec: Sendable {
    public typealias Condition = @Sendable (Signal, DirectorContext) -> Bool
    public typealias Lines = @Sendable (Signal, DirectorContext) -> [String]
    public typealias Behavior = @Sendable (Signal, DirectorContext) -> MascotReaction?

    public let id: String
    /// Варианты одной реакции делят кулдаун и дневной лимит.
    public let group: String
    public let kinds: Set<SignalKind>
    public let tier: Tier
    public let cooldown: TimeInterval
    public let dailyLimit: Int?
    public let moodGate: (@Sendable (Mood) -> Bool)?
    public let condition: Condition
    public let behavior: Behavior
    /// nil или пусто — реакция только глазами.
    public let lines: Lines
    public let bubbleDuration: TimeInterval
    /// Для приколов на минутном тике: шанс сработать, когда всё разрешено.
    public let chance: Double
    public let special: SpecialAction?
    /// Приколу нужен пользователь рядом (кроме лунатизма).
    public let needsPresence: Bool

    public init(
        _ id: String,
        group: String? = nil,
        on kinds: Set<SignalKind>,
        tier: Tier,
        cooldown: TimeInterval? = nil,
        dailyLimit: Int? = nil,
        moodGate: (@Sendable (Mood) -> Bool)? = nil,
        when condition: @escaping Condition = { _, _ in true },
        behavior: MascotReaction? = nil,
        behaviorFor: Behavior? = nil,
        lines: [String] = [],
        linesFor: Lines? = nil,
        bubble: TimeInterval = 2.5,
        chance: Double = 1,
        special: SpecialAction? = nil,
        needsPresence: Bool = true
    ) {
        self.id = id
        self.group = group ?? id
        self.kinds = kinds
        self.tier = tier
        self.cooldown = cooldown ?? Self.defaultCooldown(tier)
        self.dailyLimit = dailyLimit ?? (tier == .rhythm ? 1 : nil)
        self.moodGate = moodGate
        self.condition = condition
        self.behavior = behaviorFor ?? { _, _ in behavior }
        self.lines = linesFor ?? { _, _ in lines }
        self.bubbleDuration = bubble
        self.chance = chance
        self.special = special
        self.needsPresence = needsPresence
    }

    static func defaultCooldown(_ tier: Tier) -> TimeInterval {
        switch tier {
        case .agent: 60
        case .body: 30 * 60
        case .rhythm: 60
        case .interaction: 1
        case .fun: 20 * 60
        }
    }
}

/// Декларативный каталог всех реакций. Добавить реакцию = одна запись здесь. Пороги и кулдауны — тоже здесь.
public enum ReactionCatalog {
    static let present: Set<SignalKind> = [.userBack, .systemWake, .screenUnlocked, .minute, .stroke, .poke, .dragged]

    public static let all: [ReactionSpec] = agents + body + rhythm + interaction + news + fun

    // MARK: - Агенты (сверх основного конвейера состояний)

    static let agents: [ReactionSpec] = [
        // Пока тебя не было, агент закончил или ждал — первым делом об этом.
        ReactionSpec("agent.news", on: [.userBack, .screenUnlocked, .systemWake], tier: .agent, cooldown: 0,
                     when: { _, c in !c.news.isEmpty },
                     behaviorFor: { _, c in c.news.failed > 0 && c.news.done == 0 ? .lookDown : .done },
                     linesFor: { _, c in
                         if c.news.waiting > 0 { return ["Я жду тебя", "Глянешь? Я жду"] }
                         return c.news.done > 0 ? ["У меня готово, проверь", "Есть новости"] : ["У меня не вышло", "Не получилось, глянешь?"]
                     }, bubble: 4),
        ReactionSpec("agent.waitLong", on: [.agentWaitingLong], tier: .agent, cooldown: 5 * 60,
                     behavior: .turnAway, lines: ["Эй…"], bubble: 3),
        ReactionSpec("agent.errorStreak", on: [.agentErrorStreak], tier: .agent, cooldown: 10 * 60,
                     behavior: .lookDown, lines: ["Бывает"], bubble: 3),
        ReactionSpec("agent.longTask", on: [.agentStep], tier: .agent, cooldown: 3 * 60,
                     when: { signal, _ in (signal.value ?? 0) > 10 * 60 }, behavior: .yawn),
    ]

    // MARK: - Тело ноутбука

    static let body: [ReactionSpec] = [
        ReactionSpec("battery.critical", on: [.batteryCritical], tier: .body, behavior: .slowClose, lines: ["Совсем всё", "Я на последнем…"]),
        ReactionSpec("battery.low", on: [.batteryLow], tier: .body, behavior: .slowClose, lines: ["Есть хочу", "Мне бы поесть"]),
        ReactionSpec("charger.on", on: [.chargerConnected], tier: .body, cooldown: 5 * 60, behavior: .startle, lines: ["Ммм…", "Ммм, вкусно"]),
        ReactionSpec("battery.full", on: [.fullyCharged], tier: .body, behavior: .contentSquint, lines: ["Ням", "Сыто"]),
        ReactionSpec("lowPower", on: [.lowPowerOn], tier: .body, lines: ["Экономлю", "Берегу силы"]),
        ReactionSpec("thermal.high", on: [.thermalHigh], tier: .body, behavior: .fastBlink, lines: ["Жарко…", "Мне жарко…"]),
        ReactionSpec("thermal.normal", on: [.thermalNormal], tier: .body, behavior: .relax, lines: ["Фух"]),
        ReactionSpec("memory.pressure", on: [.memoryPressure], tier: .body, behavior: .wobble, lines: ["Тесно мне", "Мне тут тесно…"]),
        ReactionSpec("disk.low", on: [.diskLow], tier: .body, cooldown: 6 * 3600, behavior: .puff, lines: ["Я лопну"]),
        ReactionSpec("network.lost", on: [.networkLost], tier: .body, cooldown: 10 * 60, behavior: .lookAround, lines: ["Где все?", "Я никого не слышу"]),
        ReactionSpec("network.back", on: [.networkBack], tier: .body, cooldown: 10 * 60, lines: ["Вот вы где", "О, снова всех слышу"]),
        ReactionSpec("display.added", on: [.displayAdded], tier: .body, cooldown: 5 * 60,
                     behaviorFor: { signal, _ in (signal.value ?? 1) < 0 ? .lookLeft : .lookRight }, lines: ["О, второй"]),
        ReactionSpec("display.removed", on: [.displayRemoved], tier: .body, cooldown: 5 * 60,
                     behaviorFor: { signal, _ in (signal.value ?? 1) < 0 ? .lookLeft : .lookRight }, lines: ["Опустело"]),
        ReactionSpec("wake", on: [.systemWake], tier: .body, cooldown: 10 * 60, behavior: .stretch,
                     linesFor: { _, context in (5..<12).contains(context.hour) ? ["Утро?"] : ["Я тут"] }),
        ReactionSpec("sleep", on: [.systemSleep], tier: .body, cooldown: 60, behavior: .slowClose, lines: ["Пока"], bubble: 1.5),
        ReactionSpec("unlock.long", on: [.screenUnlocked], tier: .body, cooldown: 60,
                     when: { signal, _ in (signal.value ?? 0) > 3600 }, lines: ["С возвратом"]),
        ReactionSpec("uptime.long", on: [.uptimeLong], tier: .body, cooldown: 24 * 3600, dailyLimit: 1,
                     behavior: .yawn, lines: ["Хочу спать", "Мне бы поспать"]),
        ReactionSpec("headphones", on: [.headphonesOn], tier: .body, behavior: .contentSquint, lines: ["Музыка?", "Что слушаем?"]),
        ReactionSpec("volume.max", on: [.volumeMax], tier: .body, behavior: .squint, lines: ["Тише…"]),
        ReactionSpec("capsLock", on: [.capsLockOn], tier: .body, cooldown: 10 * 60, behavior: .wideEyes, lines: ["Кричишь?", "Ты чего кричишь?"]),
        ReactionSpec("theme.dark", on: [.darkMode], tier: .body, lines: ["Уютно", "Мне так уютно"]),
        // Замер посреди работы — с любопытством осматривается, молча.
        ReactionSpec("user.paused", on: [.userPaused], tier: .body, cooldown: 10 * 60, behavior: .lookAround),
    ]

    // MARK: - Ритм и время (каждая — не чаще раза в день)

    static let rhythm: [ReactionSpec] = [
        ReactionSpec("newYear", group: "holiday", on: present, tier: .rhythm,
                     when: { _, c in c.userPresent && c.month == 1 && c.day == 1 }, behavior: .done, lines: ["С Новым!"], bubble: 4),
        ReactionSpec("birthday", group: "holiday", on: present, tier: .rhythm,
                     when: { _, c in c.userPresent && c.birthday?.month == c.month && c.birthday?.day == c.day },
                     behavior: .done, lines: ["С днюхой!"], bubble: 4),
        ReactionSpec("aprilFools", on: present, tier: .rhythm,
                     when: { _, c in c.userPresent && c.month == 4 && c.day == 1 }, behavior: .eyeSwap),
        ReactionSpec("friday13", on: present, tier: .rhythm,
                     when: { _, c in c.userPresent && c.weekday == 6 && c.day == 13 }, behavior: .sideEye, lines: ["Осторожно"]),
        ReactionSpec("greeting.longAbsence", group: "greeting", on: present, tier: .rhythm,
                     when: { _, c in c.firstPresenceToday && (c.daysAway ?? 0) >= 3 }, behavior: .done,
                     lines: ["Давно не виделись", "Наконец-то"]),
        ReactionSpec("greeting.early", group: "greeting", on: present, tier: .rhythm,
                     when: { _, c in c.firstPresenceToday && (c.earlyBy ?? 0) >= 2 }, behavior: .notice, lines: ["Рано ты"]),
        ReactionSpec("greeting.friday", group: "greeting", on: present, tier: .rhythm,
                     when: { _, c in c.firstPresenceToday && c.weekday == 6 }, behavior: .notice, lines: ["Пятница!"]),
        ReactionSpec("greeting.monday", group: "greeting", on: present, tier: .rhythm,
                     when: { _, c in c.firstPresenceToday && c.weekday == 2 }, behavior: .notice, lines: ["Ну, начнём"]),
        ReactionSpec("greeting", group: "greeting", on: present, tier: .rhythm,
                     when: { _, c in c.firstPresenceToday }, behavior: .notice,
                     linesFor: { _, c in
                         // Знакомы давно — приветствие теплее.
                         let warm = c.familiarity > 0.6 ? ["Привет-привет"] : []
                         return (c.hour < 12 ? ["Привет", "Утречко"] : ["Привет"]) + warm
                     }),
        // Поздно вечером клюёт носом: глаза слипаются — и вздрагивает. Без реплики.
        ReactionSpec("nodOff", on: [.minute], tier: .rhythm, cooldown: 15 * 60, dailyLimit: 4,
                     when: { _, c in c.userPresent && (c.hour >= 22 || c.hour < 3) && c.idleSeconds > 20 && c.idleSeconds < 300 },
                     behavior: .doze),
        ReactionSpec("late.veryLate", group: "late", on: [.minute], tier: .rhythm,
                     when: { _, c in c.userPresent && c.idleSeconds < 120 && (3..<5).contains(c.hour) }, lines: ["Не спится?"]),
        ReactionSpec("late.midnight", group: "late", on: [.minute], tier: .rhythm,
                     when: { _, c in c.userPresent && c.idleSeconds < 120 && (0..<3).contains(c.hour) },
                     behavior: .yawn, lines: ["Спать пора"]),
        ReactionSpec("longWork", on: [.longWork], tier: .rhythm, dailyLimit: 2, behavior: .stretch, lines: ["Пройдёмся?", "Давай разомнёмся?"]),
        ReactionSpec("backAfterBreak", on: [.userBack], tier: .rhythm, cooldown: 20 * 60, dailyLimit: 3,
                     when: { signal, _ in (signal.value ?? 0) > 20 * 60 }, behavior: .notice, lines: ["О, ты", "О, ты тут"]),
        ReactionSpec("fridayEvening", on: [.minute], tier: .rhythm,
                     when: { _, c in c.userPresent && c.idleSeconds < 120 && c.weekday == 6 && c.hour >= 18 },
                     behavior: .contentSquint, lines: ["Неделя ок"]),
        ReactionSpec("heavyDay", on: [.minute], tier: .rhythm,
                     when: { _, c in c.userPresent && c.idleSeconds < 120 && c.hour >= 19 && c.today.agentErrors >= 5 },
                     behavior: .lookDown, lines: ["Тяжко было"]),
    ]

    // MARK: - Взаимодействие (всегда: это ответ на действие)

    static let interaction: [ReactionSpec] = [
        // Тычки идут сериями — без кулдауна, эскалация по длине серии.
        ReactionSpec("poke.many", group: "poke", on: [.poke], tier: .interaction, cooldown: 0,
                     when: { _, c in c.pokeStreak == 6 }, behavior: .turnAwayLong),
        ReactionSpec("poke.enough", group: "poke", on: [.poke], tier: .interaction, cooldown: 0,
                     when: { _, c in c.pokeStreak == 3 }, behavior: .flinch, lines: ["Ну хватит"]),
        ReactionSpec("poke", group: "poke", on: [.poke], tier: .interaction, cooldown: 0,
                     when: { _, c in c.pokeStreak < 3 }, behavior: .flinch, lines: ["Ай"], bubble: 1.2),
        ReactionSpec("stroke", on: [.stroke], tier: .interaction, cooldown: 8, behavior: .purr, lines: ["Хорошо…", "Мне приятно…"]),
        // Курсор пролетел сквозь — вздрогнул, только глазами.
        ReactionSpec("flyby", on: [.cursorFlyby], tier: .interaction, cooldown: 30, behavior: .startle),
        ReactionSpec("drag.fast", on: [.dragged], tier: .interaction, cooldown: 10,
                     when: { signal, _ in (signal.value ?? 0) > 900 }, lines: ["Уиии"], bubble: 1.2),
        ReactionSpec("thrown", on: [.thrown], tier: .interaction, cooldown: 2, behavior: .dizzy, lines: ["Укачало"]),
        ReactionSpec("dropped", on: [.dropped], tier: .interaction, cooldown: 5, behavior: .lookAround, lines: ["Так лучше", "Мне тут нравится"]),
        ReactionSpec("spaces.dizzy", on: [.spaceChanged], tier: .interaction, cooldown: 60,
                     when: { _, c in c.spaceChangesRecent > 5 }, behavior: .dizzy, lines: ["Укачало"]),
    ]

    // MARK: - Новости дизайна [решение]

    /// Время от времени, когда ты рядом и ничего не мешает: не чаще раза в 2 часа, до 3 в день.
    static let news: [ReactionSpec] = [
        ReactionSpec("news.design", on: [.minute], tier: .rhythm, cooldown: 2 * 3600, dailyLimit: 3,
                     when: { _, c in
                         c.newsWaiting > 0 && c.userPresent && c.idleSeconds < 120 && !c.quiet && !c.agentBusy
                             && (9..<22).contains(c.hour)
                     },
                     behavior: .stars, bubble: 8, chance: 1.0 / 10, special: .news),
    ]

    // MARK: - Приколы (в бюджете)

    static let funChance = 1.0 / 10

    static let fun: [ReactionSpec] = [
        ReactionSpec("fun.sneeze", on: [.minute], tier: .fun, behavior: .sneeze, lines: ["Апчхи"], bubble: 1.5, chance: funChance),
        ReactionSpec("fun.hiccup", on: [.minute], tier: .fun, behavior: .hiccup, lines: ["Ик"], bubble: 1.2, chance: funChance),
        ReactionSpec("fun.fly", on: [.minute], tier: .fun, behavior: .fly, chance: funChance),
        ReactionSpec("fun.nap", on: [.minute], tier: .fun, behavior: .nap, chance: funChance),
        ReactionSpec("fun.stare", on: [.minute], tier: .fun, behavior: .stare, chance: funChance),
        ReactionSpec("fun.peekaboo", on: [.minute], tier: .fun, lines: ["Ку-ку"], bubble: 2, chance: funChance, special: .peekaboo),
        ReactionSpec("fun.sleepwalk", on: [.minute], tier: .fun,
                     when: { _, c in (0..<6).contains(c.hour) && c.idleSeconds > 10 * 60 },
                     chance: 1.0 / 10, special: .sleepwalk, needsPresence: false),
    ]
}
