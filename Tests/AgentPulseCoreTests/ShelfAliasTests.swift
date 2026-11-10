import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ShelfAliasTests {
    @Test func symlinkAndCanonicalFileDoNotDuplicateShelf() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("original.txt"), alias = root.appendingPathComponent("alias.txt")
        try Data("Пример".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
        var shelf = ShelfModule(); _ = shelf.add([file, alias])
        #expect(shelf.items.map(\.url) == [file])
        var pinnedAlias = ShelfItem(url: alias); pinnedAlias.setPinned(true)
        shelf.restore([ShelfItem(url: file), pinnedAlias])
        #expect(shelf.items.count == 1)
        #expect(shelf.items.first?.isPinned == true)
    }
    @Test func webAddressesAreNotFiles() {
        var shelf = ShelfModule()
        _ = shelf.add([URL(string: "https://example.com/report.txt")!])
        #expect(shelf.items.isEmpty)
    }
}
