import Foundation
import Testing
@testable import AgentPulseCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func window(_ kind: LimitWindowKind, _ used: Double, in seconds: TimeInterval = 3600) -> LimitWindow {
    LimitWindow(kind: kind, usedPercent: used, resetsAt: t0.addingTimeInterval(seconds))
}

private func snapshot(_ used: Double, at: Date = t0, service: LimitService = .claude, in seconds: TimeInterval = 3600) -> LimitSnapshot {
    LimitSnapshot(service: service, windows: [window(.fiveHour, used, in: seconds)], at: at)
}

@Suite struct LimitsBookTests {
    @Test func zonesHaveHysteresis() {
        var book = LimitsBook()
        #expect(book.ingest(snapshot(79), now: t0).isEmpty)
        #expect(book.ingest(snapshot(80), now: t0) == [.limitLow(.claude)])
        // Дребезг у порога не шумит: выход на 5 п. п. ниже.
        #expect(book.ingest(snapshot(76), now: t0).isEmpty)
        #expect(book.ingest(snapshot(81), now: t0).isEmpty)
        #expect(book.ingest(snapshot(74), now: t0).isEmpty)
        #expect(book.reading(.claude, .fiveHour, now: t0)?.zone == .normal)
        #expect(book.ingest(snapshot(80), now: t0) == [.limitLow(.claude)])
        #expect(book.ingest(snapshot(95), now: t0) == [.limitCritical(.claude)])
        #expect(book.ingest(snapshot(91), now: t0).isEmpty)
        #expect(book.reading(.claude, .fiveHour, now: t0)?.zone == .critical)
        #expect(book.ingest(snapshot(89), now: t0).isEmpty)
        #expect(book.reading(.claude, .fiveHour, now: t0)?.zone == .attention)
    }

    @Test func jumpStraightToCriticalIsOneSignal() {
        var book = LimitsBook()
        #expect(book.ingest(snapshot(100), now: t0) == [.limitCritical(.claude)])
        #expect(book.reading(.claude, .fiveHour, now: t0)?.zone == .exhausted)
    }

    @Test func resetComesFromTimeNotFromNewSnapshot() {
        var book = LimitsBook()
        _ = book.ingest(snapshot(100, in: 60), now: t0)
        #expect(book.tick(now: t0.addingTimeInterval(59)).isEmpty)
        #expect(book.tick(now: t0.addingTimeInterval(61)) == [.limitRestored(.claude)])
        let reading = book.reading(.claude, .fiveHour, now: t0.addingTimeInterval(61))
        #expect(reading?.usedPercent == 0)
        #expect(reading?.zone == .normal)
        #expect(book.tick(now: t0.addingTimeInterval(62)).isEmpty)
    }

    @Test func expiredWindowReadsAsZeroBeforeTick() {
        var book = LimitsBook()
        _ = book.ingest(snapshot(97, in: 60), now: t0)
        #expect(book.reading(.claude, .fiveHour, now: t0.addingTimeInterval(61))?.usedPercent == 0)
    }

    @Test func noDataIsNotZero() {
        let book = LimitsBook()
        #expect(book.reading(.claude, .fiveHour, now: t0) == nil)
        #expect(book.tightest(.codex, now: t0) == nil)
    }

    @Test func staleAfterThirtyMinutes() {
        var book = LimitsBook()
        _ = book.ingest(snapshot(10, in: 7200), now: t0)
        #expect(book.reading(.claude, .fiveHour, now: t0.addingTimeInterval(1800))?.stale == false)
        #expect(book.reading(.claude, .fiveHour, now: t0.addingTimeInterval(1801))?.stale == true)
    }

    @Test func partialSnapshotKeepsOtherWindow() {
        var book = LimitsBook()
        _ = book.ingest(LimitSnapshot(service: .claude, windows: [window(.week, 40, in: 9000)], at: t0), now: t0)
        _ = book.ingest(snapshot(10), now: t0.addingTimeInterval(1))
        #expect(book.tightest(.claude, now: t0)?.kind == .week)
    }

