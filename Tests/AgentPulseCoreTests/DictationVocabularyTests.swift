import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct DictationVocabularyTests {
    @Test func alternativesAndExactSpelling() {
        let rules = [DictationRule(spoken: "айфон | ай фон", written: "iPhone", exactSpelling: true)]
        #expect(DictationRules.apply("Айфон и ай фон", custom: rules) == "iPhone и iPhone")
        #expect(DictationRules.apply("мойайфон", custom: rules) == "мойайфон")
    }
    @Test func oldRuleDecode() throws {
        let rule = try JSONDecoder().decode(DictationRule.self, from: Data("{\"spoken\":\"пример\",\"written\":\"example\"}".utf8))
        #expect(rule.exactSpelling == nil)
        #expect(rule.variants == ["пример"])
        #expect(DictationRules.apply("Пример", custom: [rule]) == "Example")
    }
}
