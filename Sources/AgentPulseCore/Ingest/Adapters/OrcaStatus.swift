import Foundation

/// Снимок состояния агентов Orca (`~/Library/Application Support/orca/agent-hooks/last-status.json`) → `AgentEvent`.
///
/// Orca сама ставит хуки всем агентам, которых запускает (Claude Code, Codex, OpenCode, Gemini…), и после каждого
/// события переписывает этот файл: одна запись на панель терминала. Событий в файле нет — только текущее состояние,
/// поэтому события получаем сравнением соседних снимков. Формат внутренний: незнакомая версия — источник недоступен.
/// Читаем состояние, тип агента, имя инструмента и папку; текст промпта, ответа и аргументы инструментов — никогда.
public enum OrcaStatus {
    /// По клику на маскота открываем Orca.
    public static let hostBundleId = "com.stablyai.orca"
    public static let supportedVersion = 2

    public struct Entry: Sendable, Equatable {
        public enum State: String, Sendable {
            case working, blocked, waiting, done
        }

        public var paneKey: String
        public var agentType: String
        public var state: State
        public var promptId: String?
        public var toolUseId: String?
        public var toolName: String?
        public var cwd: String?
        /// Для `done`: `success`, `failure`, `cancellation`…
        public var outcome: String?
        public var interrupted: Bool

        /// Смена любого из этих полей — событие; остальное (время, текст) не важно.
        var step: [String?] { [state.rawValue, promptId, toolUseId] }
    }

    /// nil — формат незнакомый.
    public static func parse(snapshot data: Data) -> [String: Entry]? {
        guard
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            object["version"] as? Int == supportedVersion,
            let entries = object["entries"] as? [String: Any]
        else { return nil }

        var result: [String: Entry] = [:]
        for (key, value) in entries {
            guard
                let entry = value as? [String: Any],
                let payload = entry["payload"] as? [String: Any],
                let state = (payload["state"] as? String).flatMap(Entry.State.init(rawValue:))
            else { continue }
            let agent = payload["agentType"] as? String ?? (entry["agentPresence"] as? [String: Any])?["agent"] as? String
            result[key] = Entry(
                paneKey: key,
                agentType: agent ?? "unknown",
                state: state,
                promptId: entry["providerPromptId"] as? String,
                toolUseId: entry["toolUseId"] as? String,
                toolName: payload["toolName"] as? String,
                cwd: (entry["providerSession"] as? [String: Any])?["cwd"] as? String,
                outcome: (payload["mainAgent"] as? [String: Any])?["outcome"] as? String,
                interrupted: payload["interrupted"] as? Bool == true
            )
        }
        return result
    }

    /// События между двумя снимками. Claude Code с хуками Pulse виден подробнее напрямую — тогда его пропускаем.
    public static func diff(
        from old: [String: Entry],
        to new: [String: Entry],
        includeClaude: Bool,
        now: Date = Date()
    ) -> [AgentEvent] {
        func skip(_ entry: Entry) -> Bool { !includeClaude && entry.agentType == "claude" }
        var events: [AgentEvent] = []

        for key in new.keys.sorted() {
            guard let entry = new[key], !skip(entry) else { continue }
            let previous = old[key]
            guard previous?.step != entry.step else { continue }

            func event(_ kind: AgentEvent.Kind, summary: String? = nil, awaitReason: AgentEvent.AwaitReason? = nil) -> AgentEvent {
                AgentEvent(
                    source: .orca, sessionId: sessionId(key), kind: kind, tool: entry.toolName, summary: summary,
                    context: entry.cwd.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent },
                    awaitReason: awaitReason, hostBundleId: hostBundleId, agent: agentName(entry.agentType), ts: now
                )
            }

            let newPrompt = entry.promptId != nil && entry.promptId != previous?.promptId
            // Панель, которая появилась уже завершённой, — старая работа, не новость.
            if previous == nil && entry.state == .done { continue }
            if newPrompt && entry.state != .done { events.append(event(.promptSubmitted)) }

            switch entry.state {
            case .working:
                events.append(event(entry.toolName == nil ? .toolFinished : .toolStarted))
            case .blocked:
                let what = entry.toolName.map { "Нужно разрешение: " + Humanizer.classify(tool: $0).text }
                events.append(event(.awaitingUser, summary: what, awaitReason: .permission))
            case .waiting:
                events.append(event(.awaitingUser, awaitReason: .input))
            case .done:
                switch entry.outcome {
                case "failure":
                    events.append(event(.error, summary: "Не вышло"))
                case "cancellation", "superseded", "interruption":
                    events.append(event(.sessionEnded))
                default:
                    events.append(entry.interrupted ? event(.sessionEnded) : event(.stopped))
                }
            }
        }

        for key in old.keys.sorted() where new[key] == nil {
            guard let entry = old[key], !skip(entry) else { continue }
            events.append(AgentEvent(source: .orca, sessionId: sessionId(key), kind: .sessionEnded, hostBundleId: hostBundleId, ts: now))
        }
        return events
    }

    static func sessionId(_ paneKey: String) -> String { "orca:" + paneKey }

    /// Тип агента Orca → имя, как его называют люди.
    static func agentName(_ type: String) -> String {
        switch type {
        case "claude": "Claude Code"
        case "codex": "Codex"
        case "opencode", "opencode2", "opencode-go": "OpenCode"
        case "gemini": "Gemini"
        case "cursor": "Cursor"
        case "copilot": "Copilot"
        case "grok": "Grok"
        case "kimi": "Kimi"
        case "devin": "Devin"
        case "cline": "Cline"
        case "droid": "Droid"
        case "antigravity": "Antigravity"
        case "unknown": "Orca"
        default: type.prefix(1).uppercased() + type.dropFirst()
        }
    }
}