    @Test func olderSnapshotIsIgnored() {
        var book = LimitsBook()
        _ = book.ingest(snapshot(50, at: t0.addingTimeInterval(10)), now: t0)
        #expect(book.ingest(snapshot(99, at: t0), now: t0).isEmpty)
        #expect(book.reading(.claude, .fiveHour, now: t0)?.usedPercent == 50)
    }

    @Test func restingIsOneSignalAndEndsOnReset() {
        var book = LimitsBook()
        _ = book.ingest(snapshot(60, in: 60), now: t0)
        #expect(book.markResting(.claude) == [.limitResting(.claude)])
        #expect(book.markResting(.claude).isEmpty)
        #expect(book.isCritical(.claude, now: t0))
        #expect(book.tick(now: t0.addingTimeInterval(61)) == [.limitRestored(.claude)])
        #expect(!book.isCritical(.claude, now: t0.addingTimeInterval(61)))
    }
}

@Suite struct LimitTextTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }()

    @Test func labelHasOneFormat() throws {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12)))
        let reset = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 19)))
        let reading = LimitReading(service: .claude, kind: .fiveHour, usedPercent: 76, resetsAt: reset, zone: .normal, stale: false)
        #expect(LimitText.label(reading, now: now, calendar: calendar) == "Claude · 76% · сброс 19:00")
        let later = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12)))
        #expect(LimitText.label(reading, now: later, calendar: calendar) == "Claude · 76% · сброс пт 19:00")
    }

    @Test func countdown() {
        #expect(LimitText.countdown(t0.addingTimeInterval(30), now: t0) == "меньше минуты")
        #expect(LimitText.countdown(t0.addingTimeInterval(14 * 60), now: t0) == "через 14 мин")
        #expect(LimitText.countdown(t0.addingTimeInterval(134 * 60), now: t0) == "через 2 ч 14 мин")
        #expect(LimitText.countdown(t0.addingTimeInterval(120 * 60), now: t0) == "через 2 ч")
        #expect(LimitText.countdown(t0.addingTimeInterval(76 * 3600), now: t0) == "через 3 д 4 ч")
    }
}

@Suite struct ConsoleDirectorTests {
    let limits = ConsoleCandidate(module: .limits, priority: .limitsNormal)
    let critical = ConsoleCandidate(module: .limits, priority: .limitCritical)
    let music = ConsoleCandidate(module: .media, priority: .music)

    @Test func leaderHoldsEightSecondsExceptUpward() {
        var director = ConsoleDirector()
        director.update(candidates: [limits], now: t0, agentWaiting: false, expanded: false)
        #expect(director.leader == limits)
        // Вверх по списку — сразу.
        director.update(candidates: [limits, music], now: t0.addingTimeInterval(1), agentWaiting: false, expanded: false)
        #expect(director.leader == music)
        // Вниз — только после удержания.
        director.update(candidates: [limits], now: t0.addingTimeInterval(8), agentWaiting: false, expanded: false)
        #expect(director.leader == music)
        director.update(candidates: [limits], now: t0.addingTimeInterval(9), agentWaiting: false, expanded: false)
        #expect(director.leader == limits)
    }

    @Test func nothingToShowMeansRestAfterHold() {
        var director = ConsoleDirector()
        director.update(candidates: [limits], now: t0, agentWaiting: false, expanded: false)
        director.update(candidates: [], now: t0.addingTimeInterval(3), agentWaiting: false, expanded: false)
        #expect(director.leader == limits)
        director.update(candidates: [], now: t0.addingTimeInterval(8), agentWaiting: false, expanded: false)
        #expect(director.leader == nil)
    }

    @Test func waitingChangesLeaderWithoutAnimation() {
        var director = ConsoleDirector()
        director.update(candidates: [limits], now: t0, agentWaiting: true, expanded: false)
        #expect(director.quietChange)
        director.update(candidates: [critical], now: t0.addingTimeInterval(1), agentWaiting: false, expanded: false)
        #expect(!director.quietChange)
    }

