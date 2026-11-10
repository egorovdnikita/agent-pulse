import Foundation
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
    @Test func codeAndLinksStayVerbatim() {
        let text = "Hello `let x = 1` https://example.com\n```swift\nlet y = 2\n```\n[Guide](https://example.com/a)"
        let layout = TranslationLayout(text)
        #expect(layout.texts == ["Hello"])
        #expect(layout.assembling(["Привет"]) == text.replacingOccurrences(of: "Hello", with: "Привет"))
        let unclosed = "Before\n~~~\nprivate code"
        #expect(TranslationLayout(unclosed).texts == ["Before"])
    }

}
