import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct LastTaskTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func replay(_ payloads: [Data]) throws -> LastTask? {
        var table = SessionTable()
        var task: LastTask?
        for (index, payload) in payloads.enumerated() {
            let event = try #require(ClaudeCodeHooks.parse(payload, now: t0.addingTimeInterval(Double(index))))
            table.apply(event)
            task = LastTask.updated(task, event: event, session: table.sessions[event.sessionId])
        }
        return task
    }

    @Test func figmaTaskSurvivesSessionEnd() throws {
        let task = try #require(try replay([
            Fixtures.promptSubmitted, Fixtures.preToolFigmaWrite, Fixtures.postToolOk, Fixtures.stop, Fixtures.sessionEnd,
        ]))
        #expect(task.usedFigma)
        #expect(task.status == .done)
        #expect(task.summary(now: t0.addingTimeInterval(3 + 5 * 60)) == "Figma · agent-pulse\nГотово · 5 мин назад")
    }

    @Test func claudeTaskInProgress() throws {
        let task = try #require(try replay([Fixtures.promptSubmitted, Fixtures.preToolBashTests]))
        #expect(task.summary(now: t0) == "Claude · agent-pulse\nЗапускает тесты")
    }

    @Test func newPromptResetsFigmaFlag() throws {
        let task = try #require(try replay([Fixtures.preToolFigmaWrite, Fixtures.promptSubmitted, Fixtures.preToolRead]))
        #expect(!task.usedFigma)
    }

    @Test func agoFormatting() {
        #expect(LastTask.ago(10) == "только что")
        #expect(LastTask.ago(125) == "2 мин назад")
        #expect(LastTask.ago(7200) == "2 ч назад")
        #expect(LastTask.ago(200_000) == "давно")
    }
}
