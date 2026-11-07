import AppKit
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
        let meeting = ConsoleCandidate(module: .calendar, priority: .meetingSoon)
        director.update(candidates: [limits, meeting], now: t0.addingTimeInterval(1), agentWaiting: false, expanded: false)
        #expect(director.leader == meeting)
        // Вниз — только после удержания.
        director.update(candidates: [limits], now: t0.addingTimeInterval(8), agentWaiting: false, expanded: false)
        #expect(director.leader == meeting)
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
        #expect(module.priority(now: t0) == .limitsNormal)
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
    private let screen = CGRect(x: 0, y: 0, width: 1680, height: 1050)

    @Test func capsuleSitsOnDockLevel() {
        let visible = CGRect(x: 0, y: 107, width: 1680, height: 912)
        #expect(Double(ConsoleLayout.capsuleY(screen: screen, visible: visible)) == 37.5)
    }

    @Test func panelStandsAboveDockByTheGapFromTheEdge() {
        let visible = CGRect(x: 0, y: 107, width: 1680, height: 912)
        let capsuleTop = ConsoleLayout.capsuleY(screen: screen, visible: visible) + ConsoleLayout.capsuleHeight
        #expect(capsuleTop + ConsoleLayout.gap(screen: screen, visible: visible) == 107 + ConsoleLayout.screenGap)
        #expect(ConsoleLayout.x(visible: visible, width: 460, onLeft: true) == ConsoleLayout.screenGap)
    }

    @Test func followsDockHeight() {
        let small = ConsoleLayout.gap(screen: screen, visible: CGRect(x: 0, y: 60, width: 1680, height: 960))
        let tall = ConsoleLayout.gap(screen: screen, visible: CGRect(x: 0, y: 130, width: 1680, height: 890))
        #expect(tall > small)
    }

    @Test func hiddenDockKeepsSmallestGap() {
        let visible = CGRect(x: 0, y: 4, width: 1680, height: 1016)
        #expect(ConsoleLayout.capsuleY(screen: screen, visible: visible) == ConsoleLayout.edgeMargin)
        #expect(ConsoleLayout.gap(screen: screen, visible: visible) == ConsoleLayout.expandedGap)
    }

    @Test func sideDockMovesItAside() {
        let visible = CGRect(x: 80, y: 0, width: 1600, height: 1020)
        #expect(ConsoleLayout.x(visible: visible, width: 220, onLeft: true) == 80 + ConsoleLayout.screenGap)
    }

    @Test func mirrorsToTheRight() {
        let visible = CGRect(x: 0, y: 107, width: 1680, height: 912)
        #expect(ConsoleLayout.x(visible: visible, width: 220, onLeft: false) == 1680 - ConsoleLayout.screenGap - 220)
    }

    @Test func capsuleNarrowsNextToWideDock() {
        let small = DockMetrics(edge: .bottom, tileSize: 48, icons: 11, hidden: false)
        #expect(ConsoleLayout.fit(screenWidth: 1680, dock: small) == .full(width: 220))
        let wide = DockMetrics(edge: .bottom, tileSize: 60, icons: 22, hidden: false)
        #expect(ConsoleLayout.fit(screenWidth: 1680, dock: wide) == .leader)
        let huge = DockMetrics(edge: .bottom, tileSize: 80, icons: 22, hidden: false)
        #expect(ConsoleLayout.fit(screenWidth: 1680, dock: huge) == .dot)
    }

    @Test func dockLengthMatchesMeasurement() {
        let dock = DockMetrics(edge: .bottom, tileSize: 81, icons: 11, hidden: false)
        #expect(abs(dock.length - 988) < 10)
    }

    @Test func unknownDockShrinksToLeader() {
        #expect(ConsoleLayout.fit(screenWidth: 1680, dock: nil) == .leader)
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

    @Test func leaderTwoMinutesBefore() {
        let module = module(event(in: 8, link: call))
        #expect(module.priority(now: t0) == nil)
        #expect(module.priority(now: t0.addingTimeInterval(8 * 60)) == .meetingSoon)
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

@Suite struct PrompterTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    private func words(_ count: Int) -> String { (1...count).map { "слово\($0)" }.joined(separator: " ") }

    @Test func clockAdvancesAtSpeedAndCapsuleShowsTime() {
        var module = PrompterModule()
        let started = module.start(text: words(130), now: start)
        #expect(started)
        _ = module.advance(now: start.addingTimeInterval(30))
        #expect(abs(module.position - 65) < 0.01)
        let capsule = module.capsule(now: start)
        #expect(capsule.text == "Суфлёр")
        #expect(capsule.tail == "0:30 из 1:00")
        #expect(module.priority(now: start) == .activeMode)
        #expect(module.wantsQuiet(now: start))
    }

    @Test func emptyTextDoesNotStart() {
        var module = PrompterModule()
        let started = module.start(text: " \n ", now: start)
        #expect(!started)
        #expect(!module.isActive)
        #expect(module.priority(now: start) == nil)
        #expect(!module.wantsQuiet(now: start))
    }

    @Test func pauseStopsTextWithoutJumpAfterResume() {
        var module = PrompterModule()
        module.start(text: words(130), now: start)
        module.togglePause(now: start)
        _ = module.advance(now: start.addingTimeInterval(60))
        #expect(module.position == 0)
        #expect(module.wantsQuiet(now: start))
        module.togglePause(now: start.addingTimeInterval(60))
        _ = module.advance(now: start.addingTimeInterval(61))
        #expect(abs(module.position - 130.0 / 60) < 0.01)
    }

    @Test func speedStepsByQuarterAndStaysInRange() {
        var module = PrompterModule()
        module.changeSpeed(faster: true)
        #expect(module.multiplierText == "1.25x")
        #expect(module.speed == 163)
        module.setSpeed(9999)
        #expect(module.multiplier == 2)
        module.changeSpeed(faster: true)
        #expect(module.speed == PrompterModule.speedRange.upperBound)
        module.setSpeed(1)
        #expect(module.multiplier == 0.5)
        module.setSpeed(143)
        #expect(module.multiplierText == "1.00x")
    }

    @Test func finishesAfterHoldAtEnd() {
        var module = PrompterModule()
        module.start(text: "раз два", now: start)
        let early = module.advance(now: start.addingTimeInterval(10))
        #expect(!early)
        #expect(module.isActive)
        let finished = module.advance(now: start.addingTimeInterval(13))
        #expect(finished)
        #expect(!module.isActive)
    }

    @Test func linesWrapKeepWordNumbersAndParagraphs() {
        let script = PrompterScript(text: "один два три\nчетыре")
        let lines = script.lines { $0.count <= 8 }
        #expect(lines.map(\.text) == ["один два", "три", "четыре"])
        #expect(lines.map(\.words) == [0..<2, 2..<3, 3..<4])
        #expect(PrompterScript.lineIndex(of: 2, in: lines) == 1)
        #expect(PrompterScript.lineIndex(of: 99, in: lines) == 2)
    }

    @Test func voiceFollowsSpeechAndIgnoresPunctuationCaseAndYo() {
        let script = PrompterScript(text: "Ещё раз, друзья: мы идём к новому экрану оплаты")
        #expect(PrompterVoiceMatch.position(heard: ["еще", "раз", "друзья"], in: script.normalized, from: 0) == 3)
        #expect(PrompterVoiceMatch.position(heard: ["новому", "экрану"], in: script.normalized, from: 3) == 8)
    }

    @Test func voiceToleratesEndingsButNotNoise() {
        let script = PrompterScript(text: "показать результаты тестирования команде").normalized
        #expect(PrompterVoiceMatch.position(heard: ["результат", "тестирование"], in: script, from: 0) == 3)
        #expect(PrompterVoiceMatch.position(heard: ["кофе"], in: script, from: 0) == nil)
        #expect(PrompterVoiceMatch.position(heard: [], in: script, from: 0) == nil)
    }

    @Test func voicePrefersNearestRepeat() {
        let filler = Array(repeating: "пауза", count: 10)
        let script = ["важный", "вопрос"] + filler + ["важный", "вопрос"]
        #expect(PrompterVoiceMatch.position(heard: ["важный", "вопрос"], in: script, from: 11) == 14)
    }

    @Test func oneShortWordDoesNotJump() {
        let script = PrompterScript(text: "мы начали и закончили и пошли").normalized
        #expect(PrompterVoiceMatch.position(heard: ["и"], in: script, from: 0) == nil)
    }

    @Test func voiceHoldsAfterSilenceAndNeverGoesBack() {
        var module = PrompterModule()
        module.followsVoice = true
        module.start(text: "первая вторая третья четвёртая —", now: start)
        #expect(module.voiceHolds(now: start))
        module.hear(["первая", "вторая", "третья"], now: start)
        #expect(module.position == 3)
        #expect(!module.voiceHolds(now: start.addingTimeInterval(1)))
        #expect(module.voiceHolds(now: start.addingTimeInterval(1.5)))
        _ = module.advance(now: start.addingTimeInterval(20))
        #expect(module.position == 3)
        module.hear(["первая", "вторая"], now: start.addingTimeInterval(21))
        #expect(module.position == 3)
        module.hear(["третья", "четвертая"], now: start.addingTimeInterval(22))
        #expect(module.position == 5)
    }

    @Test func libraryKeepsLastFiveWithoutDuplicatesAndSurvivesReload() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "prompter-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var library = PrompterLibrary()
        for number in 1...7 { library.remember("текст \(number)") }
        library.remember("текст 5")
        library.remember("   ")
        #expect(library.texts == ["текст 5", "текст 7", "текст 6", "текст 4", "текст 3"])
        library.remove("текст 7")
        library.save(to: url)
        #expect(PrompterLibrary.load(from: url) == library)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func panelSitsAtNotchOrUnderMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 80, width: 1512, height: 865)
        let notched = PrompterLayout.frame(screen: screen, visible: visible, notch: 37)
        #expect(notched.maxY == 982)
        #expect(notched.midX == 756)
        #expect(Double(notched.width) == PrompterLayout.width)
        #expect(Double(notched.height) == PrompterLayout.textHeight + 37)
        let plain = PrompterLayout.frame(screen: screen, visible: visible, notch: 0)
        #expect(Double(plain.maxY) == 945 - PrompterLayout.menuBarGap)
        #expect(Double(plain.height) == PrompterLayout.textHeight)
    }

    @Test func oldConfigWithoutPrompterKeysLoads() throws {
        var config = PulseConfig()
        config.console.calendar = true
        let data = try JSONEncoder().encode(config)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var console = try #require(json["console"] as? [String: Any])
        for key in ["prompter", "prompterHidden", "prompterVoice", "prompterSpeed"] { console[key] = nil }
        json["console"] = console
        let old = try JSONSerialization.data(withJSONObject: json)
        let loaded = PulseConfig.decode(old)
        #expect(loaded.console.calendar)
        #expect(loaded.console.prompter)
        #expect(loaded.console.prompterHidden)
        #expect(!loaded.console.prompterVoice)
        #expect(loaded.console.prompterSpeed == PrompterModule.defaultSpeed)
    }
}

