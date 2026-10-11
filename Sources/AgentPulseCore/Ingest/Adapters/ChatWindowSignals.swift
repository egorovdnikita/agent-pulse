import Foundation

/// Признаки состояния чата в окне Claude desktop — по подписям кнопок из дерева Accessibility.
/// Окно Claude — тот же claude.ai внутри Electron, поэтому подписи совпадают с веб-версией.
/// Текст переписки не читается: только роли и подписи кнопок и адрес страницы.
public enum ChatWindowSignals {
    public static let hostBundleId = "com.anthropic.claudefordesktop"

    public enum State: String, Sendable {
        case idle, generating, approval
    }

    /// Подписи кнопки ответа чата. Короткое «Stop»/«Остановить» есть и во вкладке Code (`/epitaxy`),
    /// поэтому оно считается признаком только на странице чата.
    static let stopLabels: Set<String> = ["stop response", "остановить ответ"]
    static let shortStopLabels: Set<String> = ["stop", "остановить"]
    static let sendLabels: Set<String> = ["send message", "отправить сообщение"]
    static let shortSendLabels: Set<String> = ["send", "отправить"]
    static let approvalPrefixes = ["allow once", "allow always", "always allow", "allow for this chat", "разрешить"]

    static func normalized(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func isStop(_ label: String, onChat: Bool = false) -> Bool {
        let value = normalized(label)
        return stopLabels.contains(value) || (onChat && shortStopLabels.contains(value))
    }

    public static func isSend(_ label: String, onChat: Bool = false) -> Bool {
        let value = normalized(label)
        return sendLabels.contains(value) || (onChat && shortSendLabels.contains(value))
    }

    public static func isApproval(_ label: String) -> Bool {
        let value = normalized(label)
        return value.count < 40 && approvalPrefixes.contains { value.hasPrefix($0) }
    }

    /// Кнопки композера: по ним находим контейнер, который дальше опрашиваем дёшево.
    public static func isComposerButton(_ label: String, onChat: Bool = false) -> Bool {
        isStop(label, onChat: onChat) || isSend(label, onChat: onChat)
    }

    /// Состояние по подписям видимых кнопок.
    public static func state(buttonLabels: [String], approvalVisible: Bool, onChat: Bool = false) -> State {
        if approvalVisible { return .approval }
        return buttonLabels.contains { isStop($0, onChat: onChat) } ? .generating : .idle
    }

    public static func isClaudePage(_ url: String?) -> Bool {
        guard let url, let host = URL(string: url)?.host() else { return false }
        return host.hasSuffix("claude.ai")
    }

    /// Только страницы чата. Вкладки Code (`/epitaxy`, `/code`) и Cowork видны через свои каналы —
    /// окно с ними не дублируем; неизвестный адрес — не чат.
    public static func isChatPage(_ url: String?) -> Bool {
        guard isClaudePage(url), let path = url.flatMap({ URL(string: $0)?.path() }) else { return false }
        return path.hasPrefix("/chat") || path.hasPrefix("/new") || path.hasPrefix("/project")
    }

    public static func sessionId(_ url: String?) -> String {
        guard let url, let parsed = URL(string: url) else { return "desktop-chat" }
        let parts = parsed.path().split(separator: "/")
        if let index = parts.firstIndex(of: "chat"), index + 1 < parts.count {
            return "desktop-chat-\(parts[index + 1])"
        }
        return "desktop-chat"
    }
}
