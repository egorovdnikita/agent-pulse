import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct NewsTopicsTests {
    let now = ISO8601DateFormatter().date(from: "2026-10-17T09:00:00Z")!

    @Test func parsesTelegramChannel() {
        let html = Data("""
            <div class="tgme_widget_message_wrap js-widget_message_wrap"><div class="tgme_widget_message" data-post="uxnotes/101">
            <div class="tgme_widget_message_text js-message_text" dir="auto">🔥 Кейт Каплан написала о подсказках в интерфейсе.<br/><br/>Подсказки работают, когда появляются вовремя. <a href="https://x.y">Подробнее</a> #ux</div>
            <time datetime="2026-10-16T10:00:00+00:00" class="time">10:00</time></div></div>
            <div class="tgme_widget_message_wrap js-widget_message_wrap"><div class="tgme_widget_message" data-post="uxnotes/102">
            <div class="tgme_widget_message_text js-message_text" dir="auto">Ок</div></div></div>
            """.utf8)
        let items = TelegramParser.parse(html, source: "UX Notes", topic: .design)
        #expect(items.count == 1)
        #expect(items[0].link == "https://t.me/uxnotes/101")
        #expect(items[0].gist == "Кейт Каплан написала о подсказках в интерфейсе")
        #expect(items[0].date != nil)
    }

    @Test func headlinesAreRetoldPlainly() {
        #expect(NewsGist.make(title: "Котяков: МРОТ в России составит 28 935 рублей в 2027 году", description: "", preferTitle: true)
            == "МРОТ в России составит 28 935 рублей в 2027 году")
        #expect(NewsGist.make(title: "Госзаказ учится на предписаниях // ФАС отчиталась о закупках", description: "", preferTitle: true)
            == "Госзаказ учится на предписаниях")
        // Обрывок без контекста не годится — берётся заголовок.
        #expect(NewsGist.isWeak("Его назвали адской курицей"))
        #expect(NewsGist.isWeak("Вновь копаем в самое интересное:"))
        #expect(NewsGist.retell(title: "Как тебе такое, Илон Маск") == "Как тебе такое, Илон Маск")
        #expect(NewsGist.retell(title: "Как редизайнить продукт") == "Тут разбирают, как редизайнить продукт")
    }

    @Test func dropsGrimQuizzesAndPromo() {
        func item(_ text: String) -> NewsItem { NewsItem(title: text, link: "https://x", source: "S", date: nil, gist: text) }
        #expect(!item("При обстреле пострадали трое человек").isTellable)
        #expect(!item("Попробуйте найти три отличия между картинками").isTellable)
        #expect(item("Ночные перекусы оказались ещё вреднее, чем думали").isTellable)
    }

    @Test func designIsTheMajority() {
        var desk = NewsDesk()
        var pool: [NewsItem] = []
        for index in 0..<40 {
            for topic in NewsTopic.allCases {
                pool.append(NewsItem(title: "t", link: "https://\(topic)/\(index)", source: "\(topic)-\(index % 3)",
                                     date: now.addingTimeInterval(-Double(index) * 60), gist: "\(index)\(topic.rawValue) z\(index)\(topic.rawValue)", topic: topic))
            }
        }
        desk.update(pool)
        var counts: [NewsTopic: Int] = [:]
        var last: NewsItem?
        for step in 0..<40 {
            let roll = Double(step % 20) / 20 // ровно 65% бросков < 0.65
            // Тема среди остальных — по вкусу (здесь он ровный): `pick` обходит шкалу без повторов подряд.
            let pick = Double((step * 7) % 40) / 40
            guard let item = desk.take(now: now, lastSource: last?.source, lastTopic: last?.topic, roll: roll, pick: pick) else { break }
            counts[item.topic, default: 0] += 1
            last = item
        }
        #expect(counts[.design, default: 0] == 26)
        // Остальные темы — по очереди: каждая хотя бы раз, ни одна не перетягивает.
        let others = NewsTopic.allCases.filter { $0 != .design }
        #expect(others.allSatisfy { (1...4).contains(counts[$0, default: 0]) }, "\(counts)")
    }

    @Test func oldNewsJSONDecodesAsDesign() throws {
        let json = Data(#"{"title":"T","link":"https://x","source":"S","gist":"Суть"}"#.utf8)
        #expect(try JSONDecoder().decode(NewsItem.self, from: json).topic == .design)
    }
}

@Suite struct NewsDedupeTests {
    func item(_ gist: String, _ link: String, _ source: String = "Ведомости · Экономика") -> NewsItem {
        NewsItem(title: gist, link: link, source: source, date: nil, gist: gist, topic: .economy)
    }

