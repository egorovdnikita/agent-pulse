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
        // Новая загрузка без штатного выхода.
        #expect(record.start(bootTime: 9000, osVersion: "26.0", now: date(2026, 11, 2)) == [.unexpectedRestart])
        // Штатный выход, перезагрузка с обновлением.
        record.cleanExit = true
        #expect(record.start(bootTime: 20000, osVersion: "26.1", now: date(2026, 11, 3)) == [.systemUpdated])
        #expect(record.firstSeen == date(2026, 11, 1))
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
