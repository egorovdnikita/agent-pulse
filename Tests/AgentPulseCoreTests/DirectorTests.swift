import Foundation
import Testing
@testable import AgentPulseCore

/// Детерминированный генератор: шансы приколов и выбор реплик повторяемы.
struct FixedRNG: RandomNumberGenerator {
    var state: UInt64 = 42
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// Генератор, при котором любой шанс срабатывает (Double.random → 0).
struct ZeroRNG: RandomNumberGenerator {
    mutating func next() -> UInt64 { 0 }
}

@Suite struct DirectorTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    func director(talk: Double = 1, mischief: Double = 1) -> Director {
        var settings = DirectorSettings()
        settings.talkativeness = talk
        settings.mischief = mischief
        return Director(settings: settings, calendar: calendar)
    }

    // Среда, 14 октября 2026.
    var wednesday: Date { date(2026, 10, 14, 10) }

    @Test func greetingOncePerDayWithVariants() {
        var rng = FixedRNG()
        var d = director()
        let first = d.handle(Signal(.presence, .userBack, value: 3600), now: wednesday, rng: &rng)
        #expect(first?.reaction == "greeting")
        #expect(["Привет", "Утречко"].contains(first?.line ?? ""))
        // Второй раз за день — молчит.
        #expect(d.handle(Signal(.clock, .minute), now: wednesday.addingTimeInterval(120), rng: &rng)?.reaction != "greeting")

        var friday = director()
        #expect(friday.handle(Signal(.presence, .userBack), now: date(2026, 10, 16, 9), rng: &rng)?.line == "Пятница!")
        var monday = director()
        #expect(monday.handle(Signal(.presence, .userBack), now: date(2026, 10, 12, 9), rng: &rng)?.line == "Ну, начнём")
    }

    @Test func earlyStartComparesWithHabit() {
        var rng = FixedRNG()
        var d = director()
        // Пять дней привычки: начало в 10:00.
        // Пять дней привычки подряд, последний — вчера (иначе это «давно не виделись»).
        for day in 9...13 {
            d.memory.notePresence(date(2026, 10, day, 10), calendar: calendar)
        }
        let decision = d.handle(Signal(.presence, .userBack), now: date(2026, 10, 14, 7, 30), rng: &rng)
        #expect(decision?.line == "Рано ты")
    }

    @Test func bodyCooldownAndHysteresisStyle() {
        var rng = FixedRNG()
        var d = director()
        _ = d.handle(Signal(.presence, .userBack), now: wednesday, rng: &rng) // приветствие
        let low = d.handle(Signal(.power, .batteryLow), now: wednesday.addingTimeInterval(10), rng: &rng)
        #expect(low?.line == "Есть хочу")
        #expect(low?.behavior == .slowClose)
        // Кулдаун 30 мин.
        #expect(d.handle(Signal(.power, .batteryLow), now: wednesday.addingTimeInterval(600), rng: &rng) == nil)
        #expect(d.handle(Signal(.power, .batteryLow), now: wednesday.addingTimeInterval(31 * 60), rng: &rng)?.reaction == "battery.low")
    }

    @Test func quietSilencesBubblesNotEyes() {
        var rng = FixedRNG()
        var d = director()
        _ = d.handle(Signal(.quiet, .quietOn), now: wednesday, rng: &rng)
        let hot = d.handle(Signal(.thermal, .thermalHigh), now: wednesday.addingTimeInterval(5), rng: &rng)
        #expect(hot?.behavior == .fastBlink)
        #expect(hot?.line == nil)
        // Агентная реакция облачко сохраняет.
        #expect(d.handle(Signal(.agents, .agentWaitingLong), now: wednesday.addingTimeInterval(6), rng: &rng)?.line == "Эй…")
        _ = d.handle(Signal(.quiet, .quietOff), now: wednesday.addingTimeInterval(7), rng: &rng)
        #expect(!d.isQuiet)
    }