@Suite struct DictationTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func noModelMeansNoRecordingAndANotice() {
        var module = DictationModule()
        let recording = module.press(now: start, modelReady: false)
        #expect(!recording)
        #expect(module.phase == .idle)
        #expect(module.capsule(now: start).text == "Скачай модель")
        #expect(module.priority(now: start.addingTimeInterval(5)) == nil)
    }

    @Test func accidentalPressRecognizesNothing() {
        var module = DictationModule()
        let recording = module.press(now: start, modelReady: true)
        #expect(recording)
        let recognize = module.release(now: start.addingTimeInterval(0.29))
        #expect(!recognize)
        #expect(module.phase == .idle)
    }

    @Test func holdIsRecognizedAndQuietOnlyWhileRecording() {
        var module = DictationModule()
        _ = module.press(now: start, modelReady: true)
        #expect(module.wantsQuiet(now: start))
        #expect(module.capsule(now: start).wave)
        #expect(module.capsule(now: start).text == nil)
        #expect(module.priority(now: start) == .activeMode)
        let recognize = module.release(now: start.addingTimeInterval(0.31))
        #expect(recognize)
        #expect(module.phase == .recognizing)
        #expect(!module.wantsQuiet(now: start))
        module.finish(now: start, notice: .inClipboard)
        #expect(module.capsule(now: start).text == "Текст в буфере")
    }

    @Test func secondPressWhileRecognizingIsIgnored() {
        var module = DictationModule()
        _ = module.press(now: start, modelReady: true)
        _ = module.release(now: start.addingTimeInterval(1))
        let again = module.press(now: start.addingTimeInterval(1.1), modelReady: true)
        #expect(!again)
        #expect(module.phase == .recognizing)
    }

    @Test func recordingStopsAtLimit() {
        var module = DictationModule()
        _ = module.press(now: start, modelReady: true)
        #expect(!module.reachedLimit(now: start.addingTimeInterval(299)))
        #expect(module.reachedLimit(now: start.addingTimeInterval(300)))
    }

    @Test func rulesReplaceWholeWordsInAnyCase() {
        #expect(DictationRules.apply("Сделай диплой и пул реквест на гитхаб") == "Сделай deploy и pull request на GitHub")
        // Начало предложения остаётся началом предложения.
        #expect(DictationRules.apply("Коммит готов") == "Commit готов")
        // Часть слова не трогаем.
        #expect(DictationRules.apply("коммитмент") == "коммитмент")
    }

    @Test func customRulesWinAndSpecialCharactersAreLiteral() {
        let custom = [DictationRule(spoken: "коммит", written: "фиксация"), DictationRule(spoken: "си плюс плюс", written: "C++ $1")]
        #expect(DictationRules.apply("коммит на си плюс плюс", custom: custom) == "фиксация на C++ $1")
        #expect(DictationRules.apply("текст", custom: [DictationRule(spoken: "  ", written: "x")]) == "текст")
    }

    @Test func longRecordingIsCutAtTheQuietestPoint() {
        var samples = [Float](repeating: 0.5, count: DictationChunks.limit + 8000)
        let quiet = DictationChunks.limit - DictationChunks.sampleRate * 2
        for index in quiet..<(quiet + 4000) { samples[index] = 0 }
        let ranges = DictationChunks.ranges(of: samples)
        #expect(ranges.count == 2)
        #expect(ranges[0].upperBound >= quiet && ranges[0].upperBound <= quiet + 4000)
        #expect(ranges[0].upperBound == ranges[1].lowerBound)
        #expect(ranges[1].upperBound == samples.count)
    }

    @Test func chunksCoverEverySampleAndStayWithinLimit() {
        let samples = [Float](repeating: 0.1, count: DictationChunks.limit * 4 + 123)
        let ranges = DictationChunks.ranges(of: samples)
        #expect(ranges.allSatisfy { $0.count <= DictationChunks.limit })
        #expect(ranges.reduce(0) { $0 + $1.count } == samples.count)
        #expect(DictationChunks.ranges(of: []).isEmpty)
    }

    @Test func insertPlanNeverLosesText() {
        #expect(DictationInsertPlan.choose(accessibility: false, role: "AXTextArea") == .clipboard)
        #expect(DictationInsertPlan.choose(accessibility: true, role: "AXTextArea") == .field)
        #expect(DictationInsertPlan.choose(accessibility: true, role: "AXGroup") == .pasteKeepingClipboard)
        #expect(DictationInsertPlan.choose(accessibility: true, role: nil) == .pasteKeepingClipboard)
    }

    @Test func historyKeepsThirtyDaysAndFileIsPrivate() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        var history = DictationHistory()
        history.add("старое", now: start)
        history.add("новое", now: start.addingTimeInterval(29 * 86400))
        history.save(to: url)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(mode == 0o600)
        let loaded = DictationHistory.load(from: url, now: start.addingTimeInterval(31 * 86400))
        #expect(loaded.entries.map(\.text) == ["новое"])
        DictationHistory.erase(at: url)
        #expect(DictationHistory.load(from: url).entries.isEmpty)
    }

    @Test func partialModelIsNotInstalled() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for file in DictationModelSpec.files {
            try Data(count: 1).write(to: folder.appending(path: file.name))
        }
        #expect(!DictationModelSpec.isInstalled(at: folder))
    }

    @Test func oldConfigGetsDictationOff() throws {
        let config = try PulseConfig.decode(Data(#"{"console":{"prompter":false}}"#.utf8))
        #expect(!config.console.dictation)
        #expect(!config.console.accessibility)
        #expect(!config.console.dictationHistory)
        #expect(config.console.dictationLanguage == "ru")
    }

    @Test func activeLeaderLeavesAtOnceOthersHold() {
        var director = ConsoleDirector()
        let dictation = ConsoleCandidate(module: .dictation, priority: .activeMode)
        let limits = ConsoleCandidate(module: .limits, priority: .limitsNormal)
        director.update(candidates: [limits], now: start, agentWaiting: false, expanded: false)
        director.update(candidates: [limits, dictation], now: start.addingTimeInterval(1), agentWaiting: false, expanded: false)
        #expect(director.leader == dictation)
        director.update(candidates: [limits], now: start.addingTimeInterval(2), agentWaiting: false, expanded: false)
        #expect(director.leader == limits)
    }
}

@Suite struct TranslateTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func directionFollowsTheText() {
        #expect(TranslateDirection.detect("Привет, мир") == .ruToEn)
        #expect(TranslateDirection.detect("Hello, world") == .enToRu)
        #expect(TranslateDirection.detect("Запусти deploy на сервере") == .ruToEn)
        #expect(TranslateDirection.detect("Run деплой on the production server") == .enToRu)
    }

    @Test func selectionIsTranslatedAndReplaceable() {
        var module = TranslateModule()
        let text = module.press(selection: "  привет\n", clipboard: "буфер", now: start)
        #expect(text == "привет")
        #expect(module.replaceable)
        module.finish(source: "привет", result: "hello")
        #expect(module.state == .done(source: "привет", result: "hello"))
    }

    @Test func withoutSelectionSecondPressTakesClipboardOnly() {
        var module = TranslateModule()
        let first = module.press(selection: nil, clipboard: "буфер", now: start)
        #expect(first == nil)
        #expect(module.state == .askToCopy)
        let second = module.press(selection: nil, clipboard: "буфер", now: start.addingTimeInterval(5))
        #expect(second == "буфер")
        #expect(!module.replaceable)
    }

    @Test func hintExpiresSoOldClipboardIsNotRead() {
        var module = TranslateModule()
        _ = module.press(selection: "", clipboard: nil, now: start)
        let late = module.press(selection: nil, clipboard: "буфер", now: start.addingTimeInterval(61))
        #expect(late == nil)
        #expect(module.state == .askToCopy)
    }

    @Test func staleResultDoesNotOverwriteNewerRequest() {
        var module = TranslateModule()
        _ = module.press(selection: "первое", clipboard: nil, now: start)
        _ = module.press(selection: "второе", clipboard: nil, now: start)
        module.finish(source: "первое", result: "first")
        #expect(module.state == .working(source: "второе"))
    }
}

