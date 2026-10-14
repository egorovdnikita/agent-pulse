import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct DesignNewsTests {
    let rss = Data("""
        <?xml version="1.0"?><rss version="2.0"><channel><title>Smashing</title>
        <item><title><![CDATA[Designing Better Error Messages]]></title><link>https://example.com/errors</link>
        <pubDate>Tue, 13 Oct 2026 10:00:00 +0000</pubDate></item>
        <item><title>Old news</title><link>https://example.com/old</link><pubDate>Mon, 01 Jun 2026 10:00:00 +0000</pubDate></item>
        </channel></rss>
        """.utf8)

    let atom = Data("""
        <?xml version="1.0" encoding="utf-8"?><feed xmlns="http://www.w3.org/2005/Atom"><title>Figma</title>
        <entry><title>Introducing Something New in Dev Mode for Teams That Ship Every Single Day</title>
        <link rel="alternate" href="https://example.com/figma-new"/><updated>2026-10-14T08:30:00Z</updated></entry>
        </feed>
        """.utf8)

    let now = ISO8601DateFormatter().date(from: "2026-10-15T09:00:00Z")!

    @Test func parsesRSSAndAtom() throws {
        let rssItems = FeedParser.parse(rss, source: "Smashing")
        #expect(rssItems.count == 2)
        #expect(rssItems[0].title == "Designing Better Error Messages")
        #expect(rssItems[0].link == "https://example.com/errors")
        #expect(rssItems[0].date != nil)

        let atomItems = FeedParser.parse(atom, source: "Figma")
        #expect(atomItems.count == 1)
        #expect(atomItems[0].link == "https://example.com/figma-new")
        #expect(atomItems[0].date == ISO8601DateFormatter().date(from: "2026-10-14T08:30:00Z"))
    }

    @Test func teaserFitsTenWords() {
        let item = FeedParser.parse(atom, source: "Figma")[0]
        #expect(Phrases.wordCount(item.teaser) <= Phrases.maxWords)
        #expect(item.teaser.hasPrefix("Figma: Introducing"))
        #expect(item.teaser.hasSuffix("…"))
        let short = NewsItem(title: "Error messages", link: "https://x", source: "NN/g", date: nil)
        #expect(short.teaser == "NN/g: Error messages")
    }

    @Test func deskShowsFreshUnseenAndAlternatesSources() {
        var desk = NewsDesk()
        desk.update(FeedParser.parse(rss, source: "Smashing") + FeedParser.parse(atom, source: "Figma"))
        // Старое (июнь) не показываем.
        #expect(desk.available(now: now).map(\.source) == ["Figma", "Smashing"])
        // Последней была Figma — следующая из другого источника.
        #expect(desk.take(now: now, lastSource: "Figma")?.source == "Smashing")
        #expect(desk.take(now: now)?.source == "Figma")
        #expect(desk.take(now: now) == nil)
    }

    @Test func directorTellsNewsOnlyWhenNothingInterferes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        var rng = ZeroRNG()

        var d = Director(calendar: calendar)
        _ = d.handle(Signal(.presence, .userBack), now: noon, rng: &rng)
        // Новостей нет — молчит.
        #expect(d.handle(Signal(.clock, .minute), now: noon.addingTimeInterval(60), rng: &rng)?.special != .news)
        _ = d.handle(Signal(.news, .newsFresh, value: 4), now: noon.addingTimeInterval(61), rng: &rng)
        #expect(d.handle(Signal(.clock, .minute), now: noon.addingTimeInterval(120), rng: &rng)?.special == .news)
        // Не чаще раза в 2 часа.
        #expect(d.handle(Signal(.clock, .minute), now: noon.addingTimeInterval(3600), rng: &rng)?.special != .news)

        var busy = Director(calendar: calendar)
        busy.agentBusy = true
        _ = busy.handle(Signal(.presence, .userBack), now: noon, rng: &rng)
        _ = busy.handle(Signal(.news, .newsFresh, value: 4), now: noon, rng: &rng)
        #expect(busy.handle(Signal(.clock, .minute), now: noon.addingTimeInterval(120), rng: &rng)?.special != .news)

        var quiet = Director(calendar: calendar)
        _ = quiet.handle(Signal(.presence, .userBack), now: noon, rng: &rng)
        _ = quiet.handle(Signal(.quiet, .quietOn), now: noon, rng: &rng)
        _ = quiet.handle(Signal(.news, .newsFresh, value: 4), now: noon, rng: &rng)
        #expect(quiet.handle(Signal(.clock, .minute), now: noon.addingTimeInterval(120), rng: &rng)?.special != .news)
    }
}
