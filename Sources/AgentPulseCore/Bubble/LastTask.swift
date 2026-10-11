import Foundation

/// Последний запрос к агенту — то, что маскот рассказывает при наведении, когда сам ничем не занят.
/// Переживает конец сессии: «что там было» интересно и после выхода из Claude Code.
public struct LastTask: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case active(String)
        case waiting
        case done
        case failed
    }

    public var source: AgentEvent.Source
    public var usedFigma: Bool
    public var context: String?
    public var status: Status
    public var at: Date

    public init(source: AgentEvent.Source, usedFigma: Bool, context: String?, status: Status, at: Date) {
        self.source = source
        self.usedFigma = usedFigma
        self.context = context
        self.status = status
        self.at = at
    }

    /// Обновление по событию; `session` — состояние сессии уже после события.
    public static func updated(_ previous: LastTask?, event: AgentEvent, session: SessionInfo?) -> LastTask? {
        guard let session else { return previous }
        let status: Status
        switch session.phase {
        case .received, .thinking, .working: status = .active(session.phase.text)
        case .awaitingUser: status = .waiting
        case .done: status = .done
        case .failed: status = .failed
        case .idle:
            guard let previous else { return nil }
            status = previous.status
        }
        return LastTask(source: session.source, usedFigma: session.usedFigma, context: session.context, status: status, at: event.ts)
    }

    /// Две строки: откуда и что с ним. «Figma (Cowork)» / «Готово · 5 мин назад».
    public func summary(now: Date) -> String {
        let origin = usedFigma ? "Figma (\(source.displayName))" : source.displayName
        let head = [origin, context].compactMap(\.self).joined(separator: " · ")
        let tail = switch status {
        case .active(let text): text
        case .waiting: "Ждёт тебя"
        case .done: "Готово · \(Self.ago(now.timeIntervalSince(at)))"
        case .failed: "Не вышло · \(Self.ago(now.timeIntervalSince(at)))"
        }
        return "\(head)\n\(tail)"
    }

    static func ago(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: "только что"
        case ..<3600: "\(Int(seconds / 60)) мин назад"
        case ..<86_400: "\(Int(seconds / 3600)) ч назад"
        default: "давно"
        }
    }
}