@Suite struct GaugeResetTests {
    @Test func gaugeShowsTimeTodayAndShortCountdownLater() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        #expect(LimitText.gaugeReset(now.addingTimeInterval(3600), now: now, calendar: calendar).count == 5)
        let later = LimitText.gaugeReset(now.addingTimeInterval(4 * 86_400 + 6 * 3600), now: now, calendar: calendar)
        #expect(!later.hasPrefix("через"))
        #expect(later.contains("4"))
    }
}

@Suite struct PageSwipeTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func run(_ events: [(Double, Double, PageSwipe.Phase)]) -> [Int] {
        var swipe = PageSwipe()
        var date = start
        var steps: [Int] = []
        for event in events {
            date = date.addingTimeInterval(0.01)
            if let step = swipe.feed(dx: event.0, dy: event.1, phase: event.2, at: date) { steps.append(step) }
        }
        return steps
    }

    @Test func longSwipeTurnsOnePage() {
        let moves = Array(repeating: (12.0, 0.0, PageSwipe.Phase.moved), count: 30)
        #expect(run([(1, 0, .began)] + moves + [(0, 0, .ended)]) == [1])
    }

    @Test func swipeBackGoesBack() {
        #expect(run([(0, 0, .began), (-20, 0, .moved), (-20, 0, .moved)]) == [-1])
    }

    @Test func shortFlickIsFinishedByMomentum() {
        let flick: [(Double, Double, PageSwipe.Phase)] = [(0, 0, .began), (9, 0, .moved), (9, 0, .moved), (0, 0, .ended), (8, 0, .momentum), (7, 0, .momentum)]
        #expect(run(flick) == [1])
    }

    @Test func momentumDoesNotTurnSecondPage() {
        let moves: [(Double, Double, PageSwipe.Phase)] = [(0, 0, .began), (40, 0, .moved), (0, 0, .ended)]
        #expect(run(moves + Array(repeating: (40, 0, .momentum), count: 10)) == [1])
    }

    @Test func diagonalEventsStillCount() {
        // Отдельные события косые, но весь жест — вбок.
        let moves: [(Double, Double, PageSwipe.Phase)] = [(0, 0, .began), (6, 7, .moved), (14, -6, .moved), (8, 2, .moved), (10, -2, .moved)]
        #expect(run(moves) == [1])
    }

    @Test func verticalScrollDoesNotTurnPage() {
        let moves: [(Double, Double, PageSwipe.Phase)] = [(0, 0, .began), (2, 25, .moved), (30, 10, .moved), (30, 10, .moved)]
        #expect(run(moves).isEmpty)
    }

    @Test func nextGestureWorksAfterTheFirst() {
        let one: [(Double, Double, PageSwipe.Phase)] = [(0, 0, .began), (40, 0, .moved), (0, 0, .ended)]
        #expect(run(one + one) == [1, 1])
    }

    @Test func wheelWaitsForPauseBeforeNextPage() {
        var swipe = PageSwipe()
        #expect(swipe.feed(dx: 40, dy: 0, phase: .wheel, at: start) == 1)
        #expect(swipe.feed(dx: 40, dy: 0, phase: .wheel, at: start.addingTimeInterval(0.1)) == nil)
        #expect(swipe.feed(dx: 40, dy: 0, phase: .wheel, at: start.addingTimeInterval(1)) == 1)
    }
}

