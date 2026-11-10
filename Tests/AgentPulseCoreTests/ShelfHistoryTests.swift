import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ShelfHistoryTests {
    let a = ShelfItem(url: URL(filePath: "/tmp/pulse-undo-a.txt"))
    let b = ShelfItem(url: URL(filePath: "/tmp/pulse-undo-b.txt"))
    @Test func undoAndRedoPreserveOrderAndNewEditDropsRedo() {
        var history = ShelfHistory()
        history.record([a, b])
        #expect(history.undo(current: [b]) == [a, b])
        #expect(history.redo(current: [a, b]) == [b])
        #expect(history.undo(current: [b]) == [a, b])
        history.record([a, b])
        #expect(!history.canRedo)
    }
    @Test func emptyAndBoundedHistory() {
        var history = ShelfHistory()
        #expect(history.undo(current: []) == nil)
        for index in 0..<30 { history.record([ShelfItem(url: URL(filePath: "/tmp/pulse-undo-\(index)"))]) }
        var count = 0
        while history.undo(current: []) != nil { count += 1 }
        #expect(count == ShelfHistory.capacity)
    }
}
