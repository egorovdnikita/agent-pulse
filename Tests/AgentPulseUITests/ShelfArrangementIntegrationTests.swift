import AgentPulseCore
import AppKit
import Testing
@testable import AgentPulse

@Suite @MainActor struct ShelfArrangementIntegrationTests {
    @Test func arrangementHistoryAndSelectionUseSameOrder() {
        _ = NSApplication.shared
        let model = ConsoleModel(promo: true)
        let urls = ["c.txt", "a.txt", "b.txt"].map { URL(fileURLWithPath: "/tmp/pulse-example/" + $0) }
        model.addToShelf(urls)
        model.clickShelf(urls[0], flags: [])
        model.pinShelfFiles(from: urls[0])
        #expect(model.shelfOrder.first == urls[0])
        model.sortShelf(.name)
        #expect(model.shelfOrder == [urls[0], urls[1], urls[2]])
        model.undoShelf()
        #expect(model.shelfOrder == [urls[0], urls[2], urls[1]])
        model.undoShelf()
        #expect(model.shelfOrder == Array(urls.reversed()))
        model.redoShelf()
        #expect(model.shelfOrder.first == urls[0])
        #expect(model.shelfSelection.contains(urls[0]))
    }
    @Test func mixedPinActionMatchesActualChange() {
        let model = ConsoleModel(promo: true)
        let urls = ["a", "b"].map { URL(fileURLWithPath: "/tmp/pulse-example/" + $0) }
        model.addToShelf(urls); model.pinShelfFiles(from: urls[0]); model.selectAllShelf()
        #expect(model.shelfPinActionTitle(from: urls[0]) == "Закрепить")
        model.pinShelfFiles(from: urls[0])
        #expect(model.shelf.items.allSatisfy(\.isPinned))
        #expect(model.shelfPinActionTitle(from: urls[1]) == "Открепить")
    }
    @Test func searchingFollowsVisibleOrderAndResetsAfterArrow() {
        let model = ConsoleModel(promo: true)
        let urls = ["Доклад.md", "Договор.pdf", "Файл.txt"].map { URL(fileURLWithPath: "/tmp/pulse-example/" + $0) }
        model.addToShelf(urls)
        _ = model.searchShelf("До")
        #expect(model.shelfSelection.focused == urls[1])
        model.moveShelfSelection(by: 1, extending: false)
        _ = model.searchShelf("Файл")
        #expect(model.shelfSelection.focused == urls[2])
    }
}
