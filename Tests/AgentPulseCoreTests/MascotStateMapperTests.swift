import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct MascotStateMapperTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func session(_ id: String, _ phase: Phase, ago: TimeInterval = 0) -> SessionInfo {
        SessionInfo(id: id, source: .claudeCode, phase: phase, at: now.addingTimeInterval(-ago))
    }

    func state(_ sessions: [SessionInfo]) -> MascotState {
        MascotStateMapper.state(for: sessions, now: now, sleepAfter: 60)
    }

    @Test func noSessionsSleeps() {
        #expect(state([]) == .sleep)
    }

    @Test func waitingBeatsEverything() {
        let edit = Activity(tool: "Edit", kind: .edit, target: .code, text: "Правит")
        let sessions = [
            session("a", .working(edit)),
            session("b", .awaitingUser(reason: .permission, message: ""), ago: 30),
            session("c", .done(summary: "Готово")),
        ]
        #expect(state(sessions) == .waitYou(.permission))
        #expect(MascotStateMapper.dominant(sessions)?.id == "b")
    }

    @Test func priorityOrder() {
        let phases: [Phase] = [
            .idle, .thinking, .working(Activity(tool: "Read", kind: .read, target: .code, text: "")),
            .done(summary: ""), .failed(""), .awaitingUser(reason: .input, message: ""),
        ]
        let ranks = phases.map(MascotStateMapper.rank)
        #expect(ranks == ranks.sorted())
        #expect(Set(ranks).count == ranks.count)
    }

    @Test func workModes() {
        #expect(state([session("a", .working(Activity(tool: "Read", kind: .read, target: .code, text: "")))]) == .work(.read))
        #expect(state([session("a", .working(Activity(tool: "X", kind: .other, target: .code, text: "")))]) == .work(.general))
        #expect(state([session("a", .received)]) == .think)
    }

    @Test func idleFallsAsleepAfterPause() {
        #expect(state([session("a", .idle, ago: 10)]) == .idle)
        #expect(state([session("a", .idle, ago: 61)]) == .sleep)
        #expect(state([session("a", .done(summary: ""), ago: 2)]) == .idle)
    }

    @Test func reactionsAndTriggers() {
        func reaction(_ kind: AgentEvent.Kind) -> MascotReaction? {
            MascotStateMapper.reaction(for: AgentEvent(source: .claudeCode, sessionId: "a", kind: kind))
        }
        #expect(reaction(.promptSubmitted) == .notice)
        #expect(reaction(.subtaskDone) == .step)
        #expect(reaction(.stopped) == .done)
        #expect(reaction(.error) == .error)
        #expect(reaction(.toolStarted) == nil)

        #expect(MascotStateMapper.ambientTrigger(for: .work(.edit), target: .figma) == .workEditFigma)
        #expect(MascotStateMapper.ambientTrigger(for: .work(.edit), target: .code) == .workEditCode)
        #expect(MascotStateMapper.ambientTrigger(for: .idle, target: nil) == nil)
    }
}
