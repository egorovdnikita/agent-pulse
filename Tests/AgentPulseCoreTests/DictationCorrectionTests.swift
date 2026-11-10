import Testing
@testable import AgentPulseCore

@Suite struct DictationCorrectionTests {
    @Test func lastWordPreservesPunctuationAndOnlyChangesProvidedInsertion() {
        let command = DictationCorrection.parse("Замени последнее слово на дизайн.")
        #expect(command?.applying(to: "Проверяем новый макет!") == "Проверяем новый дизайн!")
        #expect(DictationCorrection.parse("replace last word with layout")?.applying(to: "New screen.") == "New layout.")
    }
    @Test func phraseChangesOnlyLastWholeOccurrence() {
        let command = DictationCorrection.parse("Замени «макет» на «дизайн».")
        #expect(command?.applying(to: "Макет, макетик и макет.") == "Макет, макетик и дизайн.")
        #expect(command?.applying(to: "Только макетик") == nil)
        #expect(DictationCorrection.parse("Обычная фраза для записи") == nil)
    }
}
