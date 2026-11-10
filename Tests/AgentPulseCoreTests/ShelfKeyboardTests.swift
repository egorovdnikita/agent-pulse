import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ShelfKeyboardTests {
    let order = (0..<16).map { URL(filePath: "/tmp/pulse-keyboard-\($0).txt") }
    @Test func movesAcrossRowsAndClampsAtEdges() {
        var selection = ShelfSelection()
        selection.move(by: 1, order: order)
        #expect(selection.urls == [order[0]])
        selection.move(by: 7, order: order)
        #expect(selection.urls == [order[7]])
        selection.move(by: 100, order: order)
        #expect(selection.urls == [order[15]])
        selection.move(by: -100, order: order)
        #expect(selection.urls == [order[0]])
        selection.move(by: 1, order: [])
        #expect(selection.urls == [order[0]])
    }
    @Test func shiftExtendsAndShrinksFromAnchor() {
        var selection = ShelfSelection()
        selection.click(order[3], order: order)
        selection.move(by: 7, order: order, extending: true)
        #expect(selection.urls == Set(order[3...10]))
        selection.move(by: -1, order: order, extending: true)
        #expect(selection.urls == Set(order[3...9]))
        selection.move(by: 1, order: order)
        #expect(selection.urls == [order[10]])
    }
}
