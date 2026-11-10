import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ShelfPinTests {
    @Test func stableGroupsAndHistory() throws {
        let a = URL(fileURLWithPath: "/tmp/a.txt"), b = URL(fileURLWithPath: "/tmp/b.txt")
        var shelf = ShelfModule()
        _ = shelf.add([a, b])
        shelf.pin([a], value: true)
        #expect(shelf.displayItems.map(\.url) == [a, b])
        let data = try JSONEncoder().encode(shelf.items)
        let decoded = try JSONDecoder().decode([ShelfItem].self, from: data)
        #expect(decoded.first?.isPinned == true)
        shelf.pin([a], value: false)
        #expect(shelf.displayItems.map(\.url) == [b, a])
    }
    @Test func relinkToExistingKeepsReplacedPositionAndPin() {
        let urls = ["existing", "middle", "old"].map { URL(fileURLWithPath: "/tmp/" + $0) }
        var shelf = ShelfModule(); _ = shelf.add(urls)
        shelf.pin([urls[0]], value: true)
        let result = shelf.replace(urls[2], with: urls[0])
        #expect(result)
        #expect(shelf.items.map(\.url) == [urls[1], urls[0]])
        #expect(shelf.items.last?.isPinned == true)
    }
    @Test func legacyAndRelinking() throws {
        let old = URL(fileURLWithPath: "/tmp/old.txt"), new = URL(fileURLWithPath: "/tmp/new.txt")
        let data = Data("[{\"url\":\"file:///tmp/old.txt\"}]".utf8)
        #expect(try JSONDecoder().decode([ShelfItem].self, from: data).first?.isPinned == false)
        var shelf = ShelfModule()
        _ = shelf.add([old]); shelf.pin([old], value: true)
        let replaced = shelf.replace(old, with: new)
        #expect(replaced)
        #expect(shelf.items.first?.isPinned == true)
    }
}