@Suite struct ScrollAxisTests {
    @Test func sidewaysBelongsToPages() {
        var axis = ScrollAxis()
        #expect(axis.feed(dx: 1, dy: 0) == nil)
        #expect(axis.feed(dx: 5, dy: 1) == .pages)
    }

    @Test func upDownBelongsToList() {
        var axis = ScrollAxis()
        #expect(axis.feed(dx: 1, dy: 6) == .list)
    }

    @Test func decisionHoldsForWholeGesture() {
        var axis = ScrollAxis()
        _ = axis.feed(dx: 6, dy: 0)
        #expect(axis.feed(dx: 0, dy: 100) == .pages)
        axis.begin()
        #expect(axis.feed(dx: 0, dy: 10) == .list)
    }

    @Test func emptyEventsDecideNothing() {
        var axis = ScrollAxis()
        #expect(axis.feed(dx: 0, dy: 0) == nil)
        #expect(axis.owner == nil)
    }
}

@Suite struct CapsuleDefaultTests {
    @Test func limitsLeadEvenWithoutData() {
        let module = LimitsModule()
        let now = Date()
        #expect(module.priority(now: now) == .limitsNormal)
        let rings = module.capsule(now: now).rings
        #expect(rings.count == LimitService.allCases.count)
        #expect(rings.allSatisfy { $0.fraction == nil })
    }

