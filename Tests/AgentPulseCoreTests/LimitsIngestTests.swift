import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct StatuslineAdapterTests {
    @Test func parsesWindows() throws {
        let body = #"{"five_hour":{"used_percentage":76.4,"resets_at":1800000000},"seven_day":{"used_percentage":12}}"#
        let snapshot = try #require(ClaudeStatusline.parse(Data(body.utf8), now: Date(timeIntervalSince1970: 1)))
        #expect(snapshot.service == .claude)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].usedPercent == 76.4)
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(snapshot.windows[1].resetsAt == nil)
    }

    @Test func emptyBodyIsNoData() {
        #expect(ClaudeStatusline.parse(Data("{}".utf8)) == nil)
        #expect(ClaudeStatusline.parse(Data("мусор".utf8)) == nil)
    }

    @Test func routedByChannel() {
        let message = Data("PULSE1 bundle= channel=statusline\n{\"five_hour\":{\"used_percentage\":5}}".utf8)
        guard case .limits(let snapshot) = Ingest.route(message) else {
            Issue.record("ожидались лимиты")
            return
        }
        #expect(snapshot.windows.first?.usedPercent == 5)
        guard case .events(let events) = Ingest.route(Fixtures.promptSubmitted) else {
            Issue.record("ожидались события")
            return
        }
        #expect(events.count == 1)
    }
}