    @Test func quietHoursAcrossMidnight() {
        var d = director()
        d.settings.quietFrom = 23 * 60 + 30
        d.settings.quietTo = 8 * 60
        #expect(d.isQuietHours(date(2026, 10, 14, 23, 45)))
        #expect(d.isQuietHours(date(2026, 10, 14, 3)))
        #expect(!d.isQuietHours(date(2026, 10, 14, 12)))
    }

    @Test func funBudgetGapAndGates() {
        var rng = ZeroRNG()
        var d = director(mischief: 0.8) // незнакомым — половина: 2 в день
        let start = date(2026, 10, 14, 11)
        _ = d.handle(Signal(.presence, .userBack), now: start, rng: &rng)
        #expect(d.handle(Signal(.clock, .minute), now: start.addingTimeInterval(60), rng: &rng)?.tier == .fun)
        // Не чаще раза в 40 минут.
        #expect(d.handle(Signal(.clock, .minute), now: start.addingTimeInterval(20 * 60), rng: &rng)?.tier != .fun)
        #expect(d.handle(Signal(.clock, .minute), now: start.addingTimeInterval(45 * 60), rng: &rng)?.tier == .fun)
        // Бюджет исчерпан.
        #expect(d.handle(Signal(.clock, .minute), now: start.addingTimeInterval(2 * 3600), rng: &rng)?.tier != .fun)

        // Агент занят — приколов нет.
        var busy = director()
        busy.agentBusy = true
        _ = busy.handle(Signal(.presence, .userBack), now: start, rng: &rng)
        #expect(busy.handle(Signal(.clock, .minute), now: start.addingTimeInterval(60), rng: &rng)?.tier != .fun)

        // mischief 0 — без приколов.
        var none = director(mischief: 0)
        _ = none.handle(Signal(.presence, .userBack), now: start, rng: &rng)
        #expect(none.handle(Signal(.clock, .minute), now: start.addingTimeInterval(60), rng: &rng)?.tier != .fun)
    }

    @Test func pokesEscalate() {
        var rng = FixedRNG()
        var d = director()
        let t = wednesday
        _ = d.handle(Signal(.presence, .userBack), now: t, rng: &rng)
        let lines = (1...6).map { i in d.handle(Signal(.interaction, .poke), now: t.addingTimeInterval(Double(i) * 0.3), rng: &rng) }
        #expect(lines[0]?.line == "Ай")
        #expect(lines[2]?.line == "Ну хватит")
        #expect(lines[5]?.behavior == .turnAwayLong)
    }

    @Test func exclamationOncePerDay() {
        var rng = FixedRNG()
        var d = director()
        let friday = date(2026, 10, 16, 9)
        #expect(d.handle(Signal(.presence, .userBack), now: friday, rng: &rng)?.line == "Пятница!")
        d.settings.birthday = DateComponents(month: 10, day: 16)
        let birthday = d.handle(Signal(.clock, .minute), now: friday.addingTimeInterval(120), rng: &rng)
        #expect(birthday?.line == "С днюхой")
    }

    @Test func talkativenessZeroKeepsEyes() {
        var rng = FixedRNG()
        var d = director(talk: 0)
        let decision = d.handle(Signal(.keyboard, .capsLockOn), now: wednesday, rng: &rng)
        #expect(decision?.behavior == .wideEyes)
        #expect(decision?.line == nil)
    }

    @Test func spacesDizzy() {
        var rng = FixedRNG()
        var d = director()
        var last: Decision?
        for i in 0..<6 {
            last = d.handle(Signal(.space, .spaceChanged), now: wednesday.addingTimeInterval(Double(i)), rng: &rng)
        }
        #expect(last?.behavior == .dizzy)
    }

    @Test func moodDecaysAndFeels() {
        var mood = Mood()
        mood.feel(Signal(.thermal, .thermalHigh), hour: 12)
        #expect(mood.stress > 0.6)
        mood.decay(over: Mood.halfLife)
        #expect(abs(mood.stress - 0.6) < 0.01)
    }

