import Foundation

/// Объясняет реальные данные снимка, не выдумывая дату сброса и не считая кеш свежим.
public enum LimitExplanation {
    public static func text(service: LimitService, kind: LimitWindowKind, book: LimitsBook, now: Date) -> String {
        let source = service == .claude ? (book.snapshots[service]?.origin == .claudeUsage ? "Claude Code · get_usage" : "Строка состояния Claude Code") : "Codex app-server"
        var lines = [service.title + " · " + kind.title, "Источник: " + source]
        guard let snapshot = book.snapshots[service], let reading = book.reading(service, kind, now: now) else {
            lines.append("Данных для этого окна пока нет.")
            return lines.joined(separator: "\n")
        }
        lines.append("Израсходовано: \(reading.usedPercent)%")
        let date = DateFormatter()
        date.locale = Locale(identifier: "ru_RU")
        date.dateStyle = .medium; date.timeStyle = .medium
        let received = snapshot.windows.first { $0.kind == kind }?.observedAt ?? snapshot.at
        lines.append("Снимок получен: " + date.string(from: received))
        lines.append(reading.stale ? "Данные устарели." : "Данные не старше 30 минут.")
        if let reset = reading.resetsAt { lines.append("Сброс: " + date.string(from: reset)) }
        else { lines.append("Источник не сообщил время следующего сброса.") }
        if service == .claude { lines.append("Свежие лимиты запрашиваются через Claude Code: раз в 5 минут, при открытом Пульте — раз в минуту.") }
        return lines.joined(separator: "\n")
    }
}