    @Test func limitsBeatMusicAndShelfButNotMeetingOrRecording() {
        #expect(ConsolePriority.limitsNormal < .music)
        #expect(ConsolePriority.limitsNormal < .shelf)
        #expect(ConsolePriority.meetingSoon < .limitsNormal)
        #expect(ConsolePriority.activeMode < .limitsNormal)
    }
}

@Suite struct ShelfFileKindTests {
    @Test func kindFollowsExtensionInAnyCase() {
        #expect(ShelfFileKind(name: "Снимок.PNG") == .image)
        #expect(ShelfFileKind(name: "отчёт.pdf") == .pdf)
        #expect(ShelfFileKind(name: "архив.tar.gz") == .archive)
        #expect(ShelfFileKind(name: "доклад.key") == .presentation)
        #expect(ShelfFileKind(name: "план.docx") == .document)
        #expect(ShelfFileKind(name: "бюджет.xlsx") == .spreadsheet)
        #expect(ShelfFileKind(name: "hosts") == .other)
    }

    @Test func badgeIsShortExtension() {
        #expect(ShelfFileKind.badge(name: "план.docx") == "DOCX")
        #expect(ShelfFileKind.badge(name: "hosts") == nil)
        #expect(ShelfFileKind.badge(name: "файл.torrent") == nil)
    }
}

