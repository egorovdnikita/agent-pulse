import AgentPulseCore
import Foundation
import Testing
@testable import AgentPulse

@Suite @MainActor struct TranslationFragmentTests {
    @Test func keepsSurroundingText() throws {
        let model = ConsoleModel(promo: true)
        model.typeTranslation("До Hello после")
        let fragment = try #require(TextFragment(source: model.translateInput, range: NSRange(location: 3, length: 5)))
        model.translateFragment(fragment)
        model.finishTranslate(source: "Hello", result: .success("Привет"))
        #expect(model.translate.state == .done(source: "Hello", result: "До Привет после"))
        #expect(!model.translate.replaceable)
        model.clearTranslation()
    }
    @Test func staleSelectionCannotOverwriteEdits() throws {
        let model = ConsoleModel(promo: true)
        model.typeTranslation("Hello world")
        let fragment = try #require(TextFragment(source: model.translateInput, range: NSRange(location: 0, length: 5)))
        model.typeTranslation("New text")
        model.translateFragment(fragment)
        #expect(model.translateInput == "New text")
        #expect(model.translate.state == .working(source: "New text"))
        model.clearTranslation()
    }
}
