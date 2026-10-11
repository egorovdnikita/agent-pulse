import Foundation

/// Сообщения расширения Chrome (claude.ai, Figma Make) → `AgentEvent`.
///
/// Расширение присылает только смену состояния страницы: `{v: 1, app, session, state, from}`,
/// где `state` и `from` — `idle` | `generating` | `approval` | `closed`. Текста переписки в сообщении нет.
/// Деталей инструментов браузер не даёт, поэтому маскот здесь «думает», а не «читает» или «пишет».
public enum BrowserBridge {
    /// Генерация в Figma Make — как инструмент, чтобы маскот «рисовал».
    public static let figmaMakeTool = "FigmaMake"

    public static func parse(_ body: Data, host: String?, now: Date = Date()) -> [AgentEvent] {
        guard
            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
            object["v"] as? Int == 1,
            let app = object["app"] as? String,
            let session = object["session"] as? String, !session.isEmpty,
            let state = object["state"] as? String
        else { return [] }
        let from = object["from"] as? String ?? "idle"

        let source: AgentEvent.Source
        switch app {
        case "claude": source = .claudeChat
        case "figmaMake": source = .figmaAI
        default: return []
        }
        return events(source: source, session: session, state: state, from: from, host: host, now: now)
    }

    /// Смена состояния страницы или окна → события. Общая для расширения и наблюдателя за окном Claude.
    public static func events(
        source: AgentEvent.Source, session: String, state: String, from: String, host: String?, now: Date = Date()
    ) -> [AgentEvent] {
        func event(_ kind: AgentEvent.Kind, tool: String? = nil, summary: String? = nil, awaitReason: AgentEvent.AwaitReason? = nil) -> AgentEvent {
            AgentEvent(
                source: source, sessionId: session, kind: kind, tool: tool, summary: summary,
                awaitReason: awaitReason, hostBundleId: host, ts: now
            )
        }

        let making = source == .figmaAI
            ? [event(.toolStarted, tool: figmaMakeTool, summary: Humanizer.classify(tool: figmaMakeTool).text)]
            : []

        switch (state, from) {
        case ("generating", "approval"):
            return source == .figmaAI ? making : [event(.toolFinished)]
        case ("generating", _):
            return [event(.promptSubmitted)] + making
        case ("approval", _):
            return [event(.awaitingUser, summary: "Нужно разрешение на инструмент", awaitReason: .permission)]
        case ("idle", "generating"), ("idle", "approval"):
            return [event(.stopped)]
        case ("closed", _):
            return [event(.sessionEnded)]
        default:
            return []
        }
    }
}
