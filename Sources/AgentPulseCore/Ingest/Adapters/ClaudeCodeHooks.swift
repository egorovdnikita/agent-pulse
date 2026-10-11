import Foundation

/// Payload хуков Claude Code → `AgentEvent`.
///
/// Формат сообщения от `pulse-hook`: необязательная строка-заголовок `PULSE1 bundle=<id>\n`
/// и следом сырой JSON, который Claude Code передал хуку в stdin.
public enum ClaudeCodeHooks {
    public static let headerPrefix = "PULSE1"

    public static func parse(_ data: Data, now: Date = Date()) -> AgentEvent? {
        let (host, body) = splitEnvelope(data)
        guard
            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
            let name = object["hook_event_name"] as? String,
            let sessionId = object["session_id"] as? String, !sessionId.isEmpty
        else { return nil }

        let context = (object["cwd"] as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent }
        let tool = object["tool_name"] as? String

        func event(
            _ kind: AgentEvent.Kind,
            summary: String? = nil,
            awaitReason: AgentEvent.AwaitReason? = nil,
            isError: Bool = false
        ) -> AgentEvent {
            AgentEvent(
                source: .claudeCode, sessionId: sessionId, kind: kind, tool: tool, summary: summary,
                context: context, awaitReason: awaitReason, isError: isError, hostBundleId: host, ts: now
            )
        }

        switch name {
        case "UserPromptSubmit":
            // Текст промпта намеренно не читаем: приватность по умолчанию.
            return event(.promptSubmitted)
        case "PreToolUse":
            let input = object["tool_input"] as? [String: Any] ?? [:]
            return event(.toolStarted, summary: Humanizer.describe(tool: tool ?? "unknown", input: input).text)
        case "PostToolUse":
            return event(.toolFinished, isError: isErrorResponse(object["tool_response"]))
        case "PostToolUseFailure":
            return event(.toolFinished, isError: true)
        case "Notification":
            let message = object["message"] as? String ?? ""
            guard let reason = awaitReason(type: object["notification_type"] as? String, message: message) else { return nil }
            return event(.awaitingUser, summary: message.isEmpty ? nil : message, awaitReason: reason)
        case "PermissionRequest":
            let input = object["tool_input"] as? [String: Any] ?? [:]
            let what = Humanizer.describe(tool: tool ?? "unknown", input: input).text
            return event(.awaitingUser, summary: "Нужно разрешение: \(what)", awaitReason: .permission)
        case "SubagentStop":
            return event(.subtaskDone)
        case "Stop":
            return event(.stopped)
        case "StopFailure":
            return event(.error, summary: object["error"] as? String)
        case "SessionEnd":
            return event(.sessionEnded)
        default:
            return nil
        }
    }

    static func splitEnvelope(_ data: Data) -> (host: String?, body: Data) {
        guard data.starts(with: Data(headerPrefix.utf8)), let newline = data.firstIndex(of: 0x0A) else {
            return (nil, data)
        }
        let header = String(decoding: data[data.startIndex..<newline], as: UTF8.self)
        var host: String?
        for part in header.split(separator: " ") where part.hasPrefix("bundle=") {
            let value = part.dropFirst("bundle=".count)
            if !value.isEmpty { host = String(value) }
        }
        return (host, Data(data[data.index(after: newline)...]))
    }

    /// Неизвестный тип уведомления (например, `auth_success`) не означает ожидание — игнорируем.
    static func awaitReason(type: String?, message: String) -> AgentEvent.AwaitReason? {
        switch type {
        case "permission_prompt":
            return .permission
        case "idle_prompt", "elicitation_dialog":
            return .input
        case .some:
            return nil
        case nil:
            let lowered = message.lowercased()
            if lowered.contains("permission") { return .permission }
            if lowered.contains("waiting for your input") { return .input }
            return nil
        }
    }

    static func isErrorResponse(_ response: Any?) -> Bool {
        guard let response = response as? [String: Any] else { return false }
        if response["is_error"] as? Bool == true { return true }
        if response["success"] as? Bool == false { return true }
        if let error = response["error"] as? String, !error.isEmpty { return true }
        return false
    }
}
