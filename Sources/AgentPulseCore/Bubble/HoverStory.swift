import Foundation

/// Что маскот рассказывает при наведении — от себя и по-человечески, без технических строк.
public enum HoverStory {
    /// Агент сейчас занят: «Работаю 12 мин, сделано 8 шагов», «Жду тебя уже 3 мин».
    public static func working(source: AgentEvent.Source?, host: String? = nil, phase: Phase, since: Date, steps: Int, now: Date) -> BubbleMessage {
        let minutes = Int(now.timeIntervalSince(since) / 60)
        let text: String
        switch phase {
        case .awaitingUser(let reason, _):
            let what = reason == .permission ? "Жду твоего разрешения" : "Жду тебя"
            text = minutes > 0 ? "\(what) уже \(minutes) мин" : what
        case .thinking, .received:
            text = minutes > 0 ? "Думаю уже \(minutes) мин" : "Думаю над задачей"
        default:
            let time = minutes > 0 ? "Работаю \(minutes) мин" : "Только начинаю"
            text = steps > 1 ? "\(time), сделано \(steps) \(HumanTime.plural(steps, "шаг", "шага", "шагов"))" : time
        }
        return BubbleMessage(category: .agent(source, host: host), title: BubbleCategory.agentTitle(source, host: host), text: text, when: "сейчас")
    }

    /// Итог дня или, в пятницу вечером и в выходные, недели. nil — рассказывать нечего.
    public static func summary(today: DayMemory.Day, week: DayMemory.Day, weekday: Int, hour: Int) -> BubbleMessage? {
        let weekly = (weekday == 6 && hour >= 16) || weekday == 7 || weekday == 1
        let day = weekly ? week : today
        guard day.agentTasks > 0 || day.strokes > 0 else { return nil }
        let when = weekly ? "За неделю" : "Сегодня"
        var parts: [String] = []
        if day.agentTasks > 0 {
            parts.append("\(when) \(HumanTime.plural(day.agentTasks, "сделана", "сделано", "сделано")) \(day.agentTasks) \(HumanTime.plural(day.agentTasks, "задача", "задачи", "задач"))")
        }
        if day.strokes > 0 {
            let times = "\(day.strokes) \(HumanTime.plural(day.strokes, "раз", "раза", "раз"))"
            parts.append(parts.isEmpty ? "\(when) меня погладили \(times)" : "меня погладили \(times)")
        }
        return BubbleMessage(category: .day, title: weekly ? "Наша неделя" : "Наш день", text: parts.joined(separator: ", "))
    }
}
