import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct FeedbackTests {
    let now = Date()

    func entry(_ reaction: String, _ verdict: String, daysAgo: Double) -> FeedbackLog.Entry {
        FeedbackLog.Entry(at: now.addingTimeInterval(-daysAgo * 86_400), reaction: reaction, verdict: verdict)
    }

    @Test func twoAnnoyancesInAWeekMute() {
        let entries = [
            entry("fun.hiccup", "бесит", daysAgo: 1), entry("fun.hiccup", "бесит", daysAgo: 3),
            entry("capsLock", "бесит", daysAgo: 1), entry("capsLock", "бесит", daysAgo: 9),
            entry("stroke", "мило", daysAgo: 1), entry("stroke", "мило", daysAgo: 2),
            entry("agent.waitLong", "бесит", daysAgo: 1), entry("agent.waitLong", "бесит", daysAgo: 1),
        ]
        // Старое «бесит» не считается, «мило» не глушит, агентные — никогда.
        #expect(FeedbackLog.muted(entries, now: now) == ["fun.hiccup"])
    }

    @Test func parsesJSONLAndSkipsBrokenLines() {
        let iso = ISO8601DateFormatter().string(from: now)
        let data = Data("""
            {"ts":"\(iso)","reaction":"poke","verdict":"бесит","line":"Ай"}
            not json
            {"ts":"\(iso)","reaction":"poke","verdict":"бесит"}
            """.utf8)
        let entries = FeedbackLog.parse(data)
        #expect(entries.count == 2)
        #expect(FeedbackLog.muted(entries, now: now.addingTimeInterval(1)) == ["poke"])
    }

    @Test func mutedReactionSpeaksOnlyWithEyes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        var settings = DirectorSettings()
        settings.talkativeness = 1
        var d = Director(settings: settings, calendar: calendar)
        d.mutedReactions = ["capsLock"]
        var rng = ZeroRNG()
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        let decision = d.handle(Signal(.keyboard, .capsLockOn), now: noon, rng: &rng)
        #expect(decision?.reaction == "capsLock")
        #expect(decision?.behavior != nil)
        #expect(decision?.line == nil)
    }

    @Test func weekendAndSeasonGreetings() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        var rng = ZeroRNG()
        var saturday = Director(calendar: calendar)
        let sat = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 11))!
        #expect(saturday.handle(Signal(.presence, .userBack), now: sat, rng: &rng)?.reaction == "greeting.weekend")
        var autumn = Director(calendar: calendar)
        let sep1 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 10))!
        #expect(autumn.handle(Signal(.presence, .userBack), now: sep1, rng: &rng)?.reaction == "greeting.season")
    }
}
