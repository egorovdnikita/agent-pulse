import Foundation

/// Напоминания привязаны к конкретному эпизоду ожидания, а не к имени агента.
public struct WaitReminder: Sendable {
    public private(set) var deadlines: [String: Date] = [:]
    public init() {}
    public mutating func postpone(_ session: SessionInfo, now: Date, seconds: TimeInterval = 600) {
        guard let key = MascotStateMapper.waitKey(session), seconds.isFinite, seconds > 0 else { return }
        deadlines[key] = now.addingTimeInterval(min(seconds, 86400))
    }
    public mutating func cancel(_ session: SessionInfo) {
        if let key = MascotStateMapper.waitKey(session) { deadlines[key] = nil }
    }
    public mutating func due(sessions: [SessionInfo], now: Date) -> [SessionInfo] {
        let current = Set(sessions.compactMap(MascotStateMapper.waitKey))
        deadlines = deadlines.filter { current.contains($0.key) }
        return sessions.filter { session in
            guard let key = MascotStateMapper.waitKey(session), let date = deadlines[key], date <= now else { return false }
            deadlines[key] = nil
            return true
        }
    }
}
