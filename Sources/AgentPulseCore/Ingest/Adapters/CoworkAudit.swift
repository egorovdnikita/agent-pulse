import Foundation

/// Строки журнала Cowork (`local-agent-mode-sessions/**/audit.jsonl`) → `AgentEvent`.
///
/// Журнал — поток сообщений Claude Agent SDK, Cowork пишет его по ходу работы (задержка ~1 ms).
/// Формат внутренний и неофициальный: незнакомые строки молча пропускаем, текст сообщений не читаем.
public enum CoworkAudit {
    /// По клику на маскота открываем Claude desktop.
    public static let hostBundleId = "com.anthropic.claudefordesktop"

    public static func parse(line: Data, now: Date = Date()) -> [AgentEvent] {
        guard
            let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
            let type = object["type"] as? String,
            let sessionId = object["session_id"] as? String, !sessionId.isEmpty
        else { return [] }

        func event(
            _ kind: AgentEvent.Kind,
            tool: String? = nil,
            summary: String? = nil,
            awaitReason: AgentEvent.AwaitReason? = nil,
            isError: Bool = false
        ) -> AgentEvent {
            AgentEvent(
                source: .cowork, sessionId: sessionId, kind: kind, tool: tool, summary: summary,
                awaitReason: awaitReason, isError: isError, hostBundleId: hostBundleId, ts: now
            )
        }

        switch (type, object["subtype"] as? String) {
        case ("user", _):
            let content = (object["message"] as? [String: Any])?["content"]
            let blocks = content as? [[String: Any]] ?? []
            let results = blocks.filter { $0["type"] as? String == "tool_result" }
            if !results.isEmpty {
                let failed = results.contains { $0["is_error"] as? Bool == true }
                return [event(.toolFinished, isError: failed)]
            }
            // Текст или вложения от пользователя в основном потоке — новый запрос. Текст не читаем.
            guard object["parent_tool_use_id"] is NSNull || object["parent_tool_use_id"] == nil else { return [] }
            return content is String || !blocks.isEmpty ? [event(.promptSubmitted)] : []

        case ("assistant", _):
            let blocks = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return blocks.compactMap { block in
                guard block["type"] as? String == "tool_use", let name = block["name"] as? String else { return nil }
                if let question = Humanizer.questionTools[name] {
                    return event(.awaitingUser, tool: name, summary: question, awaitReason: .input)
                }
                let input = block["input"] as? [String: Any] ?? [:]
                return event(.toolStarted, tool: name, summary: Humanizer.describe(tool: name, input: input).text)
            }

        case ("system", "permission_request"):
            let tool = object["tool_name"] as? String ?? "unknown"
            let input = object["tool_input"] as? [String: Any] ?? [:]
            let what = Humanizer.describe(tool: tool, input: input).text
            return [event(.awaitingUser, tool: tool, summary: "Нужно разрешение: \(what)", awaitReason: .permission)]

        case ("system", "permission_response"):
            // Пользователь ответил — инструмент продолжает работу (или агент передумает и пойдёт дальше).
            let tool = object["tool_name"] as? String ?? "unknown"
            let granted = object["granted"] as? Bool ?? false
            return granted
                ? [event(.toolStarted, tool: tool, summary: Humanizer.classify(tool: tool).text)]
                : [event(.toolFinished, tool: tool)]

        case ("result", let subtype):
            let failed = object["is_error"] as? Bool == true || subtype?.hasPrefix("error") == true
            return [failed ? event(.error, summary: "Не вышло") : event(.stopped)]

        default:
            return []
        }
    }
}
