import Testing
@testable import AgentPulseCore

@Suite struct TranslationLayoutTests {
    @Test func preservesParagraphsListsIndentationAndCRLF() {
        let layout = TranslationLayout("# Header\r\n\r\n  - Hello  \r\n2. World\n")
        #expect(layout.texts == ["Header", "Hello", "World"])
        #expect(layout.assembling(["Заголовок", "Привет", "Мир"]) == "# Заголовок\r\n\r\n  - Привет  \r\n2. Мир\n")
        #expect(layout.assembling(["Неполный ответ"]) == nil)
    }
    @Test func preservesEmptyAndWhitespaceOnlyInput() {
        for text in ["", "  \n\t\r\n", "\r"] {
            let layout = TranslationLayout(text)
            #expect(layout.texts.isEmpty)
            #expect(layout.assembling([]) == text)
        }
    }
}