@Suite struct PrompterLinesTests {
    @Test func brightnessFallsFromReadLineDown() {
        #expect(PrompterLayout.lineOpacity(row: 0) == 1)
        #expect(PrompterLayout.lineOpacity(row: 1) == 0.55)
        #expect(PrompterLayout.lineOpacity(row: 2) == 0.25)
        #expect(PrompterLayout.lineOpacity(row: 9) >= 0.1)
    }
}

@Suite struct PrompterScrollTests {
    @Test func lineHoldsThenGivesWay() {
        let lines = [
            PrompterScript.Line(words: 0..<4, text: "a b c d"),
            PrompterScript.Line(words: 4..<8, text: "e f g h"),
        ]
        #expect(PrompterScript.scroll(position: 0, in: lines) == 0)
        // Половину строки она стоит на месте: это видно сразу.
        #expect(PrompterScript.scroll(position: 2, in: lines) == 0)
        #expect(PrompterScript.scroll(position: 6, in: lines) == 1)
        let gliding = PrompterScript.scroll(position: 3.5, in: lines)
        #expect(gliding > 0.5 && gliding < 1)
        #expect(PrompterScript.scroll(position: 8, in: lines) == 2)
        #expect(PrompterScript.scroll(position: 3, in: []) == 0)
    }
}

