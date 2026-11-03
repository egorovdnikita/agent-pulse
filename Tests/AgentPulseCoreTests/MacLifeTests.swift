import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct MacLifeTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func director() -> Director {
        var settings = DirectorSettings()
        settings.talkativeness = 1
        return Director(settings: settings, calendar: calendar)
    }

    /// Полнолуния 2026: 3 января, 1 марта, 26 октября, 24 ноября (по таблицам).
    @Test func fullMoonMatchesKnownDates() {
        for day in [date(2026, 1, 3), date(2026, 3, 3), date(2026, 10, 26), date(2026, 11, 24)] {
            #expect(MoonPhase.isFull(day), "\(day)")
        }
        #expect(!MoonPhase.isFull(date(2026, 11, 10)))
        #expect(!MoonPhase.isFull(date(2026, 11, 3)))
    }

    /// Внезапно — новая загрузка, а прошлый запуск не закрылся. Штатная перезагрузка — молчит.
    @Test func launchRecordDetectsUnexpectedRestartAndUpdate() {
        var record = LaunchRecord()
        #expect(record.start(bootTime: 1000, osVersion: "26.0", now: date(2026, 11, 1)).isEmpty)
        #expect(record.firstSeen == date(2026, 11, 1))
        // Тот же запуск системы, приложение упало — не внезапное выключение Mac.
        #expect(record.start(bootTime: 1001, osVersion: "26.0", now: date(2026, 11, 2)).isEmpty)
        // Новая загрузка без штатного выхода, приложение было живо до самого конца.
        record.lastAlive = 8900
        #expect(record.start(bootTime: 9000, osVersion: "26.0", now: date(2026, 11, 2)) == [.unexpectedRestart])
        // Приложение упало задолго до перезагрузки — Mac выключили штатно, молчим.
        record.lastAlive = 9000
        #expect(record.start(bootTime: 15000, osVersion: "26.0", now: date(2026, 11, 2)).isEmpty)
        // Штатный выход, перезагрузка с обновлением.
        record.cleanExit = true
        #expect(record.start(bootTime: 20000, osVersion: "26.1", now: date(2026, 11, 3)) == [.systemUpdated])
        #expect(record.firstSeen == date(2026, 11, 1))
        // Старая запись версии на языке системы — не «обновились».
        var legacy = LaunchRecord()
        legacy.osVersion = "Версия 26.6.2 (Выпуск 25G83)"
        legacy.bootTime = 100
        #expect(legacy.start(bootTime: 100, osVersion: "26.6.2 25G83", now: date(2026, 11, 3)).isEmpty)
        #expect(LaunchRecord.systemVersion(OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 2), build: "25G83") == "26.6.2 25G83")
    }

    @Test func anniversaries() {
        #expect(Anniversary.lines(days: 30) != nil)
        #expect(Anniversary.lines(days: 100) != nil)
        #expect(Anniversary.lines(days: 365)?.first == "Год вместе")
        #expect(Anniversary.lines(days: 730) == ["2 года вместе"])
        #expect(Anniversary.lines(days: 31) == nil)
    }

    @Test func anniversaryOnFirstPresence() {
        var rng = FixedRNG()
        var d = director()
        d.settings.firstSeen = date(2025, 11, 3, 9)
        let decision = d.handle(Signal(.presence, .userBack), now: date(2026, 11, 3, 10), rng: &rng)
        #expect(decision?.reaction == "anniversary")
        #expect(["Год вместе", "Уже год рядом"].contains(decision?.line ?? ""))
    }

    /// Зарядка: подключили и отключили — у каждого своё; голодному — с облегчением.
    @Test func chargerConnectAndDisconnect() {
        var rng = FixedRNG()
        var d = director()
        let now = date(2026, 11, 3, 11)
        let on = d.handle(Signal(.power, .chargerConnected, value: 12), now: now, rng: &rng)
        #expect(on?.reaction == "charger.on")
        #expect(["Ммм, наконец-то еда", "Очень кстати, спасибо"].contains(on?.line ?? ""))
        // Вынули и вставили снова через 12 s — оба раза отвечает.
        let off = d.handle(Signal(.power, .chargerDisconnected, value: 80), now: now.addingTimeInterval(30), rng: &rng)
        #expect(off?.reaction == "charger.off")
        #expect(off?.behavior == .lookDown)
        #expect(["Дальше на батарейке", "Ой, провод", "Пошли гулять?"].contains(off?.line ?? ""))
        #expect(d.handle(Signal(.power, .chargerConnected, value: 80), now: now.addingTimeInterval(42), rng: &rng)?.reaction == "charger.on")
        // Дребезг разъёма — не каждый раз.
        #expect(d.handle(Signal(.power, .chargerDisconnected, value: 80), now: now.addingTimeInterval(45), rng: &rng) == nil)
    }

    /// Тихие часы: на кабель отвечает облачком — это твоё действие. Фоновое (сеть) — только глазами.
    @Test func quietHoursStillAnswerTheCable() {
        var rng = FixedRNG()
        var settings = DirectorSettings()
        settings.talkativeness = 1
        settings.quietFrom = 23 * 60 + 30
        settings.quietTo = 8 * 60
        var d = Director(settings: settings, calendar: calendar)
        let night = date(2026, 11, 3, 6)
        #expect(d.handle(Signal(.power, .chargerDisconnected, value: 100), now: night, rng: &rng)?.line != nil)
        #expect(d.handle(Signal(.network, .networkLost), now: night, rng: &rng)?.line == nil)
    }

    /// В тишине (созвон) — только глазами.
    @Test func chargerInQuietIsEyesOnly() {
        var rng = FixedRNG()
        var d = director()
        let now = date(2026, 11, 3, 11)
        _ = d.handle(Signal(.quiet, .quietOn), now: now, rng: &rng)
        let off = d.handle(Signal(.power, .chargerDisconnected, value: 80), now: now, rng: &rng)
        #expect(off?.reaction == "charger.off")
        #expect(off?.line == nil)
    }

    @Test func clockShiftDirection() {
        var rng = FixedRNG()
        var d = director()
        #expect(d.handle(Signal(.clock, .clockShifted, value: -1), now: date(2026, 10, 25, 11), rng: &rng)?.line == "Час подарили")
        var d2 = director()
        #expect(d2.handle(Signal(.clock, .clockShifted, value: 1), now: date(2026, 3, 29, 11), rng: &rng)?.line == "Час забрали")
    }

    /// Каждый новый сигнал сам по себе что-то вызывает (кроме «звук закончился» и подобных парных).
    @Test func newSignalsHaveReactions() {
        let kinds: [SignalKind] = [.chargerWeak, .chargingPaused, .networkExpensive, .bigDownload, .diskMounted, .diskYanked,
                                   .phoneConnected, .screensaverOn, .unexpectedRestart, .systemUpdated, .timeZoneChanged,
                                   .soundPlaying, .cursorShake, .itemCarried, .lidClosing]
        for kind in kinds {
            var rng = FixedRNG()
            var d = director()
            let decision = d.handle(Signal(kind.defaultSense, kind, value: 82), now: date(2026, 11, 3, 11), rng: &rng)
            #expect(decision != nil, "\(kind)")
        }
    }

    /// Реплики с зависимостью от значения — тоже по правилам голоса.
    @Test func valueDependentLinesFollowVoiceRules() {
        let context = DirectorContext(
            now: date(2026, 11, 3), calendar: calendar, mood: Mood(), today: DayMemory.Day(date: ""),
            firstPresenceToday: true, earlyBy: nil, idleSeconds: 0, userPresent: true, birthday: nil,
            pokeStreak: 1, spaceChangesRecent: 0
        )
        var lines: [String] = []
        for spec in ReactionCatalog.all where spec.id.hasPrefix("charger") || spec.id == "clockShift" {
            for value in [-1.0, 1, 10, 25, 80] {
                lines += spec.lines(Signal(.power, .chargerConnected, value: value), context)
            }
        }
        for days in [30, 100, 365, 730, 1825] { lines += Anniversary.lines(days: days) ?? [] }
        let gendered = ["устал", "голоден", "голодна", "голодный", "сыт ", "сыта", "рад ", "рада", "готов ", "пришёл", "ушёл"]
        for line in lines {
            #expect(Phrases.wordCount(line) <= Phrases.maxWords, "\(line)")
            #expect(!gendered.contains { (line.lowercased() + " ").contains($0) }, "\(line)")
        }
    }
}

