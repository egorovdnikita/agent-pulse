import Foundation

/// Единственное место, где код знает о связи событий и анимации.
/// Behaviors не знают про источники и инструменты.
public enum MascotStateMapper {
    /// Приоритет при нескольких сессиях: wait_you > error > done > work > think > отдых > idle.
    public static func rank(_ phase: Phase) -> Int {
        switch phase {
        case .awaitingUser: 6
        case .failed: 5
        case .done: 4
        case .working: 3
        case .received, .thinking: 2
        case .resting: 1
        case .idle: 0
        }
    }

    /// Маскот один и показывает самую важную сессию; при равенстве — самую свежую.
    public static func dominant(_ sessions: [SessionInfo]) -> SessionInfo? {
        sessions.max { lhs, rhs in
            let (l, r) = (rank(lhs.phase), rank(rhs.phase))
            return l != r ? l < r : lhs.lastEventAt < rhs.lastEventAt
        }
    }

    /// Ожидание, которое ты уже видел, — ключ «сессия + начало ожидания». Новое ожидание той же сессии — новый ключ.
    public static func waitKey(_ session: SessionInfo) -> String? {
        guard case .awaitingUser = session.phase else { return nil }
        return "\(session.id)|\(session.phaseSince.timeIntervalSinceReferenceDate)"
    }

    /// Увиденное ожидание уступает: работает другой агент — маскот работает, иначе обычный покой.
    /// Сессия по-прежнему ждёт (меню, наведение), но маскот больше не смотрит на тебя.
    /// `seen` — когда увидено: от этого момента считается пауза до сна, а не от начала ожидания.
    public static func demotingSeen(_ sessions: [SessionInfo], seen: [String: Date]) -> [SessionInfo] {
        guard !seen.isEmpty else { return sessions }
        return sessions.map { session in
            guard let key = waitKey(session), let seenAt = seen[key] else { return session }
            var calm = session
            calm.phase = .idle
            calm.lastEventAt = max(calm.lastEventAt, seenAt)
            return calm
        }
    }

    public static func state(for sessions: [SessionInfo], now: Date, sleepAfter: TimeInterval) -> MascotState {
        guard let top = dominant(sessions) else { return .sleep }
        switch top.phase {
        case .awaitingUser(let reason, _):
            return .waitYou(reason)
        case .working(let activity):
            return .work(workMode(activity.kind))
        case .received, .thinking:
            return .think
        case .resting:
            // Самая важная сессия отдыхает — значит, другие не заняты и не ждут: засыпает сразу.
            return .sleep
        case .idle, .done, .failed:
            // Итог показывается реакцией; само состояние — idle, а после паузы — сон.
            let last = sessions.map(\.lastEventAt).max() ?? .distantPast
            return now.timeIntervalSince(last) >= sleepAfter ? .sleep : .idle
        }
    }

    public static func workMode(_ kind: ToolKind) -> WorkMode {
        switch kind {
        case .read: .read
        case .edit: .edit
        case .run: .run
        case .search: .search
        case .other: .general
        }
    }

    public static func reaction(for event: AgentEvent) -> MascotReaction? {
        switch event.kind {
        case .promptSubmitted: .notice
        case .subtaskDone: .step
        case .stopped: .done
        case .error: .error
        default: nil
        }
    }

    public static func waitTrigger(_ reason: AgentEvent.AwaitReason) -> BubbleTrigger {
        reason == .permission ? .waitPermission : .waitInput
    }

    public static func ambientTrigger(for state: MascotState, target: WorkTarget?) -> BubbleTrigger? {
        switch state {
        case .think:
            return .think
        case .work(let mode):
            switch mode {
            case .read: return .workRead
            case .edit: return target == .figma ? .workEditFigma : .workEditCode
            case .run: return .workRun
            case .search: return .workSearch
            case .general: return nil
            }
        default:
            return nil
        }
    }
}
