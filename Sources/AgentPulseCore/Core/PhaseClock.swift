import Foundation

/// Фазы, которые не приходят событиями, а выводятся из времени:
/// «думает» — пауза после получения задачи; итог (`done`/`failed`) живёт несколько секунд и гаснет в `idle`.
public struct PhaseClock: Sendable {
    public var thinkingAfter: TimeInterval = 0.8
    public var resultHold: TimeInterval = 6
    /// Сессия без событий так долго считается брошенной (агента убили без `SessionEnd`).
    public var staleAfter: TimeInterval = 30 * 60

    public init() {}

    public func advance(_ session: inout SessionInfo, now: Date) {
        let age = now.timeIntervalSince(session.phaseSince)
        switch session.phase {
        case .received where age >= thinkingAfter:
            session.set(.thinking, at: now)
        case .done, .failed:
            if age >= resultHold { session.set(.idle, at: now) }
        case .thinking, .working:
            if now.timeIntervalSince(session.lastEventAt) >= staleAfter { session.set(.idle, at: now) }
        default:
            break
        }
    }
}
