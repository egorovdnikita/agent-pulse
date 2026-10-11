import Foundation

public enum WorkMode: String, Sendable, Hashable, CaseIterable, Codable {
    case read, edit, run, search, general
}

public enum MascotState: Sendable, Hashable {
    case sleep
    case idle
    case think
    case work(WorkMode)
    case waitYou(AgentEvent.AwaitReason)

    public var isWaiting: Bool {
        if case .waitYou = self { true } else { false }
    }
}

/// One-shot анимации поверх состояния.
public enum MascotReaction: String, Sendable, CaseIterable {
    case notice, step, done, error

    public var bubbleTrigger: BubbleTrigger {
        switch self {
        case .notice: .notice
        case .step: .step
        case .done: .done
        case .error: .error
        }
    }
}