@Suite struct PrompterSeekTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let lines = [
        PrompterScript.Line(words: 0..<3, text: "раз два три"),
        PrompterScript.Line(words: 3..<6, text: "четыре пять шесть"),
    ]

    private func running() -> PrompterModule {
        var module = PrompterModule()
        _ = module.start(text: "раз два три четыре пять шесть", now: start)
        return module
    }

    @Test func seekMovesBothWays() {
        var module = running()
        module.seek(toFraction: 0.5, now: start)
        #expect(module.position == 3)
        module.seek(toFraction: 2, now: start)
        #expect(module.position == 6)
        module.seek(toFraction: 0, now: start)
        #expect(module.position == 0)
    }

    @Test func jumpGoesToLineStartAndStopsAtEdges() {
        var module = running()
        module.jump(lines: 1, in: lines, now: start)
        #expect(module.position == 3)
        module.jump(lines: 5, in: lines, now: start)
        #expect(module.position == 3)
        module.jump(lines: -5, in: lines, now: start)
        #expect(module.position == 0)
    }

    @Test func seekBackFromEndCancelsClosing() {
        var module = running()
        module.seek(toFraction: 1, now: start)
        _ = module.advance(now: start)
        module.seek(toFraction: 0, now: start)
        let closed = module.advance(now: start.addingTimeInterval(10 * 60 / 130))
        #expect(!closed)
        #expect(module.isActive)
    }

    @Test func seekDoesNothingWhenIdle() {
        var module = PrompterModule()
        module.seek(toFraction: 1, now: start)
        #expect(module.position == 0)
    }
}

@Suite struct TranslatePageTests {
    @Test func typedTextIsTranslatedAndEmptyClears() {
        var module = TranslateModule()
        #expect(module.type("  привет ") == "привет")
        #expect(module.state == .working(source: "привет"))
        #expect(!module.replaceable)
        #expect(module.type("   ") == nil)
        #expect(module.state == .idle)
    }

    @Test func flipTurnsDirectionUntilNewSelection() {
        var module = TranslateModule()
        #expect(module.direction(of: "привет") == .ruToEn)
        module.flip()
        #expect(module.direction(of: "привет") == .enToRu)
        _ = module.press(selection: "привет", clipboard: nil, now: Date())
        #expect(module.direction(of: "привет") == .ruToEn)
    }
}

@Suite struct DictationNoticeTests {
    @Test func insertedIsShorterThanClipboardNotice() {
        var module = DictationModule()
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = module.press(now: start, modelReady: true)
        _ = module.release(now: start.addingTimeInterval(1))
        module.finish(now: start, notice: .inserted)
        #expect(module.capsule(now: start).text == "Вставлено")
        #expect(module.priority(now: start.addingTimeInterval(2)) == nil)
    }
}

@Suite struct CapsuleWindowTests {
    @Test func chosenWindowIsShownInsteadOfTightest() {
        var module = LimitsModule()
        let now = Date()
        _ = module.book.ingest(LimitSnapshot(service: .claude, windows: [
            LimitWindow(kind: .fiveHour, usedPercent: 20, resetsAt: now.addingTimeInterval(3600)),
            LimitWindow(kind: .week, usedPercent: 70, resetsAt: now.addingTimeInterval(86_400)),
        ], at: now), now: now)
        #expect(module.capsule(now: now).rings.first?.figure == "20%")
    }
}

@Suite struct ConsoleSoundTests {
    @Test func silentWhileReadingOnCallAndAtNight() {
        for sound in ConsoleSound.allCases {
            #expect(ConsoleSound.allowed(sound, enabled: true, prompter: false, call: false, quietHours: false))
            #expect(!ConsoleSound.allowed(sound, enabled: false, prompter: false, call: false, quietHours: false))
            #expect(!ConsoleSound.allowed(sound, enabled: true, prompter: true, call: false, quietHours: false))
            #expect(!ConsoleSound.allowed(sound, enabled: true, prompter: false, call: true, quietHours: false))
            #expect(!ConsoleSound.allowed(sound, enabled: true, prompter: false, call: false, quietHours: true))
        }
    }

