import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ShelfArrangementPersistenceTests {
    @Test func renamedPinnedFileKeepsOrderAndAdditionDate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.txt"), second = root.appendingPathComponent("second.txt")
        let renamed = root.appendingPathComponent("renamed.txt"), store = root.appendingPathComponent("shelf.json")
        try Data("Первый".utf8).write(to: first); try Data("Второй".utf8).write(to: second)
        var shelf = ShelfModule(); _ = shelf.add([first, second])
        shelf.pin([first], value: true)
        let date = try #require(shelf.items.first?.addedAt)
        try shelf.save(to: store)
        try FileManager.default.moveItem(at: first, to: renamed)
        let loaded = ShelfModule.load(from: store)
        #expect(loaded.displayItems.map { $0.url.resolvingSymlinksInPath() } == [renamed, second].map { $0.resolvingSymlinksInPath() })
        #expect(loaded.displayItems.first?.isPinned == true)
        #expect(loaded.displayItems.first?.addedAt == date)
    }
}
