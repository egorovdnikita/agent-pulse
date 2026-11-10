import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct LimitExplanationTests {
    @Test func missingWindowHasNoInventedDate() {
        let text = LimitExplanation.text(service: .claude, kind: .week, book: LimitsBook(), now: Date())
        #expect(text.contains("Данных для этого окна пока нет"))
        #expect(!text.contains("Сброс:"))
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