    @Test func alertsWaitForAgentAndAreNotLost() {
        var director = ConsoleDirector()
        director.raiseAlert(color: 1)
        director.update(candidates: [critical], now: t0, agentWaiting: true, expanded: false)
        #expect(director.alert == nil)
        director.update(candidates: [critical], now: t0.addingTimeInterval(30), agentWaiting: false, expanded: false)
        #expect(director.alert?.color == 1)
    }

    @Test func openConsoleIsNotTouched() {
        var director = ConsoleDirector()
        director.update(candidates: [limits], now: t0, agentWaiting: false, expanded: false)
        director.raiseAlert(color: 1)
        director.update(candidates: [critical], now: t0.addingTimeInterval(1), agentWaiting: true, expanded: true)
        #expect(director.leader == limits)
        #expect(director.alert == nil)
    }

    @Test func alertLeavesAfterEightSecondsOfInput() {
        var director = ConsoleDirector()
        director.raiseAlert(color: 1)
        director.update(candidates: [critical], now: t0, agentWaiting: false, expanded: false)
        director.noteInput(seconds: 7)
        #expect(director.alert != nil)
        director.noteInput(seconds: 1)
        #expect(director.alert == nil)
    }
}

@Suite struct LimitsModuleTests {
    @Test func priorityFollowsZones() {
        var module = LimitsModule()
        #expect(module.priority(now: t0) == nil)
        _ = module.book.ingest(snapshot(50), now: t0)
        #expect(module.priority(now: t0) == .limitsNormal)
        _ = module.book.ingest(snapshot(95), now: t0)
        #expect(module.priority(now: t0) == .limitCritical)
    }

    @Test func capsuleShowsTightestWindowOfEachService() {
        var module = LimitsModule()
        _ = module.book.ingest(LimitSnapshot(service: .claude, windows: [window(.fiveHour, 20), window(.week, 76)], at: t0), now: t0)
        _ = module.book.ingest(snapshot(30, service: .codex), now: t0)
        let capsule = module.capsule(now: t0)
        #expect(capsule.rings.map(\.service) == [.claude, .codex])
        #expect(capsule.rings[0].fraction == 0.76)
        #expect(capsule.label.hasPrefix("Claude · 76% · сброс"))
    }
}

@Suite struct ToolSignalTests {
    /// Правило ТЗ: мозг маскота не получает строк — ни текста, ни названий.
    @Test func carriesNoStrings() {
        func hasString(_ value: Any) -> Bool {
            if value is String || value is Substring { return true }
            return Mirror(reflecting: value).children.contains { hasString($0.value) }
        }
        #expect(!ToolSignal.all.isEmpty)
        for signal in ToolSignal.all {
            #expect(!hasString(signal))
        }
    }

    @Test func goesToBrainAsNumber() throws {
        let signal = try #require(ToolSignal.limitCritical(.codex).signal(at: t0))
        #expect(signal.sense == .console)
        #expect(signal.kind == .limitCritical)
        #expect(LimitService(signalValue: signal.value) == .codex)
    }
}

@Suite struct ConsoleLayoutTests {
    @Test func narrowsWhenDockIsWide() {
        let small = DockMetrics(edge: .bottom, tileSize: 48, icons: 11, hidden: false)
        #expect(ConsoleLayout.fit(screenWidth: 1680, dock: small) == .full(width: 220))
        let wide = DockMetrics(edge: .bottom, tileSize: 60, icons: 22, hidden: false)
        #expect(ConsoleLayout.fit(screenWidth: 1680, dock: wide) == .leader)
        let huge = DockMetrics(edge: .bottom, tileSize: 80, icons: 22, hidden: false)
        #expect(ConsoleLayout.fit(screenWidth: 1680, dock: huge) == .dot)
    }

