import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ShelfFileStateTests {
    @Test func detectsRewriteAndRemoval() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!ShelfFileState.read(url).available)
        try Data("a".utf8).write(to: url)
        let first = ShelfFileState.read(url)
        #expect(first.available)
        try Data("longer".utf8).write(to: url)
        #expect(ShelfFileState.read(url) != first)
        try FileManager.default.removeItem(at: url)
        #expect(!ShelfFileState.read(url).available)
    }
}
