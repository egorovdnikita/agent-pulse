import Foundation

/// Первая доступная сеть при запуске не считается восстановлением.
/// После обрыва запрос ждёт оставшуюся часть обычного минутного ограничения.
public struct NetworkRecovery: Sendable {
    public static let minimumInterval: TimeInterval = 60
    private var wasLost = false
    public init() {}
    public mutating func receive(_ kind: SignalKind, now: Date, lastAttempt: Date) -> TimeInterval? {
        if kind == .networkLost { wasLost = true; return nil }
        guard kind == .networkBack, wasLost else { return nil }
        wasLost = false
        return max(0, Self.minimumInterval - now.timeIntervalSince(lastAttempt))
    }
}
