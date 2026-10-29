import Foundation

/// Единая модель события. Все источники приводятся к ней; UI и маскот ничего не знают об источниках.
public struct AgentEvent: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case claudeCode, cowork, claudeChat, figmaAI, figmaMCP, figmaCompanion, orca

        public var displayName: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .cowork: "Cowork"
            case .claudeChat: "Claude Chat"
            case .figmaAI: "Figma AI"
            case .figmaMCP, .figmaCompanion: "Figma"
            case .orca: "Orca"
            }
        }
    }

    public enum Kind: String, Codable, Sendable {
        case promptSubmitted, toolStarted, toolFinished, awaitingUser, subtaskDone, stopped, sessionEnded, error
    }

    /// Почему агент ждёт пользователя: от этого зависит реплика и текст уведомления.
    public enum AwaitReason: String, Codable, Sendable, Hashable {
        case permission, input
    }

    public var source: Source
    public var sessionId: String
    public var kind: Kind
    public var tool: String?
    /// Уже очеловеченная строка (полный текст для уведомления), если источник её дал.
    public var summary: String?
    /// Проект или файл Figma.
    public var context: String?
    public var awaitReason: AwaitReason?
    /// Инструмент завершился ошибкой (для `.toolFinished`). Это не провал задачи: агент обычно исправляется сам.
    public var isError: Bool
    /// Bundle id приложения, в котором живёт агент (терминал, IDE), — для перехода по клику.
    public var hostBundleId: String?
    /// Имя агента, если источник запускает разных («Codex» в Orca). nil — агент следует из источника.
    public var agent: String?
    public var ts: Date

    public init(
        source: Source,
        sessionId: String,
        kind: Kind,
        tool: String? = nil,
        summary: String? = nil,
        context: String? = nil,
        awaitReason: AwaitReason? = nil,
        isError: Bool = false,
        hostBundleId: String? = nil,
        agent: String? = nil,
        ts: Date = Date()
    ) {
        self.source = source
        self.sessionId = sessionId
        self.kind = kind
        self.tool = tool
        self.summary = summary
        self.context = context
        self.awaitReason = awaitReason
        self.isError = isError
        self.hostBundleId = hostBundleId
        self.agent = agent
        self.ts = ts
    }
}
