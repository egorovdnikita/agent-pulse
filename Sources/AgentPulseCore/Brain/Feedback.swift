import Foundation

/// «Мило / бесит» из меню — локальный лог недели валидации. Правило паспорта: реакция с двумя «бесит»
/// за 7 дней уходит в глаза без облачка, пока лог её не отпустит. Оценка самой новости идёт во вкус
/// (`NewsDesk.record`), а не сюда: иначе два «бесит» выключали бы новости целиком.
public enum FeedbackLog {
    public static let window: TimeInterval = 7 * 86_400
    public static let strikes = 2
    /// Оценки рассказанной новости (старые записи — «news.design»): не глушат повод.
    static let newsItems: Set<String> = ["news.item", "news.design"]

    public struct Entry: Sendable, Equatable {
        public var at: Date
        public var reaction: String
        public var verdict: String

        public init(at: Date, reaction: String, verdict: String) {
            self.at = at
            self.reaction = reaction
            self.verdict = verdict
        }
    }

    /// Строки JSONL `{"ts": ISO8601, "reaction": …, "verdict": "мило"|"бесит"}`; битые пропускаются.
    public static func parse(_ data: Data) -> [Entry] {
        let iso = ISO8601DateFormatter()
        return data.split(separator: 0x0A).compactMap { line in
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                let ts = (object["ts"] as? String).flatMap(iso.date(from:)),
                let reaction = object["reaction"] as? String,
                let verdict = object["verdict"] as? String
            else { return nil }
            return Entry(at: ts, reaction: reaction, verdict: verdict)
        }
    }

    /// Реакции, которые за последнюю неделю набрали два «бесит». Агентные не глушатся никогда:
    /// «ждёт тебя» важнее любого раздражения.
    public static func muted(_ entries: [Entry], now: Date) -> Set<String> {
        var counts: [String: Int] = [:]
        for entry in entries where entry.verdict == "бесит" && now.timeIntervalSince(entry.at) < window {
            guard !entry.reaction.hasPrefix("agent."), !newsItems.contains(entry.reaction) else { continue }
            counts[entry.reaction, default: 0] += 1
        }
        return Set(counts.filter { $0.value >= strikes }.keys)
    }
}
