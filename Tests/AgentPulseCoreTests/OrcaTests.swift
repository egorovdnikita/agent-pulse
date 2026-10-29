import Foundation
import Testing
@testable import AgentPulseCore

/// Снимки повторяют структуру настоящего `last-status.json` Orca 1.4 (ключи сняты с файла на машине автора),
/// текст промптов и ответов заменён.
enum OrcaFixtures {
    static let pane = "tab-1:pane-1"

    static func entry(
        agent: String = "codex",
        state: String,
        prompt: String? = "p1",
        tool: String? = nil,
        toolUse: String? = nil,
        outcome: String? = nil,
        interrupted: Bool = false
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "state": state, "prompt": "секретный промпт", "agentType": agent,
            "lastAssistantMessage": "секретный ответ",
            "mainAgent": ["state": state, "stateStartedAt": 1_793_292_704_404] as [String: Any],
        ]
        if let tool {
            payload["toolName"] = tool
            payload["toolInput"] = "rm -rf секрет"
        }
        if let outcome { payload["mainAgent"] = ["state": state, "outcome": outcome, "stateStartedAt": 1] as [String: Any] }
        if interrupted { payload["interrupted"] = true }
        var entry: [String: Any] = [
            "paneKey": pane, "source": agent, "agentPresence": ["agent": agent],
            "tabId": "tab-1", "worktreeId": "w::/Users/me/Projects/agent-pulse", "hookEventName": "PostToolUse",
            "providerSession": ["key": "session_id", "id": "s1", "cwd": "/Users/me/Projects/agent-pulse"],
            "payload": payload,
        ]
        if let prompt { entry["providerPromptId"] = prompt }
        if let toolUse { entry["toolUseId"] = toolUse }
        return entry
    }

    static func snapshot(_ entries: [String: [String: Any]], version: Int = 2) -> Data {
        try! JSONSerialization.data(withJSONObject: ["version": version, "entries": entries, "authorityCommitments": [:]])
    }

    static func parsed(_ entries: [String: [String: Any]]) -> [String: OrcaStatus.Entry] {
        OrcaStatus.parse(snapshot: snapshot(entries))!
    }
}

@Suite struct OrcaStatusTests {
    typealias F = OrcaFixtures

    func kinds(_ old: [String: [String: Any]], _ new: [String: [String: Any]], includeClaude: Bool = false) -> [AgentEvent.Kind] {
        OrcaStatus.diff(from: F.parsed(old), to: F.parsed(new), includeClaude: includeClaude).map(\.kind)
    }

    @Test func parsesWithoutReadingText() throws {
        let entry = try #require(F.parsed([F.pane: F.entry(state: "working", tool: "exec_command", toolUse: "t1")])[F.pane])
        #expect(entry.agentType == "codex")
        #expect(entry.state == .working)
        #expect(entry.toolName == "exec_command")
        #expect(entry.cwd == "/Users/me/Projects/agent-pulse")
        // В модели нет полей для текста промпта, ответа и аргументов.
        #expect(!String(describing: entry).contains("секрет"))
    }

    @Test func unknownFormatIsUnavailable() {
        #expect(OrcaStatus.parse(snapshot: F.snapshot([:], version: 3)) == nil)
        #expect(OrcaStatus.parse(snapshot: Data("{".utf8)) == nil)
        #expect(OrcaStatus.parse(snapshot: F.snapshot([:])) == [:])
    }

    @Test func taskLifecycle() {
        let start = [F.pane: F.entry(state: "working")]
        #expect(kinds([:], start) == [.promptSubmitted, .toolFinished])
        let tool = [F.pane: F.entry(state: "working", tool: "apply_patch", toolUse: "t1")]
        #expect(kinds(start, tool) == [.toolStarted])
        #expect(kinds(tool, tool).isEmpty)
        let done = [F.pane: F.entry(state: "done", tool: "apply_patch", toolUse: "t1")]
        #expect(kinds(tool, done) == [.stopped])
        let next = [F.pane: F.entry(state: "working", prompt: "p2")]
        #expect(kinds(done, next) == [.promptSubmitted, .toolFinished])
    }

