import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct TranslationTermsTests {
    @Test func literalAndLongest() {
        let layout = TranslationLayout("Use Box UI and Box, not Boxer or box.", protectedTerms: ["Box", "Box UI"])
        #expect(!layout.texts.contains(where: { $0.contains("Box UI") }))
        #expect(layout.texts.contains(where: { $0.contains("Boxer") && $0.contains("box") }))
        #expect(layout.assembling(layout.texts) == "Use Box UI and Box, not Boxer or box.")
    }
    @Test func boundsAndRegexCharacters() {
        var terms = TranslationTerms()
        terms.add(" C++ "); terms.add("C++"); terms.add("\n"); terms.add(String(repeating: "a", count: 121))
        #expect(terms.terms == ["C++"])
        let layout = TranslationLayout("Use C++ now", protectedTerms: terms.terms)
        #expect(layout.texts == ["Use", "now"])
    }
}
