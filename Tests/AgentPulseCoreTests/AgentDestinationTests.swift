import Testing
@testable import AgentPulseCore

@Suite struct AgentDestinationTests {
    @Test func opensOnlyRecognizedConversationIDs() {
        let id = "11111111-2222-4333-8444-555555555555"
        #expect(AgentDestination.webURL(source: .claudeChat, sessionID: "claude-" + id)?.absoluteString == "https://claude.ai/chat/" + id)
        #expect(AgentDestination.webURL(source: .figmaAI, sessionID: "figmaMake-Abcd1234_Efgh")?.absoluteString == "https://www.figma.com/make/Abcd1234_Efgh")
        #expect(AgentDestination.webURL(source: .claudeChat, sessionID: "claude-tab") == nil)
        #expect(AgentDestination.webURL(source: .figmaAI, sessionID: "figmaMake-../../private") == nil)
        #expect(AgentDestination.webURL(source: .codex, sessionID: "claude-" + id) == nil)
    }
}