    @Test func dictationSoundsAreMarked() {
        #expect(ConsoleSound.recordStart.isDictation)
        #expect(ConsoleSound.inserted.isDictation)
        #expect(!ConsoleSound.limitCritical.isDictation)
    }

    @Test func wavIsValidAndShort() {
        for sound in ConsoleSound.allCases {
            let wav = sound.wav
            #expect(wav.prefix(4) == Data("RIFF".utf8))
            #expect(wav.count > 44)
            #expect(wav.count < 44 + 44_100)
        }
    }
}

@Suite struct TwoFingerTapTests {
    private func two(_ time: Double, x: Double = 50, y: Double = 40, size: Double = 8) -> TouchFrame {
        TouchFrame(time: time, contacts: [
            TouchContact(id: 1, x: x - 10, y: y, size: size), TouchContact(id: 2, x: x + 10, y: y, size: size),
        ])
    }

    private func tap(_ gesture: inout TwoFingerTap, at time: Double, x: Double = 50) -> Bool {
        _ = gesture.observe(two(time, x: x))
        _ = gesture.observe(two(time + 0.05, x: x))
        return gesture.observe(TouchFrame(time: time + 0.1, contacts: []))
    }

    @Test func twoQuickTapsCount() {
        var gesture = TwoFingerTap()
        let result1 = tap(&gesture, at: 0)
        #expect(!result1)
        let result2 = tap(&gesture, at: 0.3)
        #expect(result2)
    }

    @Test func slowSecondTapDoesNot() {
        var gesture = TwoFingerTap()
        _ = tap(&gesture, at: 0)
        let result3 = tap(&gesture, at: 1)
        #expect(!result3)
    }

    @Test func oneFingerDoesNotCount() {
        var gesture = TwoFingerTap()
        for time in [0.0, 0.3] {
            _ = gesture.observe(TouchFrame(time: time, contacts: [TouchContact(id: 1, x: 50, y: 40, size: 8)]))
            let result4 = gesture.observe(TouchFrame(time: time + 0.1, contacts: []))
            #expect(!result4)
        }
    }

    @Test func scrollIsNotATap() {
        var gesture = TwoFingerTap()
        _ = gesture.observe(two(0))
        _ = gesture.observe(two(0.05, y: 50))
        let result5 = gesture.observe(TouchFrame(time: 0.1, contacts: []))
        #expect(!result5)
        let result6 = tap(&gesture, at: 0.3)
        #expect(!result6)
    }

    @Test func threeFingersAndPalmSpoil() {
        var gesture = TwoFingerTap()
        _ = gesture.observe(TouchFrame(time: 0, contacts: [
            TouchContact(id: 1, x: 10, y: 10, size: 8), TouchContact(id: 2, x: 30, y: 10, size: 8), TouchContact(id: 3, x: 50, y: 10, size: 8),
        ]))
        let result7 = gesture.observe(TouchFrame(time: 0.1, contacts: []))
        #expect(!result7)
        _ = gesture.observe(two(0.2, size: 40))
        let result8 = gesture.observe(TouchFrame(time: 0.3, contacts: []))
        #expect(!result8)
    }

    @Test func pressIsAClick() {
        var gesture = TwoFingerTap()
        _ = tap(&gesture, at: 0)
        _ = gesture.observe(two(0.3))
        gesture.press()
        let result9 = gesture.observe(TouchFrame(time: 0.4, contacts: []))
        #expect(!result9)
    }

    @Test func holdIsNotATap() {
        var gesture = TwoFingerTap()
        _ = gesture.observe(two(0))
        let result10 = gesture.observe(TouchFrame(time: 1, contacts: []))
        #expect(!result10)
    }

    @Test func farApartTapsDoNotPair() {
        var gesture = TwoFingerTap()
        _ = tap(&gesture, at: 0, x: 20)
        let result11 = tap(&gesture, at: 0.3, x: 90)
        #expect(!result11)
    }
}

@Suite struct ConsoleSoundFileTests {
    @Test func systemPlayerAcceptsEveryTone() {
        for sound in ConsoleSound.allCases {
            #expect(NSSound(data: sound.wav) != nil)
        }
    }
}

@Suite struct TranslateSelectionTests {
    @Test func textOnPageIsTranslatedButNotReplaceable() {
        var module = TranslateModule()
        let text = module.press(selection: "заголовок", clipboard: nil, now: Date(), editable: false)
        #expect(text == "заголовок")
        #expect(!module.replaceable)
    }
}
