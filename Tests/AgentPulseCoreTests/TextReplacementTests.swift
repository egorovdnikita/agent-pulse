import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct TextReplacementTests {
    @Test func validatesUTF16AndRejectsChangedText() {
        let value = "🌸 Hello мир"
        let replacement = TextReplacement(original: "Hello", range: NSRange(location: 3, length: 5))
        #expect(replacement.matches(value))
        #expect(!replacement.matches("🌸 Other мир"))
        let splitEmoji = TextReplacement(original: "🌸", range: NSRange(location: 1, length: 1)).matches(value)
        #expect(splitEmoji == false)
        let invalid = TextReplacement(original: "x", range: NSRange(location: Int.max, length: 1)).matches(value)
        #expect(invalid == false)
    }
    @Test func capturesOnlyActuallyInsertedText() {
        #expect(TextReplacement.inserted("Привет", endingAt: 9, in: "🌸 Привет")?.range == NSRange(location: 3, length: 6))
        #expect(TextReplacement.inserted("Привет", endingAt: 9, in: "🌸 Другое") == nil)
        #expect(TextReplacement.inserted("Hello", endingAt: 2, in: "Hello") == nil)
    }
}
