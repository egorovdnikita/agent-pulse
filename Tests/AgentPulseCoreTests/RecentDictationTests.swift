import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct RecentDictationTests {
    @Test func onlyRecentExplicitCorrectionCanChangeInsertion() {
        let now = Date(timeIntervalSince1970: 1000)
        let recent = RecentDictation(text: "Новый макет.", now: now)
        #expect(recent.correcting("замени макет на дизайн", now: now) == "Новый дизайн.")
        #expect(recent.correcting("замени макет на дизайн", now: now.addingTimeInterval(121)) == nil)
        #expect(recent.correcting("замени макет на дизайн", now: now.addingTimeInterval(-1)) == nil)
        #expect(recent.correcting("Обычная диктовка", now: now) == nil)
        #expect(!RecentDictation(text: "", now: now).isCurrent(now: now))
    }
}
