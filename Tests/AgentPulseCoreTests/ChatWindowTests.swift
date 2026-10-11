import Testing
@testable import AgentPulseCore

@Suite struct ChatWindowSignalsTests {
    @Test func labels() {
        #expect(ChatWindowSignals.isStop("Stop response"))
        #expect(ChatWindowSignals.isStop(" Остановить ответ "))
        #expect(!ChatWindowSignals.isStop("Stop sharing"))
        #expect(!ChatWindowSignals.isStop("Stop"))
        #expect(ChatWindowSignals.isStop("Остановить", onChat: true))
        #expect(ChatWindowSignals.isSend("Send message"))
        #expect(ChatWindowSignals.isApproval("Allow once"))
        #expect(ChatWindowSignals.isApproval("Разрешить всегда"))
        #expect(!ChatWindowSignals.isApproval("Allowance report for the whole quarter of the year 2026"))
    }

    @Test func state() {
        #expect(ChatWindowSignals.state(buttonLabels: ["Attach", "Stop response"], approvalVisible: false) == .generating)
        #expect(ChatWindowSignals.state(buttonLabels: ["Attach", "Send message"], approvalVisible: false) == .idle)
        #expect(ChatWindowSignals.state(buttonLabels: ["Stop response"], approvalVisible: true) == .approval)
    }

    @Test func pagesAndSessions() {
        #expect(ChatWindowSignals.isChatPage("https://claude.ai/chat/abc"))
        #expect(ChatWindowSignals.isChatPage("https://claude.ai/new"))
        #expect(!ChatWindowSignals.isChatPage(nil))
        #expect(!ChatWindowSignals.isChatPage("https://claude.ai/epitaxy/local_e082"))
        #expect(!ChatWindowSignals.isChatPage("file:///Applications/Claude.app/index.html"))
        #expect(!ChatWindowSignals.isChatPage("https://claude.ai/code/session_1"))
        #expect(!ChatWindowSignals.isChatPage("https://claude.ai/task/xyz"))
        #expect(ChatWindowSignals.sessionId("https://claude.ai/chat/abc-123") == "desktop-chat-abc-123")
        #expect(ChatWindowSignals.sessionId("https://claude.ai/new") == "desktop-chat")
    }

    @Test func transitionsReuseBrowserMapping() {
        let start = BrowserBridge.events(source: .claudeChat, session: "s", state: "generating", from: "idle", host: ChatWindowSignals.hostBundleId)
        #expect(start.map(\.kind) == [.promptSubmitted])
        #expect(start.first?.hostBundleId == "com.anthropic.claudefordesktop")
        #expect(BrowserBridge.events(source: .claudeChat, session: "s", state: "idle", from: "generating", host: nil).map(\.kind) == [.stopped])
    }
}
