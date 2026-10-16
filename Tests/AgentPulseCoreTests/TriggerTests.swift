import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct TriggerTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }()

    func date(_ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: h, minute: min))!
    }

    func director() -> Director {
        var settings = DirectorSettings()
        settings.talkativeness = 1
        settings.mischief = 0
        return Director(settings: settings, calendar: calendar)
    }

    @Test func newsWelcomesYouBackFromBreak() {
        var rng = ZeroRNG()
        var d = director()
        _ = d.handle(Signal(.presence, .userBack), now: date(12), rng: &rng)
        _ = d.handle(Signal(.news, .newsFresh, value: 3), now: date(12, 1), rng: &rng)
        _ = d.handle(Signal(.presence, .userAway, value: 300), now: date(12, 30), rng: &rng)
        let back = d.handle(Signal(.presence, .userBack, value: 40 * 60), now: date(13, 10), rng: &rng)
        #expect(back?.special == .news)
        #expect(back?.reaction == "news.welcome")
        // Общий кулдаун новостей: на минутном тике сразу следом — молчит.
        #expect(d.handle(Signal(.clock, .minute), now: date(13, 12), rng: &rng)?.special != .news)
    }

    @Test func morningNewsHasItsOwnLeadIn() {
        var rng = ZeroRNG()
        var d = director()
        _ = d.handle(Signal(.presence, .userBack), now: date(9, 30), rng: &rng)
        _ = d.handle(Signal(.news, .newsFresh, value: 2), now: date(9, 31), rng: &rng)
        let tick = d.handle(Signal(.clock, .minute), now: date(9, 32), rng: &rng)
        #expect(tick?.reaction == "news.morning")
        #expect(tick?.line != nil)
    }

    @Test func taskMilestones() {
        var rng = ZeroRNG()
        var d = director()
        _ = d.handle(Signal(.presence, .userBack), now: date(10), rng: &rng)
        var milestones: [String] = []
        for index in 1...12 {
            let decision = d.handle(Signal(.agents, .agentDone), now: date(10, index * 3), rng: &rng)
            if decision?.reaction == "agent.milestone", let line = decision?.line { milestones.append(line) }
        }
        #expect(milestones.count == 1)
        #expect(milestones.first?.contains("10") == true)
    }

    @Test func lunchOnlyWithoutBreaks() {
        var rng = ZeroRNG()
        var d = director()
        _ = d.handle(Signal(.presence, .userBack), now: date(9), rng: &rng)
        var reactions: [String] = []
        for minute in stride(from: 0, to: 60, by: 1) {
            if let r = d.handle(Signal(.clock, .minute), now: date(13, minute), rng: &rng)?.reaction { reactions.append(r) }
        }
        #expect(reactions.contains("lunch"))

        var rested = director()
        _ = rested.handle(Signal(.presence, .userBack), now: date(9), rng: &rng)
        _ = rested.handle(Signal(.presence, .userAway, value: 300), now: date(11), rng: &rng)
        _ = rested.handle(Signal(.presence, .userBack, value: 60), now: date(11, 2), rng: &rng)
        let quiet = (0..<30).compactMap { rested.handle(Signal(.clock, .minute), now: date(13, $0), rng: &rng)?.reaction }
        #expect(!quiet.contains("lunch"))
    }
}
