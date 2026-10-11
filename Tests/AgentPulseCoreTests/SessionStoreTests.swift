import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct SessionStoreTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func event(_ data: Data, at offset: TimeInterval) throws -> AgentEvent {
        try #require(ClaudeCodeHooks.parse(data, now: t0.addingTimeInterval(offset)))
    }

    func phase(_ table: SessionTable) -> Phase? {
        table.sessions[Fixtures.sessionId]?.phase
    }

    @Test func typicalTaskLifecycle() throws {
        var table = SessionTable()
        table.apply(try event(Fixtures.promptSubmitted, at: 0))
        #expect(phase(table) == .received)

        // «Думает» не приходит событием — выводится из паузы.
        table.tick(now: t0.addingTimeInterval(0.5))
        #expect(phase(table) == .received)
        table.tick(now: t0.addingTimeInterval(1))
        #expect(phase(table) == .thinking)

        table.apply(try event(Fixtures.preToolBashTests, at: 2))
        guard case .working(let activity) = phase(table) else { Issue.record("ожидали working"); return }
        #expect(activity.kind == .run)
        #expect(activity.text == "Запускает тесты")

        table.apply(try event(Fixtures.notificationPermission, at: 3))
        #expect(phase(table) == .awaitingUser(reason: .permission, message: "Claude needs your permission to use Bash"))

        table.apply(try event(Fixtures.postToolOk, at: 10))
        #expect(phase(table) == .thinking)

        table.apply(try event(Fixtures.stop, at: 12))
        #expect(phase(table) == .done(summary: "Готово"))
        table.tick(now: t0.addingTimeInterval(19))
        #expect(phase(table) == .idle)

        table.apply(try event(Fixtures.sessionEnd, at: 20))
        #expect(table.sessions.isEmpty)
    }

    @Test func toolErrorIsNotFailure() throws {
        var table = SessionTable()
        table.apply(try event(Fixtures.preToolRead, at: 0))
        table.apply(try event(Fixtures.postToolError, at: 1))
        #expect(phase(table) == .thinking)
    }

    @Test func readStreakBecomesStudyingProject() throws {
        var table = SessionTable()
        table.apply(try event(Fixtures.promptSubmitted, at: 0))
        for index in 1...3 {
            table.apply(try event(Fixtures.preToolRead, at: Double(index)))
        }
        guard case .working(let activity) = phase(table) else { Issue.record("ожидали working"); return }
        #expect(activity.text == "Изучает проект")
        #expect(table.sessions[Fixtures.sessionId]?.timeline == ["Читает Package.swift", "Изучает проект"])
    }

    @Test func hostAndContextAreRemembered() throws {
        var table = SessionTable()
        table.apply(try event(Fixtures.enveloped(Fixtures.promptSubmitted, bundle: "com.mitchellh.ghostty"), at: 0))
        table.apply(try event(Fixtures.preToolRead, at: 1))
        #expect(table.sessions[Fixtures.sessionId]?.hostBundleId == "com.mitchellh.ghostty")
        #expect(table.sessions[Fixtures.sessionId]?.context == "agent-pulse")
    }

    @Test func actorWrapsTable() async throws {
        let store = SessionStore()
        let sessions = await store.apply(try event(Fixtures.promptSubmitted, at: 0))
        #expect(sessions.count == 1)
    }
}
