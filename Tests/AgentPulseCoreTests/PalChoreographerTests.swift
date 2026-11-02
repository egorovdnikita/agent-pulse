import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct PalChoreographerTests {
    func started(_ state: MascotState, target: WorkTarget? = nil, at t: Double = 0) -> PalChoreographer {
        var choreo = PalChoreographer()
        choreo.setState(state, target: target, at: t)
        return choreo
    }

    @Test func statesMapToClips() {
        #expect(PalChoreographer.clip(for: .sleep, target: nil) == .sleeping)
        #expect(PalChoreographer.clip(for: .idle, target: nil) == .idle)
        #expect(PalChoreographer.clip(for: .think, target: nil) == .thinking)
        #expect(PalChoreographer.clip(for: .waitYou(.permission), target: nil) == .listening)
        #expect(PalChoreographer.clip(for: .work(.read), target: .code) == .reading)
        #expect(PalChoreographer.clip(for: .work(.edit), target: .code) == .coding)
        #expect(PalChoreographer.clip(for: .work(.edit), target: .figma) == .designing)
        #expect(PalChoreographer.clip(for: .work(.run), target: .code) == .typing)
        #expect(PalChoreographer.clip(for: .work(.search), target: .code) == .searching)
        #expect(PalChoreographer.clip(for: .work(.general), target: nil) == .working)
    }

    @Test func clipHoldsOneLoopBeforeSwitching() {
        var choreo = started(.think)
        choreo.setState(.work(.read), target: .code, at: 1)
        #expect(choreo.clip == .thinking)
        let switched2_3 = choreo.tick(at: 2.3)
        #expect(!switched2_3)
        let switched2_4 = choreo.tick(at: 2.4)
        #expect(switched2_4)
        #expect(choreo.clip == .reading)
    }

    @Test func workClipsDoNotFlickerPerTool() {
        var choreo = started(.work(.read), target: .code)
        // Прочитал → поправил → запустил за пару секунд: маскот остаётся «читает» две петли.
        choreo.setState(.work(.edit), target: .code, at: 0.5)
        choreo.setState(.work(.run), target: .code, at: 1.5)
        let switched4_7 = choreo.tick(at: 4.7)
        #expect(!switched4_7)
        #expect(choreo.clip == .reading)
        let switched4_8 = choreo.tick(at: 4.8)
        #expect(switched4_8)
        // Применяется последнее желание, промежуточные шаги пропускаются.
        #expect(choreo.clip == .typing)
    }

    @Test func waitingInterruptsImmediately() {
        var choreo = started(.work(.edit), target: .code)
        choreo.react(.done, at: 0.1)
        choreo.setState(.waitYou(.input), target: nil, at: 0.2)
        #expect(choreo.clip == .listening)
        #expect(choreo.nextDeadline == nil)
    }

    @Test func outcomeIsOneShotThenReturns() {
        var choreo = started(.work(.edit), target: .code)
        choreo.react(.done, at: 1)
        #expect(choreo.clip == .done)
        choreo.setState(.idle, target: nil, at: 1.2)
        let switched5_7 = choreo.tick(at: 5.7)
        #expect(!switched5_7)
        #expect(choreo.clip == .done)
        let switched5_8 = choreo.tick(at: 5.8)
        #expect(switched5_8)
        #expect(choreo.clip == .idle)
    }

    @Test func outcomeDoesNotBreakWaiting() {
        var choreo = started(.waitYou(.permission))
        choreo.react(.error, at: 1)
        #expect(choreo.clip == .listening)
    }

    @Test func leavingWaitIsImmediate() {
        var choreo = started(.waitYou(.permission))
        choreo.setState(.work(.run), target: .code, at: 0.5)
        #expect(choreo.clip == .typing)
    }

    @Test func wakingAndFallingAsleepAreImmediate() {
        var choreo = started(.sleep)
        choreo.setState(.sleep, target: nil, awake: true, at: 0.3)
        #expect(choreo.clip == .idle)
        choreo.setState(.sleep, target: nil, at: 0.6)
        #expect(choreo.clip == .sleeping)
        choreo.setState(.think, target: nil, at: 0.9)
        #expect(choreo.clip == .thinking)
    }

    @Test func otherReactionsKeepClip() {
        var choreo = started(.idle)
        choreo.react(.purr, at: 1)
        #expect(choreo.clip == .idle)
    }

    @Test func skinConfigParsing() {
        #expect(PalSkin(config: "agent-pals/Cat")?.bot == "Cat")
        #expect(PalSkin(config: "default") == nil)
        #expect(PalSkin(config: "agent-pals/../x") == nil)
        #expect(PalSkin(bot: "Heart").configValue == "agent-pals/Heart")
    }

    @Test func installedNeedsAllClips() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "pals-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for clip in PalClip.allCases {
            let url = PalSkin(bot: "Full").url(clip, in: root)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url)
        }
        let partial = PalSkin(bot: "Half").url(.idle, in: root)
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: partial)
        #expect(PalSkin.installed(in: root).map(\.bot) == ["Full"])
    }
}
