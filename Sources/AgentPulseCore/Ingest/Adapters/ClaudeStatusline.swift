import Foundation

/// Сообщение от `pulse-statusline`: только проценты и время сброса, остальное обёртка отбрасывает ещё до сокета.
public enum ClaudeStatusline {
    public static let channel = "statusline"

    public static func parse(_ body: Data, now: Date = Date()) -> LimitSnapshot? {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        let windows = [("five_hour", LimitWindowKind.fiveHour), ("seven_day", LimitWindowKind.week)].compactMap { key, kind -> LimitWindow? in
            guard let window = object[key] as? [String: Any], let used = number(window["used_percentage"]) else { return nil }
            return LimitWindow(kind: kind, usedPercent: clamp(used), resetsAt: number(window["resets_at"]).flatMap(date))
        }
        return windows.isEmpty ? nil : LimitSnapshot(service: .claude, windows: windows, at: now)
    }

    static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    static func clamp(_ percent: Double) -> Double {
        max(0, min(100, percent))
    }

    /// Unix-секунды. Миллисекунды тоже понимаем: формат не наш.
    static func date(_ value: Double) -> Date? {
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000 : value)
    }
}
