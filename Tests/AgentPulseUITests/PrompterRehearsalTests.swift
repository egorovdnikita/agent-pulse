import AgentPulseCore
import Foundation
import Testing
@testable import AgentPulse

@Suite @MainActor struct PrompterRehearsalTests {
    @Test func keepsDraftAndResumePoint() throws {
        let model = ConsoleModel(promo: true)
        let original = "Один два три четыре пять шесть семь восемь девять десять"
        model.preparePromoResume(text: original, position: 3)
        let range = (original as NSString).range(of: "пять шесть")
        model.rehearsePrompter(try #require(TextFragment(source: original, range: range)))
        #expect(model.prompterRehearsing)
        #expect(model.prompter.script.text == "пять шесть")
        #expect(model.prompterDraft == original)
        #expect(model.prompterLibrary.texts.isEmpty)
        model.stopPrompter()
        #expect(!model.prompterRehearsing)
        #expect(model.canResumePrompter)
    }
}
