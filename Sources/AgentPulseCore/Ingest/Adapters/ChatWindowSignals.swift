import Foundation

/// Признаки состояния чата в окне Claude desktop — по подписям кнопок из дерева Accessibility.
/// Окно Claude — тот же claude.ai внутри Electron, поэтому подписи совпадают с веб-версией.
/// Текст переписки не читается: только роли и подписи кнопок и адрес страницы.
public enum ChatWindowSignals {
    public static let hostBundleId = "com.anthropic.claudefordesktop"

    public enum State: String, Sendable {
        case idle, generating, approval
    }

    static let stopLabels: Set<String> = ["stop response", "stop", "остановить ответ", "остановить"]
    static let sendLabels: Set<String> = ["send message", "send", "отправить сообщение", "отправить"]
    static let approvalPrefixes = ["allow once", "allow always", "always allow", "allow for this chat", "разрешить"]

    static func normalized(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func isStop(_ label: String) -> Bool {
        stopLabels.contains(normalized(label))
    }

    public static func isSend(_ label: String) -> Bool {
        sendLabels.contains(normalized(label))
    }

    public static func isApproval(_ label: String) -> Bool {
        let value = normalized(label)
        return value.count < 40 && approvalPrefixes.contains { value.hasPrefix($0) }
    }

    /// Кнопки композера: по ним находим контейнер, который дальше опрашиваем дёшево.
    public static func isComposerButton(_ label: String) -> Bool {
        isStop(label) || isSend(label)
    }

    /// Состояние по подписям видимых кнопок.
    public static func state(buttonLabels: [String], approvalVisible: Bool) -> State {
        if approvalVisible { return .approval }
        return buttonLabels.contains(where: isStop) ? .generating : .idle
    }

    /// Вкладки Code и Cowork видны через свои каналы (хуки, журнал) — окно с ними не дублируем.
    public static func isChatPage(_ url: String?) -> Bool {
        guard let url, let parsed = URL(string: url), let host = parsed.host() else { return true }
        guard host.hasSuffix("claude.ai") || host.hasSuffix("anthropic.com") else { return true }
        let path = parsed.path()
        return !(path.hasPrefix("/code") || path.contains("/task") || path.contains("cowork") || path.contains("local-agent"))
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
