import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ClaudeUsageTransportTests {
    func stub(_ body: String) throws -> (root: URL, executable: String) {
        let root = FileManager.default.temporaryDirectory.appending(path: "pulse-cli-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appending(path: "claude")
        try Data(("#!/bin/sh\n" + body).utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return (root, script.path)
    }
    @Test func nativeControlHandshakeReturnsUsageWithoutUserMessage() async throws {
        let script = try stub(#"""
        IFS= read -r first
        case "$first" in *'"subtype":"initialize"'*) ;; *) exit 1;; esac
        printf '%s\n' '{"type":"control_response","response":{"subtype":"success","request_id":"pulse-init","response":{}}}'
        IFS= read -r second
        case "$second" in *'"subtype":"get_usage"'*) ;; *) exit 1;; esac
        printf '%s' '{"type":"control_response","response":{"subtype":"success","request_id":"pulse-usage",'
        printf '%s\n' '"response":{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":42}}}}}'
        """#)
        defer { try? FileManager.default.removeItem(at: script.root) }
        let snapshot = await ClaudeUsage.fetch(executable: script.executable, timeout: 3)
        #expect(snapshot?.windows.first?.usedPercent == 42)
        #expect(snapshot?.origin == .claudeUsage)
    }
    @Test func silentCLIIsBoundedAndUnsupportedResponseIsNotFresh() async throws {
        let silent = try stub("IFS= read -r line\nIFS= read -r line\n")
        defer { try? FileManager.default.removeItem(at: silent.root) }
        let start = ProcessInfo.processInfo.systemUptime
        let missing = await ClaudeUsage.fetch(executable: silent.executable, timeout: 0.1)
        #expect(missing == nil)
        #expect(ProcessInfo.processInfo.systemUptime - start < 3)
        let failed = try stub(#"""
        IFS= read -r line
        printf '%s\n' '{"type":"control_response","response":{"subtype":"error","request_id":"pulse-init","error":"unsupported"}}'
        """#)
        defer { try? FileManager.default.removeItem(at: failed.root) }
        let unsupported = await ClaudeUsage.fetch(executable: failed.executable, timeout: 3)
        #expect(unsupported == nil)
    }
}
