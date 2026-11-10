import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ShelfTypeSearchTests {
    @Test func prefixAndTimeout() {
        var search = ShelfTypeSearch()
        let now = Date()
        let names = ["Другой.txt", "Доклад.md", "Договор.pdf"]
        #expect(search.match("д", names: names, now: now) == 0)
        #expect(search.match("о", names: names, now: now.addingTimeInterval(0.1)) == 1)
        #expect(search.match("ДОГ", names: names, now: now.addingTimeInterval(2)) == 2)
    }
    @Test func substringAndControls() {
        var search = ShelfTypeSearch()
        #expect(search.match("резюме", names: ["Моё РЕЗЮМЕ.pdf"], now: Date()) == 0)
        #expect(search.match("\n", names: [], now: Date()) == nil)
        #expect(search.query == "резюме")
    }
}
