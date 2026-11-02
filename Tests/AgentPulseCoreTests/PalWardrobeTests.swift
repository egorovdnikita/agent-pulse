import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct PalWardrobeTests {
    let all = Set(PalWardrobe.homePool + PalWardrobe.costumes.map(\.bot))

    func wear(
        _ wardrobe: inout PalWardrobe, _ state: MascotState, source: AgentEvent.Source? = nil, agent: String? = nil,
        mode: PalWardrobe.Mode = .daily, day: Int = 100, present: Bool = true, at t: Double
    ) -> String? {
        wardrobe.update(
            mode: mode, costumes: true, installed: all, state: state, source: source, agent: agent,
            day: day, present: present, at: t
        )
    }

    @Test func dailyBotCyclesWithoutRepeats() {
        let week = (0..<9).compactMap { PalWardrobe.dailyBot(day: $0, installed: all) }
        #expect(Set(week).count == 9)
        for day in 0..<30 {
            #expect(PalWardrobe.dailyBot(day: day, installed: all) != PalWardrobe.dailyBot(day: day + 1, installed: all))
        }
        #expect(Set(week).isDisjoint(with: PalWardrobe.costumes.map(\.bot)))
    }

    @Test func modeParsing() {
        #expect(PalWardrobe.Mode(config: "default") == .classic)
        #expect(PalWardrobe.Mode(config: "agent-pals/daily") == .daily)
        #expect(PalWardrobe.Mode(config: "agent-pals/Cat") == .fixed("Cat"))
    }

    @Test func agentArrivesImmediatelyAndLeavesAfterAMinute() {
        var wardrobe = PalWardrobe()
        let home = wear(&wardrobe, .idle, at: 0)
        #expect(wear(&wardrobe, .think, source: .claudeCode, at: 10) == "Clover")
        #expect(wardrobe.inCostume)
        // Закончил: гость ещё доигрывает итог.
        #expect(wear(&wardrobe, .idle, at: 20) == "Clover")
        #expect(wear(&wardrobe, .idle, at: 79) == "Clover")
        #expect(wear(&wardrobe, .idle, at: 80) == home)
        #expect(!wardrobe.inCostume)
    }

    @Test func fallingAsleepReturnsHome() {
        var wardrobe = PalWardrobe()
        let home = wear(&wardrobe, .idle, at: 0)
        _ = wear(&wardrobe, .work(.edit), source: .cowork, at: 5)
        #expect(wear(&wardrobe, .sleep, at: 30) == home)
    }

    @Test func orcaAgentsGetTheirOwnBots() {
        #expect(PalWardrobe.costume(source: .orca, agent: "Codex") == "Hexagon")
        #expect(PalWardrobe.costume(source: .orca, agent: "Claude Code") == "Clover")
        #expect(PalWardrobe.costume(source: .orca, agent: "Grok") == "Oval")
        #expect(PalWardrobe.costume(source: .figmaMCP, agent: nil) == "Triangle")
    }

    @Test func twoAgentsDoNotFlicker() {
        var wardrobe = PalWardrobe()
        _ = wear(&wardrobe, .work(.read), source: .claudeCode, at: 0)
        #expect(wear(&wardrobe, .work(.run), source: .orca, agent: "Codex", at: 5) == "Clover")
        #expect(wear(&wardrobe, .work(.run), source: .orca, agent: "Codex", at: 20) == "Hexagon")
    }

    @Test func waitingSwitchesToWhoeverWaitsImmediately() {
        var wardrobe = PalWardrobe()
        _ = wear(&wardrobe, .work(.read), source: .claudeCode, at: 0)
        #expect(wear(&wardrobe, .waitYou(.permission), source: .orca, agent: "Codex", at: 1) == "Hexagon")
    }

    @Test func newDayChangesHomeOnlyWhenYouAreHere() {
        var wardrobe = PalWardrobe()
        let yesterday = wear(&wardrobe, .sleep, day: 100, at: 0)
        #expect(wear(&wardrobe, .sleep, day: 101, present: false, at: 10) == yesterday)
        let today = wear(&wardrobe, .idle, day: 101, present: true, at: 20)
        #expect(today != yesterday)
        #expect(today == PalWardrobe.dailyBot(day: 101, installed: all))
    }

    @Test func fixedBotStillHostsGuests() {
        var wardrobe = PalWardrobe()
        #expect(wear(&wardrobe, .idle, mode: .fixed("Cat"), at: 0) == "Cat")
        #expect(wear(&wardrobe, .work(.edit), source: .figmaCompanion, mode: .fixed("Cat"), at: 5) == "Triangle")
    }

    @Test func classicHasNoBot() {
        var wardrobe = PalWardrobe()
        #expect(wear(&wardrobe, .work(.edit), source: .claudeCode, mode: .classic, at: 0) == nil)
    }
}
