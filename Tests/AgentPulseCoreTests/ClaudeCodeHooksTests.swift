import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ClaudeCodeHooksTests {
    @Test func promptSubmittedDoesNotLeakPromptText() throws {
        let event = try #require(ClaudeCodeHooks.parse(Fixtures.promptSubmitted))
        #expect(event.kind == .promptSubmitted)
        #expect(event.sessionId == Fixtures.sessionId)
        #expect(event.context == "agent-pulse")
        #expect(event.summary == nil)
    }

    @Test func preToolUseIsHumanized() throws {
        let read = try #require(ClaudeCodeHooks.parse(Fixtures.preToolRead))
        #expect(read.kind == .toolStarted)
        #expect(read.tool == "Read")
        #expect(read.summary == "Читает Package.swift")

        let bash = try #require(ClaudeCodeHooks.parse(Fixtures.preToolBashTests))
        #expect(bash.summary == "Запускает тесты")

        let figma = try #require(ClaudeCodeHooks.parse(Fixtures.preToolFigmaWrite))
        #expect(figma.summary == "Рисует в Figma")
    }

    @Test func postToolUseDetectsErrors() throws {
        #expect(try #require(ClaudeCodeHooks.parse(Fixtures.postToolOk)).isError == false)
        let failed = try #require(ClaudeCodeHooks.parse(Fixtures.postToolError))
        #expect(failed.kind == .toolFinished)
        #expect(failed.isError)
    }

    @Test func notificationsMapToAwaitReason() throws {
        #expect(try #require(ClaudeCodeHooks.parse(Fixtures.notificationPermission)).awaitReason == .permission)
        #expect(try #require(ClaudeCodeHooks.parse(Fixtures.notificationIdle)).awaitReason == .input)
        // Старые версии без notification_type — по тексту сообщения.
        #expect(try #require(ClaudeCodeHooks.parse(Fixtures.notificationLegacyPermission)).awaitReason == .permission)
        // Уведомление, которое не про ожидание, игнорируем.
        #expect(ClaudeCodeHooks.parse(Fixtures.notificationAuth) == nil)
    }

    @Test func lifecycleEvents() {
        #expect(ClaudeCodeHooks.parse(Fixtures.subagentStop)?.kind == .subtaskDone)
        #expect(ClaudeCodeHooks.parse(Fixtures.stop)?.kind == .stopped)
        #expect(ClaudeCodeHooks.parse(Fixtures.sessionEnd)?.kind == .sessionEnded)
    }

    @Test func envelopeCarriesHostBundle() throws {
        let event = try #require(ClaudeCodeHooks.parse(Fixtures.enveloped(Fixtures.stop, bundle: "com.apple.Terminal")))
        #expect(event.hostBundleId == "com.apple.Terminal")
        #expect(event.kind == .stopped)

        let empty = try #require(ClaudeCodeHooks.parse(Fixtures.enveloped(Fixtures.stop, bundle: "")))
        #expect(empty.hostBundleId == nil)
    }

    @Test(arguments: [
        Data(),
        Data("not json".utf8),
        Data(#"{"hook_event_name": "Stop"}"#.utf8),
        Data(#"{"session_id": "x", "hook_event_name": "SomethingNew"}"#.utf8),
        Data("PULSE1 bundle=x\n".utf8),
    ])
    func malformedInputIsDropped(_ data: Data) {
        #expect(ClaudeCodeHooks.parse(data) == nil)
    }
}
