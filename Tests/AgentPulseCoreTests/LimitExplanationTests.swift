import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct LimitExplanationTests {
    @Test func missingWindowHasNoInventedDate() {
        let text = LimitExplanation.text(service: .claude, kind: .week, book: LimitsBook(), now: Date())
        #expect(text.contains("Данных для этого окна пока нет"))
        #expect(!text.contains("Сброс:"))
    }
    @Test func partialRefreshDoesNotMakeOldWeekFresh() {
        let now = Date(); var book = LimitsBook()
        _ = book.ingest(.init(service: .claude, windows: [.init(kind: .week, usedPercent: 50, resetsAt: nil)], at: now.addingTimeInterval(-3600)), now: now)
        _ = book.ingest(.init(service: .claude, windows: [.init(kind: .fiveHour, usedPercent: 10, resetsAt: nil)], at: now), now: now)
        #expect(book.reading(.claude, .week, now: now)?.stale == true)
        #expect(book.reading(.claude, .fiveHour, now: now)?.stale == false)
        #expect(LimitExplanation.text(service: .claude, kind: .week, book: book, now: now).contains("устарели"))
    }
    @Test func staleCacheIsExplicit() {
        var book = LimitsBook(); let now = Date()
        _ = book.ingest(LimitSnapshot(service: .claude, windows: [.init(kind: .fiveHour, usedPercent: 42, resetsAt: nil)], at: now.addingTimeInterval(-3600)), now: now)
        let text = LimitExplanation.text(service: .claude, kind: .fiveHour, book: book, now: now)
        #expect(text.contains("42%"))
        #expect(text.contains("устарели"))
        #expect(text.contains("перечитывает кеш"))
        #expect(!text.contains("Сброс:"))
    }
}
