import Foundation

/// Единственное место, где код знает о связи событий и анимации.
/// Behaviors не знают про источники и инструменты.
public enum MascotStateMapper {
    /// Приоритет при нескольких сессиях: wait_you > error > done > work > think > idle.
    public static func rank(_ phase: Phase) -> Int {
        switch phase {
        case .awaitingUser: 6
        case .failed: 5
        case .done: 4
        case .working: 3
        case .received, .thinking: 2
        case .idle: 1
        }
    }

    /// Маскот один и показывает самую важную сессию; при равенстве — самую свежую.
    public static func dominant(_ sessions: [SessionInfo]) -> SessionInfo? {
        sessions.max { lhs, rhs in
            let (l, r) = (rank(lhs.phase), rank(rhs.phase))
            return l != r ? l < r : lhs.lastEventAt < rhs.lastEventAt
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