    @Test func hysteresisDoesNotBlink() {
        var battery = Hysteresis(enter: 20, exit: 30)
        #expect(battery.update(25) == nil)
        #expect(battery.update(19) == .entered)
        #expect(battery.update(22) == nil)
        #expect(battery.update(19) == nil)
        #expect(battery.update(31) == .exited)
        var heat = Hysteresis(enter: 2, exit: 1, falling: false)
        #expect(heat.update(3) == .entered)
        #expect(heat.update(0) == .exited)
    }

    @Test func baselineFromMoodAndBody() {
        var body = BodyCondition()
        body.apply(Signal(.power, .batteryLow))
        body.apply(Signal(.thermal, .thermalHigh))
        let base = Baseline.from(mood: Mood(energy: 0.1), body: body)
        #expect(base.eyeOpen < 0.8)
        #expect(base.glowFlicker > 0)
        #expect(base.motionSpeed < 1)
        #expect(Baseline.from(mood: Mood(), body: BodyCondition()) == Baseline())
    }

    /// Все реплики каталога: ≤ 10 слов, без техники, без эмодзи.
    @Test func catalogLinesFollowVoiceRules() {
        let technical = ["cpu", "ram", "wi-fi", "bash", "агент"]
        var lines: Set<String> = []
        for spec in ReactionCatalog.all {
            for hour in [3, 9, 15, 21] {
                let context = DirectorContext(
                    now: date(2026, 10, 14, hour), calendar: calendar, mood: Mood(), today: DayMemory.Day(date: ""),
                    firstPresenceToday: true, earlyBy: nil, idleSeconds: 0, userPresent: true, birthday: nil,
                    pokeStreak: 1, spaceChangesRecent: 0
                )
                lines.formUnion(spec.lines(Signal(.clock, .minute), context))
            }
        }
        #expect(lines.count > 30)
        for line in lines {
            #expect(Phrases.wordCount(line) <= Phrases.maxWords, "\(line)")
            #expect(!technical.contains { line.lowercased().contains($0) }, "\(line)")
            #expect(!line.unicodeScalars.contains { $0.properties.isEmojiPresentation }, "\(line)")
        }
    }

    @Test func newsWhileAwayAreDeliveredOnReturn() {
        var rng = FixedRNG()
        var d = director()
        let t = wednesday
        _ = d.handle(Signal(.presence, .userBack), now: t, rng: &rng)
        _ = d.handle(Signal(.presence, .userAway, value: 300), now: t.addingTimeInterval(600), rng: &rng)
        _ = d.handle(Signal(.agents, .agentDone), now: t.addingTimeInterval(700), rng: &rng)
        _ = d.handle(Signal(.agents, .agentDone), now: t.addingTimeInterval(800), rng: &rng)
        #expect(d.news == AwayNews(done: 2))
        let back = d.handle(Signal(.presence, .userBack, value: 900), now: t.addingTimeInterval(1500), rng: &rng)
        #expect(back?.reaction == "agent.news")
        #expect(back?.behavior == .done)
        #expect(d.deliveredNews == AwayNews(done: 2))
        #expect(d.news.isEmpty)
        #expect(AwayNews(done: 3, waiting: 1).summary == "Пока тебя не было, у меня готовы 3 задачи, одна ждёт тебя")
        #expect(AwayNews(done: 5, failed: 1).summary == "Пока тебя не было, у меня готово 5 задач, 1 задача не вышла")
        // При тебе — не новости.
        _ = d.handle(Signal(.agents, .agentDone), now: t.addingTimeInterval(1600), rng: &rng)
        #expect(d.news.isEmpty)
    }

