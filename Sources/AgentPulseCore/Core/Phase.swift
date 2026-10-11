import Foundation

/// Что делает инструмент — определяет модус маскота `work`.
public enum ToolKind: String, Codable, Sendable {
    case read, edit, run, search, other
}

/// Над чем работает агент — влияет только на выбор реплики («Пишу…» против «Рисую…»).
public enum WorkTarget: String, Codable, Sendable {
    case code, figma
}

public struct Activity: Sendable, Equatable {
    public var tool: String
    public var kind: ToolKind
    public var target: WorkTarget
    /// Полный человеческий текст: «Правит Package.swift», «Изучает проект».
    public var text: String

    public init(tool: String, kind: ToolKind, target: WorkTarget, text: String) {
        self.tool = tool
        self.kind = kind
        self.target = target
        self.text = text
    }
}

public enum Phase: Sendable, Equatable {
    case idle
    case received
    case thinking
    case working(Activity)
    case awaitingUser(reason: AgentEvent.AwaitReason, message: String)
    case done(summary: String)
    case failed(String)

    /// Строка для меню и тултипа. В облачко не попадает.
    public var text: String {
        switch self {
        case .idle: "Свободен"
        case .received: "Получил задачу"
        case .thinking: "Думает"
        case .working(let activity): activity.text
        case .awaitingUser(let reason, let message):
            message.isEmpty ? (reason == .permission ? "Ждёт разрешения" : "Ждёт тебя") : message
        case .done(let summary): summary
        case .failed(let message): message
        }
    }
}
