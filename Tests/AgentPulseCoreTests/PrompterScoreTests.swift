import Testing
@testable import AgentPulseCore

@Suite struct PrompterScoreTests {
    @Test func explicitAndParagraphPauses() {
        let score = PrompterScore("One two\n[пауза 2,5]\nThree\n\nFour")
        #expect(score.text == "One two\nThree\n\nFour")
        #expect(score.pauses == [2: 2.5, 3: 1])
        #expect(score.duration == 3.5)
    }
    @Test func inlineAndTrailingIgnored() {
        let score = PrompterScore("[pause 20]\nRead [пауза] aloud\n[pause 20]")
        #expect(score.text.contains("Read [пауза] aloud"))
        #expect(score.pauses.isEmpty)
    }
}
