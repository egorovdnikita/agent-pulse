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
                                     date: now.addingTimeInterval(-Double(index) * 60), gist: "суть новости из ленты", topic: topic))
            }
        }
        desk.update(pool)
        var counts: [NewsTopic: Int] = [:]
        var last: NewsItem?
        for step in 0..<40 {
            let roll = Double(step % 20) / 20 // ровно 65% бросков < 0.65
            guard let item = desk.take(now: now, lastSource: last?.source, lastTopic: last?.topic, roll: roll) else { break }
            counts[item.topic, default: 0] += 1
            last = item
        }
        #expect(counts[.design, default: 0] == 26)
        // Остальные темы — по очереди, не две подряд одну.
        #expect([NewsTopic.it, .economy, .science].allSatisfy { counts[$0, default: 0] >= 4 })
    }

    @Test func oldNewsJSONDecodesAsDesign() throws {
        let json = Data(#"{"title":"T","link":"https://x","source":"S","gist":"Суть"}"#.utf8)
        #expect(try JSONDecoder().decode(NewsItem.self, from: json).topic == .design)
    }
}
