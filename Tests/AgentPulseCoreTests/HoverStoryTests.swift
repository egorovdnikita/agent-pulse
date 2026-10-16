import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct HoverStoryTests {
    let now = Date()

    @Test func workingIsToldFromFirstPerson() {
        let activity = Activity(tool: "Edit", kind: .edit, target: .code, text: "Правит файл")
        let work = HoverStory.working(source: .claudeCode, phase: .working(activity), since: now.addingTimeInterval(-12 * 60), steps: 8, now: now)
        #expect(work.text == "Работаю 12 мин, сделано 8 шагов")
        #expect(work.title == "Claude Code")
        let wait = HoverStory.working(source: .cowork, phase: .awaitingUser(reason: .permission, message: ""), since: now.addingTimeInterval(-180), steps: 0, now: now)
        #expect(wait.text == "Жду твоего разрешения уже 3 мин")
        let fresh = HoverStory.working(source: .figmaCompanion, phase: .working(activity), since: now, steps: 0, now: now)
        #expect(fresh.text == "Только начинаю")
        #expect(fresh.category == .figma)
    }

    @Test func dayAndWeekSummaries() {
        var today = DayMemory.Day(date: "d")
        today.agentTasks = 3
        today.strokes = 2
        var week = DayMemory.Day(date: "w")
        week.agentTasks = 21
        // Вторник вечер — день.
        #expect(HoverStory.summary(today: today, week: week, weekday: 3, hour: 19)?.text == "Сегодня сделано 3 задачи, меня погладили 2 раза")
        // Пятница вечер — неделя.
        let friday = HoverStory.summary(today: today, week: week, weekday: 6, hour: 18)
        #expect(friday?.text == "За неделю сделана 21 задача")
        #expect(friday?.title == "Наша неделя")
        #expect(HoverStory.summary(today: DayMemory.Day(date: "x"), week: DayMemory.Day(date: "y"), weekday: 3, hour: 19) == nil)
    }
}