    @Test func sameStoryFromTwoOutletsIsToldOnce() {
        var desk = NewsDesk()
        desk.update([
            item("МРОТ в России составит 28 935 рублей в 2027 году", "https://a"),
            item("Минимальный размер оплаты труда в России вырастет до 28 935 рублей в 2027 году", "https://b", "Коммерсантъ"),
            item("Страховые пенсии проиндексируют темпами выше инфляции", "https://c"),
        ])
        #expect(desk.items.count == 2)
        #expect(desk.items.first?.shortSource == "Ведомости")
    }

    @Test func everyTopicHasSourcesAndDesignLeads() {
        for topic in NewsTopic.allCases {
            #expect(NewsFeeds.all.contains { $0.topic == topic }, "\(topic)")
            #expect(!topic.leadIns.isEmpty)
        }
        let design = NewsFeeds.all.filter { $0.topic == .design }.count
        #expect(design > NewsFeeds.all.count / 3)
    }

    @Test func leadInsFollowVoiceRules() {
        for line in NewsVoice.allLeadIns {
            #expect(Phrases.wordCount(line) <= Phrases.maxWords, "\(line)")
        }
    }
}

@Suite struct NewsTasteTests {
    let now = ISO8601DateFormatter().date(from: "2026-10-17T09:00:00Z")!

    func desk(_ topics: [NewsTopic], sources: [String] = ["A"]) -> NewsDesk {
        var desk = NewsDesk()
        var pool: [NewsItem] = []
        for index in 0..<20 {
            for topic in topics {
                for source in sources {
                    // Суть из уникальных слов: иначе похожие новости склеятся в одну историю.
                    let word = String(format: "%05d", pool.count)
                    pool.append(NewsItem(title: "t", link: "https://\(topic)/\(source)/\(index)", source: source,
                                         date: now.addingTimeInterval(-Double(index) * 60),
                                         gist: "\(word)aa \(word)bb", topic: topic))
                }
            }
        }
        desk.update(pool)
        return desk
    }

    /// Тема, которую открываешь, звучит чаще; та, что бесит, — реже, но не пропадает.
    @Test func openedTopicsSoundMoreOften() {
        var desk = desk([.it, .science, .games])
        let sample = desk.available(now: now)
        for _ in 0..<5 { desk.record(.opened, for: sample.first { $0.topic == .science }!) }
        for _ in 0..<2 { desk.record(.disliked, for: sample.first { $0.topic == .games }!) }
        // Доли тем при `pick`, равномерно пробегающем шкалу: наука 2.5, ИТ 1, игры 0.2.
        let fresh = desk.available(now: now)
        var counts: [NewsTopic: Int] = [:]
        for step in 0..<1000 {
            guard let topic = desk.byTaste(fresh, pick: Double(step) / 1000).first?.topic else { continue }
            counts[topic, default: 0] += 1
        }
        #expect(abs(counts[.science, default: 0] - 676) <= 2, "\(counts)")
        #expect(abs(counts[.it, default: 0] - 270) <= 2, "\(counts)")
        #expect(abs(counts[.games, default: 0] - 54) <= 2, "\(counts)")
        // Через `take` тема тоже выбирается по вкусу: дизайна нет, бросок — в остальные темы.
        #expect(desk.take(now: now, roll: 0.99, pick: 0.999)?.topic != nil)
    }

    /// Надоевший источник молчит, пока есть другие; дизайн по-прежнему большая часть.
    @Test func dislikedSourceIsSkipped() {
        var desk = desk([.design], sources: ["A", "B"])
        let fromA = desk.available(now: now).first { $0.source == "A" }!
        desk.record(.disliked, for: fromA)
        desk.record(.disliked, for: fromA)
        for _ in 0..<10 {
            #expect(desk.take(now: now, roll: 0)?.source == "B")
        }
        #expect(NewsDesk.weight(-100) > 0)
    }

    /// Оценка новости во вкус, а не в глушилку: два «бесит» новости не выключают новости.
    @Test func newsFeedbackDoesNotMuteNews() {
        let entries = (0..<3).map { _ in FeedbackLog.Entry(at: now, reaction: "news.item", verdict: "бесит") }
            + (0..<2).map { _ in FeedbackLog.Entry(at: now, reaction: "news.design", verdict: "бесит") }
        #expect(FeedbackLog.muted(entries, now: now).isEmpty)
    }

    /// В выходные рабочие темы молчат, пока есть другие.
    @Test func weekendSkipsWorkTopics() {
        var desk = desk([.it, .economy, .art])
        for step in 0..<10 {
            #expect(desk.take(now: now, resting: true, roll: 0.99, pick: Double(step) / 10)?.topic == .art)
        }
        var work = self.desk([.it])
        #expect(work.take(now: now, resting: true, roll: 0.99)?.topic == .it)
    }

    /// Старый `news.json` без вкуса читается.
    @Test func oldDeskDecodes() throws {
        let data = Data(#"{"seen":["x"],"items":[]}"#.utf8)
        let desk = try JSONDecoder().decode(NewsDesk.self, from: data)
        #expect(desk.seen == ["x"])
        #expect(desk.score(topic: .it) == 0)
    }
}
