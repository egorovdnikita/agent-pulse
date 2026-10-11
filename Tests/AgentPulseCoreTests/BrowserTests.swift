import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct BrowserBridgeTests {
    func message(_ app: String, _ state: String, from: String, session: String = "claude-abc") -> Data {
        Data("PULSE1 bundle=com.google.Chrome channel=browser\n{\"v\":1,\"app\":\"\(app)\",\"session\":\"\(session)\",\"state\":\"\(state)\",\"from\":\"\(from)\"}".utf8)
    }

    func kinds(_ data: Data) -> [AgentEvent.Kind] {
        Ingest.parse(data).map(\.kind)
    }

    @Test func chatLifecycle() {
        #expect(kinds(message("claude", "generating", from: "idle")) == [.promptSubmitted])
        #expect(kinds(message("claude", "approval", from: "generating")) == [.awaitingUser])
        #expect(kinds(message("claude", "generating", from: "approval")) == [.toolFinished])
        #expect(kinds(message("claude", "idle", from: "generating")) == [.stopped])
        #expect(kinds(message("claude", "closed", from: "idle")) == [.sessionEnded])
        #expect(kinds(message("claude", "idle", from: "idle")).isEmpty)

        let event = Ingest.parse(message("claude", "generating", from: "idle")).first
        #expect(event?.source == .claudeChat)
        #expect(event?.hostBundleId == "com.google.Chrome")
        #expect(event?.summary == nil)
    }

    @Test func figmaMakeDraws() {
        var table = SessionTable()
        for event in Ingest.parse(message("figmaMake", "generating", from: "idle", session: "figmaMake-1")) {
            table.apply(event)
        }
        let session = table.sessions["figmaMake-1"]
        guard case .working(let activity) = session?.phase else { Issue.record("ожидали working"); return }
        #expect(activity.target == .figma)
        #expect(activity.kind == .edit)
        #expect(activity.text == "Генерирует в Figma Make")
        #expect(session?.source == .figmaAI)
    }

    @Test func routerKeepsHooksWorking() {
        #expect(Ingest.parse(Fixtures.enveloped(Fixtures.stop, bundle: "com.apple.Terminal")).map(\.kind) == [.stopped])
        #expect(Ingest.parse(Fixtures.stop).map(\.kind) == [.stopped])
        #expect(Ingest.parse(Data("PULSE1 channel=browser\n{\"v\":2}".utf8)).isEmpty)
    }

    @Test func envelope() {
        let envelope = PulseEnvelope(Data("PULSE1 bundle=com.x channel=browser\nbody".utf8))
        #expect(envelope.host == "com.x")
        #expect(envelope.channel == "browser")
        #expect(envelope.body == Data("body".utf8))
        #expect(PulseEnvelope(Data("PULSE1 bundle= \n{}".utf8)).host == nil)
    }
}

@Suite struct BrowserBridgeInstallerTests {
    @Test func writesManifestOnlyForInstalledBrowsers() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nmh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Google/Chrome"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let installed = try BrowserBridgeInstaller.install(hookPath: "/Apps/Agent Pulse.app/pulse-hook", applicationSupport: root)
        #expect(installed.count == 1)
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: installed[0])) as? [String: Any])
        #expect(manifest["name"] as? String == BrowserBridgeInstaller.hostName)
        #expect(manifest["path"] as? String == "/Apps/Agent Pulse.app/pulse-hook")
        #expect(manifest["allowed_origins"] as? [String] == ["chrome-extension://\(BrowserBridgeInstaller.extensionId)/"])
        #expect(BrowserBridgeInstaller.isInstalled(applicationSupport: root))

        try BrowserBridgeInstaller.uninstall(applicationSupport: root)
        #expect(!BrowserBridgeInstaller.isInstalled(applicationSupport: root))
    }

    /// ID в коде должен совпадать с ключом в manifest.json расширения — иначе Chrome не пустит его к мосту.
    @Test func extensionIdMatchesManifestKey() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Extensions/Chrome/manifest.json")
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let encoded = try #require(manifest["key"] as? String)
        let key = try #require(Data(base64Encoded: encoded))
        #expect(ChromeExtensionId.from(publicKey: key) == BrowserBridgeInstaller.extensionId)
    }
}
