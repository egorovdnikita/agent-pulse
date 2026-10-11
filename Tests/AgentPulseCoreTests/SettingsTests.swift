import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct HookInstallerTests {
    let command = "\"/Applications/AgentPulse.app/Contents/MacOS/pulse-hook\""

    var foreign: [String: Any] {
        [
            "model": "opus",
            "hooks": [
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "my-guard.sh"]]]],
                "Stop": [["hooks": [["type": "command", "command": "say done"]]]],
            ],
        ]
    }

    func json(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    func ourCount(_ settings: [String: Any], event: String) -> Int {
        let groups = (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { $0["hooks"] as? [Any] ?? [] }.filter(HookInstaller.isOurs).count
    }

    @Test func installKeepsForeignHooksAndIsIdempotent() throws {
        let once = HookInstaller.installing(into: foreign, command: command)
        let twice = HookInstaller.installing(into: once, command: command)
        #expect(try json(once) == json(twice))
        #expect(once["model"] as? String == "opus")
        for event in HookInstaller.events {
            #expect(ourCount(twice, event: event) == 1, "\(event)")
        }
        let preTool = (once["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        #expect(preTool?.count == 2)
        #expect(preTool?.first?["matcher"] as? String == "Bash")
        #expect(HookInstaller.isInstalled(once))
    }

    @Test func uninstallIsCleanRollback() throws {
        let installed = HookInstaller.installing(into: foreign, command: command)
        #expect(try json(HookInstaller.removing(from: installed)) == json(foreign))
        #expect(!HookInstaller.isInstalled(foreign))

        let fromEmpty = HookInstaller.installing(into: [:], command: command)
        #expect(try json(HookInstaller.removing(from: fromEmpty)) == "{}")
    }

    @Test func removingLeavesUntouchedFileAlone() throws {
        let odd: [String: Any] = ["hooks": ["Stop": [] as [Any]]]
        #expect(try json(HookInstaller.removing(from: odd)) == json(odd))
    }

    @Test func fileInstallMakesBackupAndRefusesBrokenJSON() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "agentpulse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = directory.appending(path: "settings.json")

        // Нет файла — создаём, бэкапа нет.
        #expect(try HookInstaller.install(command: command, settingsURL: settings) == nil)
        #expect(HookInstaller.isInstalled(settingsURL: settings))

        let backup = try #require(try HookInstaller.uninstall(settingsURL: settings))
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(!HookInstaller.isInstalled(settingsURL: settings))

        try Data("{ broken".utf8).write(to: settings)
        #expect(throws: HookInstaller.Failure.self) {
            try HookInstaller.install(command: command, settingsURL: settings)
        }
        #expect(try String(contentsOf: settings, encoding: .utf8) == "{ broken")
    }
}

@Suite struct PulseConfigTests {
    @Test func partialConfigFallsBackToDefaults() {
        let config = PulseConfig.decode(Data(#"{"display": {"anchor": "bottom-left"}, "unknown": 1}"#.utf8))
        #expect(config.display.anchor == .bottomLeft)
        #expect(config.display.mascotSize == 48)
        #expect(config.events.awaitingUser.sound == "soft")
        #expect(config.privacy.showPromptText == false)
    }

    @Test func brokenConfigGivesDefaults() {
        #expect(PulseConfig.decode(Data("nope".utf8)) == PulseConfig())
    }
}

@Suite struct SocketServerTests {
    @Test func receivesOneMessagePerConnection() async throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "ap-\(UUID().uuidString.prefix(8)).sock").path
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        let server = SocketServer(path: path) { continuation.yield($0) }
        try server.start()
        defer { server.stop() }

        let payload = Fixtures.enveloped(Fixtures.stop, bundle: "com.apple.Terminal")
        try send(payload, to: path)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == payload)
        #expect(received.flatMap { ClaudeCodeHooks.parse($0) }?.hostBundleId == "com.apple.Terminal")
    }

    private func send(_ data: Data, to path: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            path.utf8CString.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(connected == 0)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }
}

@Suite struct InstallRepairTests {
    @Test func hooksPointingElsewhereNeedUpdate() {
        let old = HookInstaller.installing(into: [:], command: "\"/old/pulse-hook\"")
        #expect(HookInstaller.needsUpdate(old, command: "\"/new/pulse-hook\""))
        #expect(!HookInstaller.needsUpdate(old, command: "\"/old/pulse-hook\""))
        // Не установлены — чинить нечего.
        #expect(!HookInstaller.needsUpdate([:], command: "\"/new/pulse-hook\""))
        // Кто-то удалил часть событий — восстановим.
        var partial = old
        var hooks = partial["hooks"] as! [String: Any]
        hooks["Stop"] = nil
        partial["hooks"] = hooks
        #expect(HookInstaller.needsUpdate(partial, command: "\"/old/pulse-hook\""))
    }

    @Test func bridgePointingElsewhereNeedsUpdate() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nmh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Google/Chrome"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try BrowserBridgeInstaller.install(hookPath: "/old/pulse-hook", applicationSupport: root)
        #expect(BrowserBridgeInstaller.needsUpdate(hookPath: "/new/pulse-hook", applicationSupport: root))
        #expect(!BrowserBridgeInstaller.needsUpdate(hookPath: "/old/pulse-hook", applicationSupport: root))
    }
}
