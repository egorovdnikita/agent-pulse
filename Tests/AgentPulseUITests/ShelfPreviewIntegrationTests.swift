import AgentPulseCore
import AppKit
import Testing
@testable import AgentPulse

@Suite @MainActor struct ShelfPreviewIntegrationTests {
    @Test func previewContainsAllAvailableFilesStartingAtSelection() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = ["a.txt", "missing.txt", "b.txt"].map { root.appendingPathComponent($0) }
        try Data("Пример".utf8).write(to: urls[0]); try Data("Пример".utf8).write(to: urls[2])
        let model = ConsoleModel(promo: true)
        model.addToShelf(urls); model.clickShelf(urls[0], flags: [])
        var captured: [URL] = []; var index = -1; var toggle = false
        model.onShelfPreview = { captured = $0; index = $1; toggle = $2 }
        model.previewShelfFiles()
        #expect(captured == [urls[2], urls[0]])
        #expect(index == 1)
        #expect(toggle)
        model.previewShelfFiles(from: urls[2])
        #expect(index == 0)
        #expect(!toggle)
    }
}