    @Test func waitingForUser() {
        let working = [F.pane: F.entry(state: "working")]
        let blocked = OrcaStatus.diff(
            from: F.parsed(working), to: F.parsed([F.pane: F.entry(state: "blocked", tool: "exec_command", toolUse: "t1")]),
            includeClaude: false
        )
        #expect(blocked.map(\.kind) == [.awaitingUser])
        #expect(blocked.first?.awaitReason == .permission)
        let waiting = OrcaStatus.diff(from: F.parsed(working), to: F.parsed([F.pane: F.entry(state: "waiting")]), includeClaude: false)
        #expect(waiting.first?.awaitReason == .input)
    }

    @Test func endings() {
        let working = [F.pane: F.entry(state: "working")]
        #expect(kinds(working, [F.pane: F.entry(state: "done", outcome: "failure")]) == [.error])
        #expect(kinds(working, [F.pane: F.entry(state: "done", outcome: "cancellation")]) == [.sessionEnded])
        #expect(kinds(working, [F.pane: F.entry(state: "done", interrupted: true)]) == [.sessionEnded])
        #expect(kinds(working, [:]) == [.sessionEnded])
        // Панель появилась уже завершённой — это старая работа.
        #expect(kinds([:], [F.pane: F.entry(state: "done")]).isEmpty)
    }

    @Test func claudeOnlyWithoutPulseHooks() {
        let claude = [F.pane: F.entry(agent: "claude", state: "working")]
        #expect(kinds([:], claude).isEmpty)
        #expect(kinds([:], claude, includeClaude: true) == [.promptSubmitted, .toolFinished])
    }

    @Test func eventCarriesHostAgentAndProject() throws {
        let event = try #require(OrcaStatus.diff(from: [:], to: F.parsed([F.pane: F.entry(state: "waiting")]), includeClaude: false).last)
        #expect(event.source == .orca)
        #expect(event.sessionId == "orca:" + F.pane)
        #expect(event.hostBundleId == OrcaStatus.hostBundleId)
        #expect(event.agent == "Codex")
        #expect(event.context == "agent-pulse")
    }

    @Test func menuTitle() {
        var table = SessionTable()
        for event in OrcaStatus.diff(from: [:], to: F.parsed([F.pane: F.entry(agent: "opencode", state: "working")]), includeClaude: false) {
            table.apply(event)
        }
        #expect(table.ordered.map(BubbleCategory.sessionTitle) == ["OpenCode в Orca · agent-pulse"])

        var claude = SessionInfo(id: "c", source: .claudeCode, at: Date())
        claude.hostBundleId = OrcaStatus.hostBundleId
        claude.context = "agent-pulse"
        #expect(BubbleCategory.sessionTitle(claude) == "Claude Code в Orca · agent-pulse")
        claude.hostBundleId = "com.apple.Terminal"
        #expect(BubbleCategory.sessionTitle(claude) == "Claude Code · agent-pulse")
    }

    @Test func foreignToolNames() {
        #expect(Humanizer.classify(tool: "exec_command").kind == .run)
        #expect(Humanizer.classify(tool: "apply_patch").kind == .edit)
        #expect(Humanizer.classify(tool: "read").kind == .read)
    }

    @Test func bubbleCategory() {
        #expect(BubbleCategory.agent(.orca) == .orca)
        #expect(BubbleCategory.orca.appBundleId == OrcaStatus.hostBundleId)
    }
}

@Suite struct OrcaHostTests {
    @Test func claudeCodeInOrcaSpeaksAsOrca() {
        let orca = OrcaStatus.hostBundleId
        #expect(BubbleCategory.agent(.claudeCode, host: orca) == .orca)
        #expect(BubbleCategory.agentTitle(.claudeCode, host: orca) == "Orca")
        #expect(BubbleCategory.agent(.claudeCode, host: "com.apple.Terminal") == .claude)
        #expect(BubbleCategory.agentTitle(.claudeCode) == "Claude Code")

        let now = Date()
        let story = HoverStory.working(source: .claudeCode, host: orca, phase: .thinking, since: now, steps: 0, now: now)
        #expect(story.category == .orca)
        #expect(story.title == "Orca")

        let task = LastTask(source: .claudeCode, hostBundleId: orca, usedFigma: false, context: "agent-pulse", status: .done, at: now)
        #expect(task.summary(now: now).hasPrefix("Claude Code в Orca · agent-pulse"))
    }
}
