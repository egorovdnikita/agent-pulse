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

    @Test func goesToBrainAsNumber() {
        let signal = ToolSignal.limitCritical(.codex).signal(at: t0)
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