/// Лог «мило / бесит» не растёт вечно: старше 30 дней и битые строки уходят.
@Suite struct FeedbackRetentionTests {
    @Test func prunesOldLines() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let iso = ISO8601DateFormatter()
        func line(_ daysAgo: Double) -> String {
            #"{"reaction":"fun.sneeze","ts":"\#(iso.string(from: now.addingTimeInterval(-daysAgo * 86_400)))","verdict":"бесит"}"#
        }
        let data = Data((line(40) + "\n" + "мусор\n" + line(3) + "\n").utf8)
        let kept = FeedbackLog.parse(FeedbackLog.pruned(data, now: now))
        #expect(kept.count == 1)
        #expect(kept.first.map { now.timeIntervalSince($0.at) < 4 * 86_400 } == true)
    }
}

/// Кулдауны переживают перезапуск: новый Director с тем же журналом не повторяет «Хочу спать».
/// «Тесно мне» — не чаще двух раз в день.
@Suite struct LedgerTests {
    @Test func cooldownsSurviveRestart() throws {
        var rng = SystemRandomNumberGenerator()
        let now = Date(timeIntervalSinceReferenceDate: 815_000_000)
        var first = Director()
        first.setMood(Mood())
        let said = first.handle(Signal(.clock, .uptimeLong, ts: now), now: now, rng: &rng)
        #expect(said?.reaction == "uptime.long")

        let url = FileManager.default.temporaryDirectory.appending(path: "ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try first.ledger.save(to: url)
        var restarted = Director()
        restarted.ledger = ReactionLedger.load(from: url)
        let later = now.addingTimeInterval(60)
        #expect(restarted.handle(Signal(.clock, .uptimeLong, ts: later), now: later, rng: &rng)?.reaction != "uptime.long")
    }

    @Test func memoryPressureTwiceADay() {
        var rng = SystemRandomNumberGenerator()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var director = Director(calendar: utc)
        // 3 ноября, 08:00 UTC — двенадцать часов в пределах одного дня.
        let start = Date(timeIntervalSince1970: 1_793_692_800)
        var fired = 0
        for hour in 0..<12 {
            let t = start.addingTimeInterval(Double(hour) * 3600)
            if director.handle(Signal(.memory, .memoryPressure, ts: t), now: t, rng: &rng)?.reaction == "memory.pressure" { fired += 1 }
        }
        #expect(fired <= 2)
    }
}

@Suite struct TrafficCounterTests {
    /// Переполнение 32-битного счётчика не теряет замер; новый интерфейс не считается.
    @Test func countsAcrossWrap() {
        let old: [String: UInt32] = ["en0": UInt32.max - 999, "en1": 10]
        let new: [String: UInt32] = ["en0": 1000, "en1": 30, "en5": 500]
        #expect(TrafficCounter.received(from: old, to: new) == 2000 + 20)
    }
}

@Suite struct NewsYoTests {
    /// «еще» → «ещё» только целым словом: «вещество» и «Ещенко» не трогаются.
    @Test func restoresYoInEshche() {
        #expect(NewsGist.clean("Перекусы оказались еще вреднее") == "Перекусы оказались ещё вреднее")
        #expect(NewsGist.clean("Еще одно вещество") == "Ещё одно вещество")
        #expect(NewsGist.clean("Ещенко и еще") == "Ещенко и ещё")
    }
}