    /// Замер: 11 иконок при tilesize 81 дают Dock 988 pt.
    @Test func dockLengthMatchesMeasurement() {
        let dock = DockMetrics(edge: .bottom, tileSize: 81, icons: 11, hidden: false)
        #expect(abs(dock.length - 988) < 8)
    }

    @Test func expandedStaysClearOfDock() {
        let dock = DockMetrics(edge: .bottom, tileSize: 81, icons: 11, hidden: false)
        let width = ConsoleLayout.expandedWidth(screenWidth: 1680, dock: dock)
        #expect(width < 360)
        #expect(ConsoleLayout.screenMargin + width + ConsoleLayout.dockGap <= (1680 - dock.length) / 2)
        #expect(ConsoleLayout.expandedWidth(screenWidth: 3000, dock: dock) == 360)
    }

    @Test func unknownDockShrinksToLeader() {
        #expect(ConsoleLayout.fit(screenWidth: 1680, dock: nil) == .leader)
    }

    @Test func sideDockMovesConsoleAside() {
        let left = DockMetrics(edge: .left, tileSize: 48, icons: 11, hidden: false)
        #expect(ConsoleLayout.sideInset(dock: left, onRight: false) > ConsoleLayout.screenMargin)
        #expect(ConsoleLayout.sideInset(dock: left, onRight: true) == ConsoleLayout.screenMargin)
        #expect(ConsoleLayout.fit(screenWidth: 1680, dock: left) == .full(width: 220))
    }
}

@Suite struct MeetingLinksTests {
    private func link(url: String? = nil, location: String? = nil, notes: String? = nil) -> MeetingLink? {
        MeetingLinks.find(url: url.flatMap(URL.init(string:)), location: location, notes: notes)
    }

    /// Тестовый календарь приёмки: `Войти` должна открыть звонок в ≥ 95% событий.
    @Test func recognizesCorpus() {
        let corpus: [(String?, String?, String?, MeetingService)] = [
            ("https://zoom.us/j/1234567890", nil, nil, .zoom),
            ("https://us02web.zoom.us/j/1234567890?pwd=abc", nil, nil, .zoom),
            (nil, "https://company.zoom.us/my/room", nil, .zoom),
            (nil, nil, "Подключиться: https://zoom.us/j/99 пароль 123", .zoom),
            (nil, "Переговорная 3, https://zoom.us/s/55", nil, .zoom),
            (nil, nil, "<https://us06web.zoom.us/w/123?tk=x>", .zoom),
            (nil, nil, "zoommtg://zoom.us/join?confno=123", .zoom),
            ("https://meet.google.com/abc-defg-hij", nil, nil, .meet),
            (nil, "https://meet.google.com/abc-defg-hij", nil, .meet),
            (nil, nil, "Google Meet: meet.google.com/abc-defg-hij", .meet),
            (nil, nil, "Join: https://meet.google.com/abc-defg-hij?authuser=0.", .meet),
            (nil, nil, "https://www.google.com/url?q=https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij", .meet),
            ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0?context=y", nil, nil, .teams),
            (nil, nil, "Microsoft Teams meeting https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0", .teams),
            (nil, nil, "https://teams.live.com/meet/9876", .teams),
            (nil, nil, "https://teams.microsoft.com/meet/123456?p=abc", .teams),
            (nil, nil, "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2Fx&data=1", .teams),
            ("https://telemost.yandex.ru/j/12345678901234", nil, nil, .telemost),
            (nil, "https://telemost.360.yandex.ru/j/12345", nil, .telemost),
            (nil, nil, "Телемост: telemost.yandex.ru/j/12345", .telemost),
            (nil, nil, "https://telemost.yandex.com/j/777", .telemost),
        ]
        let hits = corpus.filter { url, location, notes, service in link(url: url, location: location, notes: notes)?.service == service }
        #expect(Double(hits.count) / Double(corpus.count) >= 0.95, "распознано \(hits.count) из \(corpus.count)")
    }

