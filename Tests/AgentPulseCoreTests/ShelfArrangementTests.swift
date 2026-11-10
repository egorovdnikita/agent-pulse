import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ShelfArrangementTests {
    let urls = ["c.txt", "b.pdf", "a.md"].map { URL(fileURLWithPath: "/tmp/" + $0) }
    @Test func sortNames() {
        var shelf = ShelfModule(); _ = shelf.add(urls)
        shelf.sort(.name)
        #expect(shelf.displayItems.map(\.name) == ["a.md", "b.pdf", "c.txt"])
        shelf.sort(.kind)
        #expect(shelf.displayItems.map(\.name) == ["a.md", "b.pdf", "c.txt"])
        shelf.sort(.added)
        #expect(shelf.displayItems.map(\.url) == Array(urls.reversed()))
    }
    @Test func reorderWithinPinGroup() {
        var shelf = ShelfModule(); _ = shelf.add(urls)
        shelf.move([urls[0]], before: urls[2])
        #expect(shelf.displayItems.map(\.url) == [urls[0], urls[2], urls[1]])
        shelf.pin([urls[1]], value: true)
        let saved = shelf.items
        shelf.move([urls[0]], before: urls[1])
        #expect(shelf.items == saved)
        shelf.move([urls[0]], before: urls[0])
        #expect(shelf.items == saved)
    }
}