@Suite struct CodexAppServerTests {
    /// Ответ `account/rateLimits/read`, снятый с настоящего `codex app-server`; id аккаунта заменён.
    static let response = #"""
    {"id":2,"result":{"ordinaryUsageAllowed":true,"rateLimits":{"limitId":"codex","primary":{"usedPercent":3,"windowDurationMins":300,"resetsAt":1794024455},"secondary":{"usedPercent":17,"windowDurationMins":10080,"resetsAt":1794305242},"planType":"plus","rateLimitReachedType":null},"accountId":"00000000-0000-0000-0000-000000000000"}}
    """#

    @Test func parsesRealResponse() throws {
        let snapshot = try #require(CodexAppServer.parse(Data(Self.response.utf8)))
        #expect(snapshot.service == .codex)
        #expect(snapshot.windows.map(\.kind) == [.fiveHour, .week])
        #expect(snapshot.windows.map(\.usedPercent) == [3, 17])
    }

    @Test func windowsComeFromDurationNotFromName() throws {
        let swapped = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":9,"windowDurationMins":10080},"secondary":{"usedPercent":1,"windowDurationMins":300}}}}"#
        let snapshot = try #require(CodexAppServer.parse(Data(swapped.utf8)))
        #expect(snapshot.windows.first?.kind == .week)
    }

    @Test func unknownWindowIsSkipped() {
        let monthly = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":9,"windowDurationMins":43200}}}}"#
        #expect(CodexAppServer.parse(Data(monthly.utf8)) == nil)
    }

    @Test func otherResponsesAreIgnored() {
        #expect(CodexAppServer.parse(Data(#"{"id":1,"result":{}}"#.utf8)) == nil)
        #expect(CodexAppServer.parse(Data(#"{"id":2,"error":{"code":-32600}}"#.utf8)) == nil)
    }

    @Test func accountHomeIsExplicit() {
        let base = ["PATH": "/usr/bin", "CODEX_HOME": "/leftover"]
        let own = CodexAppServer.environment(codex: "/usr/bin/true", home: "/custom", base: base)
        #expect(own["CODEX_HOME"] == "/custom")
        #expect(own["PATH"]?.contains("/opt/homebrew/bin") == true)
        // Чужой CODEX_HOME из окружения не наследуется: показали бы лимиты не того аккаунта.
        #expect(CodexAppServer.environment(codex: "/usr/bin/true", home: nil, base: base)["CODEX_HOME"] == nil)
    }

    @Test func neverAsksForAccount() {
        #expect(![CodexAppServer.initialize, CodexAppServer.initialized, CodexAppServer.readLimits].contains { $0.contains("account/read") })
    }
}

@Suite struct RateLimitStopTests {
    @Test func rateLimitIsNotAnError() throws {
        let event = try #require(ClaudeCodeHooks.parse(Fixtures.hook("StopFailure", #""error": "rate_limit""#)))
        #expect(event.kind == .rateLimited)
        #expect(MascotStateMapper.reaction(for: event) == nil)
    }

    @Test func otherFailuresStayErrors() throws {
        let event = try #require(ClaudeCodeHooks.parse(Fixtures.hook("StopFailure", #""error": "server_error""#)))
        #expect(event.kind == .error)
    }

    @Test func hooksSubscribeToStopFailure() {
        #expect(HookInstaller.events.contains("StopFailure"))
        let old = HookInstaller.installing(into: [:], command: "x/pulse-hook")
        var stale = old
        var hooks = stale["hooks"] as! [String: Any]
        hooks["StopFailure"] = nil
        stale["hooks"] = hooks
        #expect(HookInstaller.needsUpdate(stale, command: "x/pulse-hook"))
    }

    private func session(_ phase: Phase, _ id: String, at date: Date = Date()) -> SessionInfo {
        SessionInfo(id: id, source: .claudeCode, phase: phase, at: date)
    }

    @Test func restingSessionSleepsAloneButYieldsToOthers() {
        let now = Date()
        let activity = Activity(tool: "Read", kind: .read, target: .code, text: "x")
        #expect(MascotStateMapper.state(for: [session(.resting, "a")], now: now, sleepAfter: 1000) == .sleep)
        #expect(MascotStateMapper.state(for: [session(.resting, "a"), session(.idle, "b")], now: now, sleepAfter: 1000) == .sleep)
        #expect(MascotStateMapper.state(for: [session(.resting, "a"), session(.working(activity), "b")], now: now, sleepAfter: 1000) == .work(.read))
        #expect(MascotStateMapper.state(for: [session(.resting, "a"), session(.awaitingUser(reason: .input, message: ""), "b")], now: now, sleepAfter: 1000) == .waitYou(.input))
    }

    @Test func snapshotFailureDoesNotOverrideRest() {
        var table = SessionTable()
        let now = Date()
        table.apply(AgentEvent(source: .claudeCode, sessionId: "s", kind: .rateLimited, ts: now))
        table.apply(AgentEvent(source: .claudeCode, sessionId: "s", kind: .error, summary: "Ошибка", ts: now))
        #expect(table.sessions["s"]?.phase == .resting)
        table.apply(AgentEvent(source: .claudeCode, sessionId: "s", kind: .promptSubmitted, ts: now))
        #expect(table.sessions["s"]?.phase == .received)
    }

    @Test func restEndsWithTime() {
        var table = SessionTable()
        let now = Date()
        table.apply(AgentEvent(source: .claudeCode, sessionId: "s", kind: .rateLimited, ts: now))
        table.tick(now: now.addingTimeInterval(5 * 3600 + 1))
        #expect(table.sessions["s"]?.phase == .idle)
    }
}

@Suite struct StatuslineInstallerTests {
    let wrapper = "/Applications/Agent Pulse.app/Contents/MacOS/pulse-statusline"
    let orca = "/bin/sh \"${HOME-}/.orca/agent-hooks/claude-statusline.sh\""

    @Test func keepsOriginalHiddenFromOrca() throws {
        let settings: [String: Any] = ["statusLine": ["type": "command", "command": orca, "padding": 1], "theme": "dark"]
        let installed = try StatuslineInstaller.installing(into: settings, wrapperPath: wrapper)
        let command = try #require(StatuslineInstaller.currentCommand(installed))
        // Orca затирает команду, в тексте которой видит свой путь.
        #expect(!command.contains("agent-hooks/claude-statusline.sh"))
        #expect(StatuslineInstaller.original(from: command) == orca)
        #expect((installed["statusLine"] as? [String: Any])?["padding"] as? Int == 1)
        #expect(installed["theme"] as? String == "dark")
    }

    @Test func uninstallRestoresExactly() throws {
        let settings: [String: Any] = ["statusLine": ["type": "command", "command": orca]]
        let installed = try StatuslineInstaller.installing(into: settings, wrapperPath: wrapper)
        #expect(StatuslineInstaller.currentCommand(StatuslineInstaller.removing(from: installed)) == orca)
    }

    @Test func noOriginalLeavesNoTrace() throws {
        let installed = try StatuslineInstaller.installing(into: [:], wrapperPath: wrapper)
        #expect(StatuslineInstaller.isInstalled(installed))
        #expect(StatuslineInstaller.removing(from: installed)["statusLine"] == nil)
    }

    @Test func secondInstallDoesNotWrapTwice() throws {
        let settings: [String: Any] = ["statusLine": ["type": "command", "command": orca]]
        let once = try StatuslineInstaller.installing(into: settings, wrapperPath: wrapper)
        let twice = try StatuslineInstaller.installing(into: once, wrapperPath: wrapper)
        #expect(StatuslineInstaller.currentCommand(twice) == StatuslineInstaller.currentCommand(once))
    }

    @Test func movedAppIsDetected() throws {
        let installed = try StatuslineInstaller.installing(into: [:], wrapperPath: wrapper)
        #expect(!StatuslineInstaller.needsUpdate(installed, wrapperPath: wrapper))
        #expect(StatuslineInstaller.needsUpdate(installed, wrapperPath: "/elsewhere/pulse-statusline"))
    }

    @Test func refusesNonCommand() {
        #expect(throws: StatuslineInstaller.Failure.self) {
            try StatuslineInstaller.installing(into: ["statusLine": ["type": "static"]], wrapperPath: wrapper)
        }
    }

    @Test func foreignCommandIsNotOurs() {
        #expect(!StatuslineInstaller.isOurs(orca))
        #expect(StatuslineInstaller.removing(from: ["statusLine": ["command": orca]])["statusLine"] != nil)
    }

    private func shell(_ command: String, stdin: String) throws -> String {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    /// Удалили приложение: statusline пользователя работает, stdin доходит до неё целиком.
    @Test func withoutWrapperOriginalStillRuns() throws {
        let command = StatuslineInstaller.command(wrapperPath: "/нет/такого/pulse-statusline", original: "printf 'ok:'; cat")
        #expect(try shell(command, stdin: "{\"a\":1}") == "ok:{\"a\":1}")
    }

    @Test func withoutWrapperAndOriginalIsSilent() throws {
        let command = StatuslineInstaller.command(wrapperPath: "/нет/такого/pulse-statusline", original: nil)
        #expect(try shell(command, stdin: "{}") == "")
    }

    @Test func wrapperPathWithApostropheIsQuoted() throws {
        let command = StatuslineInstaller.command(wrapperPath: "/Users/o'neil/pulse-statusline", original: "printf ok")
        #expect(try shell(command, stdin: "") == "ok")
    }
}

@Suite struct ConsoleConfigTests {
    @Test func oldConfigGetsDefaults() {
        let config = PulseConfig.decode(Data(#"{"version":1}"#.utf8))
        #expect(config.console.enabled)
        #expect(config.console.limits)
        #expect(config.console.hotkey == "x")
    }
}
