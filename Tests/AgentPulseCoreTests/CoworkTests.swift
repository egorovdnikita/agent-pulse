import Foundation
import Testing
@testable import AgentPulseCore

/// Строки повторяют структуру настоящего `audit.jsonl` Cowork (ключи и типы сняты с журналов на машине автора),
/// текст сообщений заменён.
enum CoworkFixtures {
    static let session = "cw-1"
    static let common = #""session_id": "cw-1", "uuid": "u", "timestamp": "2026-10-11T18:00:00.000Z", "_audit_timestamp": "2026-10-11T18:00:00.001Z", "_audit_hmac": "h""#

    static func line(_ body: String) -> Data {
        Data("{\(body), \(common)}".utf8)
    }

    static let init_ = line(#""type": "system", "subtype": "init", "cwd": "/x/outputs", "tools": ["Bash"], "model": "m""#)
    static let prompt = line(#""type": "user", "parent_tool_use_id": null, "client_platform": "desktop", "message": {"role": "user", "content": "нарисуй экран"}"#)
    static let promptBlocks = line(#""type": "user", "parent_tool_use_id": null, "message": {"role": "user", "content": [{"type": "text", "text": "x"}, {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": ""}}]}"#)
    static let thinking = line(#""type": "system", "subtype": "thinking_tokens", "estimated_tokens": 10, "estimated_tokens_delta": 5"#)
    static let useFigma = line(#""type": "assistant", "parent_tool_use_id": null, "request_id": "r", "message": {"role": "assistant", "content": [{"type": "thinking", "thinking": "", "signature": ""}, {"type": "tool_use", "id": "t1", "name": "mcp__8ece76e0-4474-4af1-aeee-e1b5e92835c3__use_figma", "input": {"code": ""}, "caller": {"type": "direct"}}]}"#)
    static let vmBash = line(#""type": "assistant", "parent_tool_use_id": null, "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t2", "name": "mcp__workspace__bash", "input": {"command": "npm test"}}]}"#)
    static let ask = line(#""type": "assistant", "parent_tool_use_id": null, "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t3", "name": "AskUserQuestion", "input": {}}]}"#)
    static let resultOk = line(#""type": "user", "parent_tool_use_id": null, "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}"#)
    static let resultFail = line(#""type": "user", "parent_tool_use_id": null, "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "is_error": true, "content": "boom"}]}"#)
    static let permissionRequest = line(#""type": "system", "subtype": "permission_request", "tool_name": "Bash", "tool_input": {"command": "swift build"}"#)
    static let permissionGranted = line(#""type": "system", "subtype": "permission_response", "tool_name": "Bash", "decision": "once", "granted": true"#)
    static let permissionDenied = line(#""type": "system", "subtype": "permission_response", "tool_name": "Bash", "decision": "deny", "granted": false"#)
    static let done = line(#""type": "result", "subtype": "success", "is_error": false, "stop_reason": "end_turn", "result": "текст", "num_turns": 3, "duration_ms": 1"#)
    static let failed = line(#""type": "result", "subtype": "error_during_execution", "is_error": true"#)
}

@Suite struct CoworkAuditTests {
    func kinds(_ line: Data) -> [AgentEvent.Kind] {
        CoworkAudit.parse(line: line).map(\.kind)
    }

    @Test func promptsAndNoise() {
        #expect(kinds(CoworkFixtures.prompt) == [.promptSubmitted])
        #expect(kinds(CoworkFixtures.promptBlocks) == [.promptSubmitted])
        #expect(kinds(CoworkFixtures.init_).isEmpty)
        #expect(kinds(CoworkFixtures.thinking).isEmpty)
        // Текст запроса не попадает в событие.
        #expect(CoworkAudit.parse(line: CoworkFixtures.prompt).first?.summary == nil)
    }

    @Test func toolsAreHumanized() throws {
        let figma = try #require(CoworkAudit.parse(line: CoworkFixtures.useFigma).first)
        #expect(figma.kind == .toolStarted)
        #expect(figma.summary == "Рисует в Figma")
        #expect(figma.source == .cowork)
        #expect(figma.hostBundleId == CoworkAudit.hostBundleId)

        let bash = try #require(CoworkAudit.parse(line: CoworkFixtures.vmBash).first)
        #expect(bash.summary == "Запускает тесты")
        #expect(Humanizer.classify(tool: "mcp__workspace__bash").kind == .run)
    }

    @Test func waitingForUser() throws {
        let question = try #require(CoworkAudit.parse(line: CoworkFixtures.ask).first)
        #expect(question.kind == .awaitingUser)
        #expect(question.awaitReason == .input)

        let permission = try #require(CoworkAudit.parse(line: CoworkFixtures.permissionRequest).first)
        #expect(permission.awaitReason == .permission)
        #expect(permission.summary == "Нужно разрешение: Собирает проект")

        #expect(kinds(CoworkFixtures.permissionGranted) == [.toolStarted])
        #expect(kinds(CoworkFixtures.permissionDenied) == [.toolFinished])
    }

    @Test func resultsAndErrors() {
        #expect(CoworkAudit.parse(line: CoworkFixtures.resultOk).first?.isError == false)
        #expect(CoworkAudit.parse(line: CoworkFixtures.resultFail).first?.isError == true)
        #expect(kinds(CoworkFixtures.done) == [.stopped])
        #expect(kinds(CoworkFixtures.failed) == [.error])
    }

    @Test func fullSessionDrivesStateMachine() {
        var table = SessionTable()
        let lines = [
            CoworkFixtures.prompt, CoworkFixtures.useFigma, CoworkFixtures.resultOk,
            CoworkFixtures.permissionRequest,
        ]
        for line in lines {
            for event in CoworkAudit.parse(line: line) { table.apply(event) }
        }
        let session = table.sessions[CoworkFixtures.session]
        #expect(session?.usedFigma == true)
        #expect(session?.phase == .awaitingUser(reason: .permission, message: "Нужно разрешение: Собирает проект"))
        for event in CoworkAudit.parse(line: CoworkFixtures.done) { table.apply(event) }
        #expect(table.sessions[CoworkFixtures.session]?.phase == .done(summary: "Готово"))
    }

    @Test(arguments: [Data(), Data("{".utf8), Data(#"{"type": "user"}"#.utf8), Data(#"{"type": "mystery", "session_id": "x"}"#.utf8)])
    func garbageIsIgnored(_ line: Data) {
        #expect(CoworkAudit.parse(line: line).isEmpty)
    }

    @Test func claudeCodeQuestionIsWaiting() throws {
        let data = Fixtures.hook("PreToolUse", #""tool_name": "AskUserQuestion", "tool_input": {}"#)
        let event = try #require(ClaudeCodeHooks.parse(data))
        #expect(event.kind == .awaitingUser)
        #expect(event.awaitReason == .input)
    }
}

@Suite struct JSONLTailerTests {
    @Test func readsOnlyAppendedCompleteLines() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old\n".utf8).write(to: url)

        var tailer = JSONLTailer()
        tailer.prime(url.path)
        #expect(tailer.readNewLines(url.path).isEmpty)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("one\ntw".utf8))
        #expect(tailer.readNewLines(url.path) == [Data("one".utf8)])
        try handle.write(contentsOf: Data("o\nthree\n".utf8))
        try handle.close()
        #expect(tailer.readNewLines(url.path) == [Data("two".utf8), Data("three".utf8)])

        // Файл перезаписан короче — читаем заново.
        try Data("fresh\n".utf8).write(to: url)
        #expect(tailer.readNewLines(url.path) == [Data("fresh".utf8)])
    }
}

@Suite struct CoworkWatcherTests {
    @Test func newJournalLinesArriveAsEvents() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cowork-\(UUID().uuidString)")
        let sessionDir = root.appending(path: "acc/org/local_old")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = sessionDir.appending(path: CoworkWatcher.journalName)
        // История до запуска не должна проигрываться.
        try (CoworkFixtures.prompt + Data("\n".utf8)).write(to: journal)

        let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
        let watcher = CoworkWatcher(root: root) { events in
            for event in events { continuation.yield(event) }
        }
        #expect(watcher.start())
        defer { watcher.stop() }

        let handle = try FileHandle(forWritingTo: journal)
        try handle.seekToEnd()
        try handle.write(contentsOf: CoworkFixtures.useFigma + Data("\n".utf8))
        try handle.close()

        // Не ждём вечно: если событие не пришло за 3 s, тест падает, а не виснет.
        let timeout = Task {
            try await Task.sleep(for: .seconds(3))
            continuation.finish()
        }
        defer { timeout.cancel() }
        let started = Date()
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.kind == .toolStarted)
        #expect(Date().timeIntervalSince(started) < 1)
    }
}
