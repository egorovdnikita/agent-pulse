import Foundation
import Testing
@testable import AgentPulseCore

/// Детерминированный генератор для тестов.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Suite struct PalWardrobeTests {
    let all: Set<String> = [
        "Arch", "Briefcase", "Cat", "Circle", "Cloud", "Clover", "Drop", "Flame", "Flower",
        "Ghost", "Heart", "Hexagon", "Oval", "Pill", "Scallop", "Square", "Star", "Triangle",
    ]
    var rng = SeededRandom(state: 42)

    mutating func wear(_ wardrobe: inout PalWardrobe, _ state: MascotState, mode: PalWardrobe.Mode = .shuffle, at t: Double) -> String? {
        wardrobe.update(mode: mode, installed: all, state: state, at: t, using: &rng)
    }

    @Test func modeParsing() {
        #expect(PalWardrobe.Mode(config: "default") == .classic)
        #expect(PalWardrobe.Mode(config: "agent-pals/shuffle") == .shuffle)
        #expect(PalWardrobe.Mode(config: "agent-pals/daily") == .shuffle)
        #expect(PalWardrobe.Mode(config: "agent-pals/Cat") == .fixed("Cat"))
    }

    @Test mutating func newTaskBringsNewBot() {
        var wardrobe = PalWardrobe()
        let first = wear(&wardrobe, .idle, at: 0)
        #expect(wear(&wardrobe, .think, at: 200) != first)
    }

    @Test mutating func botStaysDuringWork() {
        var wardrobe = PalWardrobe()
        _ = wear(&wardrobe, .idle, at: 0)
        let working = wear(&wardrobe, .think, at: 200)
        #expect(wear(&wardrobe, .work(.read), at: 500) == working)
        #expect(wear(&wardrobe, .work(.edit), at: 900) == working)
        #expect(wear(&wardrobe, .idle, at: 1000) == working)
    }

    @Test mutating func notMoreOftenThanMinGap() {
        var wardrobe = PalWardrobe()
        let first = wear(&wardrobe, .idle, at: 0)
        #expect(wear(&wardrobe, .think, at: 60) == first)
        _ = wear(&wardrobe, .idle, at: 90)
        #expect(wear(&wardrobe, .think, at: 181) != first)
    }

    @Test mutating func waitingNeverChangesBot() {
        var wardrobe = PalWardrobe()
        let first = wear(&wardrobe, .sleep, at: 0)
        #expect(wear(&wardrobe, .waitYou(.permission), at: 500) == first)
    }

    @Test mutating func wakingBringsNewBot() {
        var wardrobe = PalWardrobe()
        let first = wear(&wardrobe, .sleep, at: 0)
        #expect(wear(&wardrobe, .idle, at: 400) != first)
    }

    @Test mutating func allBotsShowBeforeRepeat() {
        var wardrobe = PalWardrobe()
        var seen: [String] = [wear(&wardrobe, .idle, at: 0)].compactMap { $0 }
        var t = 0.0
        for _ in 1..<all.count {
            t += 200
            _ = wear(&wardrobe, .idle, at: t)
            t += 200
            if let bot = wear(&wardrobe, .think, at: t) { seen.append(bot) }
        }
        #expect(Set(seen).count == all.count)
        for index in 1..<seen.count { #expect(seen[index] != seen[index - 1]) }
    }

    @Test mutating func fixedAndClassic() {
        var wardrobe = PalWardrobe()
        #expect(wear(&wardrobe, .think, mode: .fixed("Cat"), at: 0) == "Cat")
        #expect(wear(&wardrobe, .think, mode: .classic, at: 1) == nil)
    }
}
