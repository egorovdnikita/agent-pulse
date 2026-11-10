import Testing
@testable import AgentPulseCore

@Suite struct DictationFormattingTests {
    @Test func literalUnlessEnabled() {
        let source = "Напиши новый абзац."
        #expect(DictationFormatting.apply(source, enabled: false) == source)
    }
    @Test func paragraphsAndItems() {
        #expect(DictationFormatting.apply("Привет. Новый абзац. Далее", enabled: true) == "Привет.\n\nДалее")
        #expect(DictationFormatting.apply("Новый пункт. Один новый пункт. Два", enabled: true) == "• Один\n• Два")
        #expect(DictationFormatting.apply("First new line second", enabled: true) == "First\nsecond")
    }
}