    @Test func rhythmAndFlyby() {
        var rng = FixedRNG()
        var d = director()
        let t = wednesday
        _ = d.handle(Signal(.presence, .userBack), now: t, rng: &rng)
        let paused = d.handle(Signal(.presence, .userPaused, value: 50), now: t.addingTimeInterval(60), rng: &rng)
        #expect(paused?.behavior == .lookAround)
        #expect(paused?.line == nil)
        let flyby = d.handle(Signal(.interaction, .cursorFlyby), now: t.addingTimeInterval(70), rng: &rng)
        #expect(flyby?.behavior == .startle)
        // Кулдаун: не дёргается на каждый пролёт.
        #expect(d.handle(Signal(.interaction, .cursorFlyby), now: t.addingTimeInterval(80), rng: &rng) == nil)

        var body = BodyCondition()
        body.apply(Signal(.presence, .userFocused))
        #expect(Baseline.from(mood: Mood(), body: body).motionSpeed < 1)
        body.apply(Signal(.presence, .userPaused))
        #expect(Baseline.from(mood: Mood(), body: body).motionSpeed == 1)
    }

    @Test func moodColorsVoice() {
        let tired = Mood(energy: 0.2)
        #expect(MoodVoice.color("Готово", mood: tired) == "Готово…")
        #expect(MoodVoice.color("Можно?", mood: tired) == "Можно?")
        #expect(MoodVoice.color("Хмм…", mood: tired) == "Хмм…")
        #expect(MoodVoice.color("Готово", mood: Mood()) == "Готово")
        #expect(MoodVoice.pool(for: .done, mood: Mood(joy: 0.9)).contains("Ура, готово"))
        #expect(!MoodVoice.pool(for: .done, mood: Mood()).contains("Ура"))

        // Ожидание пользователя всегда без окраски.
        var scheduler = BubbleScheduler()
        scheduler.mood = tired
        scheduler.react(.waitPermission, now: wednesday)
        #expect(!(scheduler.current?.text.hasSuffix("…") ?? true))
        for trigger in BubbleTrigger.allCases where trigger != .line {
            for line in MoodVoice.pool(for: trigger, mood: Mood(joy: 1)) {
                #expect(Phrases.wordCount(MoodVoice.color(line, mood: tired)) <= Phrases.maxWords)
            }
        }
    }

    @Test func familiarityAndLongAbsence() {
        var rng = FixedRNG()
        var d = director()
        for day in 1...5 {
            d.memory.notePresence(date(2026, 10, day, 10), calendar: calendar)
        }
        #expect(d.memory.familiarity > 0.2)
        #expect(d.memory.daysSinceLastVisit(before: date(2026, 10, 14, 9), calendar: calendar) == 9)
        let back = d.handle(Signal(.presence, .userBack), now: date(2026, 10, 14, 9), rng: &rng)
        #expect(["Давно не виделись", "Наконец-то"].contains(back?.line ?? ""))

        var settings = DirectorSettings()
        settings.mischief = 1
        #expect(settings.funLimit(familiarity: 0) < settings.funLimit(familiarity: 1))
        #expect(settings.funLimit(familiarity: 1) == 5)
    }

    @Test func nodsOffOnlyLateAndWhenStill() {
        var rng = FixedRNG()
        var d = director()
        _ = d.handle(Signal(.presence, .userBack), now: date(2026, 10, 14, 23, 10), rng: &rng)
        // Днём носом не клюёт.
        #expect(d.handle(Signal(.clock, .minute), now: date(2026, 10, 15, 14), rng: &rng)?.behavior != .doze)
        var body = BodyCondition()
        body.hour = 23
        let night = Baseline.from(mood: Mood(), body: body)
        body.hour = 9
        let morning = Baseline.from(mood: Mood(), body: body)
        #expect(night.droop > 0)
        #expect(night.motionSpeed < morning.motionSpeed)
        #expect(Baseline.from(mood: Mood(joy: 1), body: BodyCondition()).bounce == 1)
    }

    @Test func memoryKeepsThirtyDays() {
        var memory = DayMemory()
        for offset in 0..<40 {
            memory.notePresence(date(2026, 9, 1, 10).addingTimeInterval(Double(offset) * 86_400), calendar: calendar)
        }
        #expect(memory.days.count == DayMemory.retentionDays)
    }
}