    @Test func ignoresOrdinaryLinks() {
        #expect(link(url: "https://example.com/doc") == nil)
        #expect(link(notes: "Повестка: https://docs.google.com/document/d/1") == nil)
        #expect(link(notes: "https://zoom.us/pricing") == nil)
        #expect(link(notes: "https://teams.microsoft.com/downloads") == nil)
        #expect(link(location: "Переговорная 3") == nil)
    }

    @Test func urlFieldWinsOverNotes() {
        #expect(link(url: "https://zoom.us/j/1", notes: "https://meet.google.com/abc-defg-hij")?.service == .zoom)
    }
}

@Suite struct CalendarModuleTests {
    let call = MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!)

    private func module(_ events: MeetingEvent...) -> CalendarModule {
        var module = CalendarModule()
        module.update(events: events)
        return module
    }

    private func event(in minutes: Double, link: MeetingLink? = nil, allDay: Bool = false, title: String = "Синк") -> MeetingEvent {
        let start = t0.addingTimeInterval(minutes * 60)
        return MeetingEvent(id: "e\(minutes)", title: title, start: start, end: start.addingTimeInterval(1800), isAllDay: allDay, link: link)
    }

    @Test func leaderTenMinutesBefore() {
        let module = module(event(in: 8, link: call))
        #expect(module.priority(now: t0) == .meetingSoon)
        #expect(module.capsule(now: t0).label == "Синк · через 8 мин")
        #expect(module.capsule(now: t0).tail == "· через 8 мин")
        #expect(module.capsule(now: t0).action == .join(call.url))
        #expect(module.priority(now: t0.addingTimeInterval(-3 * 60)) == nil)
    }

    @Test func noLinkNoButton() {
        #expect(module(event(in: 5)).capsule(now: t0).action == nil)
    }

    @Test func warnsOncePerMeetingNotPerDay() {
        var module = module(event(in: 10), event(in: 20))
        #expect(module.tick(now: t0).contains(.meetingSoon))
        #expect(!module.tick(now: t0).contains(.meetingSoon))
        #expect(module.tick(now: t0.addingTimeInterval(600)).contains(.meetingSoon))
    }

    @Test func lastCallIsOneAlert() {
        var module = module(event(in: 1))
        let signals = module.tick(now: t0)
        #expect(signals.contains(.meetingLastCall))
        #expect(ToolSignal.meetingLastCall.isAlert)
        #expect(!module.tick(now: t0).contains(.meetingLastCall))
    }

    @Test func startedLateDoesNotWarn() {
        var module = module(event(in: -3, link: call))
        #expect(!module.tick(now: t0).contains(.meetingSoon))
        #expect(module.capsule(now: t0).label == "Синк · идёт")
    }

    @Test func onlyRealCallsSilenceMascot() {
        #expect(module(event(in: -1, link: call)).wantsQuiet(now: t0))
        #expect(!module(event(in: -1)).wantsQuiet(now: t0))
        #expect(!module(event(in: -1, link: call, allDay: true)).wantsQuiet(now: t0))
        #expect(!module(event(in: 1, link: call)).wantsQuiet(now: t0))
        #expect(!module(event(in: -40, link: call)).wantsQuiet(now: t0))
    }

    @Test func allDayIsNeverLeader() {
        #expect(module(event(in: 5, allDay: true)).priority(now: t0) == nil)
    }

    @Test func freeDayIsOncePerDay() {
        var module = CalendarModule()
        #expect(module.tick(now: t0).contains(.dayFree))
        #expect(!module.tick(now: t0).contains(.dayFree))
        var busy = self.module(event(in: 30, link: call))
        #expect(!busy.tick(now: t0).contains(.dayFree))
    }
}

@Suite struct ShelfModuleTests {
    let a = URL(fileURLWithPath: "/tmp/a.txt"), b = URL(fileURLWithPath: "/tmp/b.png")

