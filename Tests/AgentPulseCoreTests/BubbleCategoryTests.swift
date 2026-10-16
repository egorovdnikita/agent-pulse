import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct BubbleCategoryTests {
    @Test func reactionsGoToTheirCategory() {
        #expect(BubbleCategory.forReaction("battery.low") == .battery)
        #expect(BubbleCategory.forReaction("thermal.high") == .wellbeing)
        #expect(BubbleCategory.forReaction("network.lost") == .network)
        #expect(BubbleCategory.forReaction("headphones") == .devices)
        #expect(BubbleCategory.forReaction("greeting.friday") == .day)
        #expect(BubbleCategory.forReaction("birthday") == .holiday)
        #expect(BubbleCategory.forReaction("poke.enough") == .together)
        #expect(BubbleCategory.forReaction("fun.sneeze") == .mood)
        #expect(BubbleCategory.forReaction("news.design") == .news)
        #expect(BubbleCategory.forReaction("agent.waitLong") == .claude)
        #expect(BubbleCategory.agent(.figmaCompanion) == .figma)
        #expect(BubbleCategory.agentTitle(.cowork) == "Claude Cowork")
    }

    @Test func everyCategoryHasDistinctColor() {
        let colors = BubbleCategory.allCases.map(\.color)
        #expect(Set(colors).count == colors.count)
    }

    @Test func schedulerKeepsCategoryAndTitle() {
        var scheduler = BubbleScheduler()
        let now = Date()
        scheduler.react(.done, category: .claude, title: "Claude Code", now: now)
        #expect(scheduler.current?.title == "Claude Code")
        var other = BubbleScheduler()
        other.say("Мне жарко…", duration: 2, category: .wellbeing, now: now)
        #expect(other.current?.category == .wellbeing)
        #expect(other.current?.title == "Самочувствие")
        var sleepy = BubbleScheduler()
        sleepy.react(.fallAsleep, now: now)
        #expect(sleepy.current?.category == .rest)
    }

    @Test func humanTime() {
        #expect(HumanTime.ago(30) == "только что")
        #expect(HumanTime.ago(5 * 60) == "5 мин назад")
        #expect(HumanTime.ago(3600) == "час назад")
        #expect(HumanTime.plural(21, "задача", "задачи", "задач") == "задача")
        #expect(HumanTime.plural(12, "задача", "задачи", "задач") == "задач")
        #expect(HumanTime.plural(3, "задача", "задачи", "задач") == "задачи")
    }
}
