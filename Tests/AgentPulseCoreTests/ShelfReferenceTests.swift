import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ShelfReferenceTests {
    @Test func bookmarkFindsRenamedFile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appending(path: "before.txt"), renamed = root.appending(path: "after.txt")
        try Data("Пример".utf8).write(to: original)
        let item = ShelfItem(url: original)
        try FileManager.default.moveItem(at: original, to: renamed)
        let restored = try JSONDecoder().decode(ShelfItem.self, from: JSONEncoder().encode(item))
        #expect(restored.resolvingReference().url.resolvingSymlinksInPath() == renamed.resolvingSymlinksInPath())
    }
    @Test func missingFileKeepsReference() throws {
        let url = URL(filePath: "/tmp/pulse-missing-\(UUID().uuidString)")
        let item = ShelfItem(url: url)
        #expect(item.resolvingReference().url == url)
        #expect(try JSONDecoder().decode(ShelfItem.self, from: JSONEncoder().encode(item)).url == url)
    }
    @Test func storageMigratesOldURLsAndPersistsBookmarks() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appending(path: "original.txt"), moved = root.appending(path: "moved.txt")
        let storage = root.appending(path: "shelf.json")
        try Data("Пример".utf8).write(to: original)
        try JSONEncoder().encode([original]).write(to: storage)
        let shelf = ShelfModule.load(from: storage)
        #expect(shelf.items.map(\.url) == [original])
        try shelf.save(to: storage)
        try FileManager.default.moveItem(at: original, to: moved)
        #expect(ShelfModule.load(from: storage).items.first?.url.resolvingSymlinksInPath() == moved.resolvingSymlinksInPath())
    }

    @Test func relinkPreservesPositionAndMergesDuplicates() {
        var shelf = ShelfModule()
        let urls = (0..<3).map { URL(filePath: "/tmp/pulse-relink-\($0)") }
        _ = shelf.add(urls)
        let replacement = URL(filePath: "/tmp/pulse-relinked")
        let replaced = shelf.replace(urls[1], with: replacement)
        #expect(replaced)
        #expect(shelf.items.map(\.url) == [urls[0], replacement, urls[2]])
        let merged = shelf.replace(replacement, with: urls[0])
        #expect(merged)
        #expect(shelf.items.map(\.url) == [urls[0], urls[2]])
        let missing = shelf.replace(replacement, with: urls[1])
        #expect(!missing)
    }

}