    @Test func keepsFilesWithoutDuplicates() {
        var shelf = ShelfModule()
        #expect(shelf.priority(now: t0) == nil)
        #expect(shelf.add([a]) == [.shelfChanged])
        #expect(shelf.add([a]).isEmpty)
        _ = shelf.add([b])
        #expect(shelf.items.map(\.name) == ["a.txt", "b.png"])
        #expect(shelf.capsule(now: t0).text == "2 файла")
        #expect(shelf.priority(now: t0) == .shelf)
        shelf.remove(a)
        #expect(shelf.capsule(now: t0).text == "1 файл")
        shelf.clear()
        #expect(shelf.priority(now: t0) == nil)
    }
}

@Suite struct MediaModuleTests {
    /// Строка настоящего `stream --no-diff`, название заменено.
    static let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome","playing":true,"title":"Трек","artist":"Автор","duration":1003.741,"elapsedTime":10,"timestamp":"2026-11-06T23:28:44Z","playbackRate":1}}"#

    @Test func parsesStream() throws {
        guard case .playing(let playing) = try #require(MediaRemoteStream.parse(Data(Self.line.utf8))) else {
            Issue.record("ожидался трек")
            return
        }
        #expect(playing.line == "Автор — Трек")
        #expect(playing.isPlaying)
        #expect(playing.duration == 1003.741)
        #expect(abs(playing.position(now: playing.at.addingTimeInterval(5)) - 15) < 0.001)
    }

    @Test func emptyPayloadMeansNothing() {
        #expect(MediaRemoteStream.parse(Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8)) == .nothing)
        #expect(MediaRemoteStream.parse(Data("мусор".utf8)) == nil)
    }

    @Test func infiniteDurationIsDropped() throws {
        let line = #"{"type":"data","diff":false,"payload":{"playing":false,"title":"Т","duration":0}}"#
        guard case .playing(let playing) = try #require(MediaRemoteStream.parse(Data(line.utf8))) else {
            Issue.record("ожидался трек")
            return
        }
        #expect(playing.duration == nil)
    }

    @Test func leaderOnlyWhilePlaying() {
        var media = MediaModule()
        media.playing = NowPlaying(title: "Т", artist: nil, isPlaying: false, duration: nil, elapsed: 0, at: t0)
        #expect(media.priority(now: t0) == nil)
        media.playing?.isPlaying = true
        #expect(media.priority(now: t0) == .music)
    }
}

@Suite struct ConsoleBrainTests {
    @Test func meetingSoonOncePerMeetingNotOncePerDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        var settings = DirectorSettings()
        settings.quietFrom = nil
        settings.quietTo = nil
        settings.talkativeness = 1
        var director = Director(settings: settings, calendar: calendar)
        var rng = FixedRNG()
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 10)))
        let first = director.handle(try #require(ToolSignal.meetingSoon.signal(at: morning)), now: morning, rng: &rng)
        #expect(["Скоро встреча", "Встреча уже близко"].contains(first?.line ?? ""))
        let later = morning.addingTimeInterval(3600)
        #expect(director.handle(try #require(ToolSignal.meetingSoon.signal(at: later)), now: later, rng: &rng) != nil)
    }

    @Test func modulesQuietGoesDirectlyToDirector() throws {
        var director = Director(settings: DirectorSettings(), calendar: .current)
        var rng = FixedRNG()
        _ = director.handle(try #require(ToolSignal.quiet(true).signal(at: t0)), now: t0, rng: &rng)
        #expect(director.isQuiet)
        _ = director.handle(try #require(ToolSignal.quiet(false).signal(at: t0)), now: t0, rng: &rng)
        #expect(!director.isQuiet)
    }

    @Test func eatenFileAnswersUser() {
        var director = Director(settings: DirectorSettings(), calendar: .current)
        var rng = FixedRNG()
        let eaten = director.handle(Signal(.console, .fileEaten, ts: t0), now: t0, rng: &rng)
        #expect(["Ням, положу", "Ням, на полку"].contains(eaten?.line ?? ""))
        #expect(eaten?.answersUser == true)
    }
}
