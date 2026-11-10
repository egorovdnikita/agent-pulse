import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ShelfPersistenceTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "pulse-shelf-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func savedReferenceCanBeUsedAgainAfterRestart() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appending(path: "original.txt"), storage = root.appending(path: "shelf.json")
        let contents = Data("Повторное использование файла".utf8)
        try contents.write(to: original)
        var shelf = ShelfModule()
        _ = shelf.add([original])
        try shelf.save(to: storage)
        for index in 1...2 {
            let restored = ShelfModule.load(from: storage)
            let item = try #require(restored.items.first)
            let copy = root.appending(path: "copy-\(index).txt")
            try FileManager.default.copyItem(at: item.url, to: copy)
            #expect(try Data(contentsOf: copy) == contents)
            #expect(restored.items.map(\.url) == [original])
        }
        #expect(try Data(contentsOf: original) == contents)
    }

    @Test func removalAndClearPersistWithoutDeletingOriginals() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appending(path: "a.txt"), b = root.appending(path: "b.txt")
        let storage = root.appending(path: "shelf.json")
        try Data("A".utf8).write(to: a)
        try Data("B".utf8).write(to: b)
        var shelf = ShelfModule()
        _ = shelf.add([a, b])
        try shelf.save(to: storage)
        shelf.remove(a)
        try shelf.save(to: storage)
        #expect(ShelfModule.load(from: storage).items.map(\.url) == [b])
        shelf.clear()
        try shelf.save(to: storage)
        #expect(ShelfModule.load(from: storage).items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: b.path))
    }

    @Test func restoreKeepsOrderCapacityAndTemporarilyUnavailableFiles() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appending(path: "shelf.json")
        let urls = (0..<25).map { root.appending(path: "missing-\($0).pdf") }
        let input = [try #require(URL(string: "https://example.com/file.pdf"))] + [urls[0]] + urls
        try JSONEncoder().encode(input).write(to: storage)
        let restored = ShelfModule.load(from: storage)
        #expect(restored.items.map(\.url) == Array(urls.prefix(ShelfModule.capacity)))
    }

    @Test func absentOrCorruptStorageDoesNotPreventLaunch() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appending(path: "shelf.json")
        #expect(ShelfModule.load(from: storage).items.isEmpty)
        try Data("not json".utf8).write(to: storage)
        #expect(ShelfModule.load(from: storage).items.isEmpty)
    }

    @Test func savedFileIsPrivateAndCreatesItsDirectory() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appending(path: "nested/shelf.json")
        try ShelfModule().save(to: storage)
        let attributes = try FileManager.default.attributesOfItem(atPath: storage.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
