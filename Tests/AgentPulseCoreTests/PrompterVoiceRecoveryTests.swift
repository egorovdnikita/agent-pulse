import Testing
@testable import AgentPulseCore

@Suite struct PrompterVoiceRecoveryTests {
    @Test func skippedWordsStillFindShortFinalWord() {
        let script = PrompterScript(text: "мы покажем новый дизайн и закончим")
        #expect(PrompterVoiceMatch.position(heard: ["мы", "покажем", "и"], in: script.normalized, from: 0) == 5)
    }
    @Test func spokenCorrectionCanBeSkipped() {
        let script = PrompterScript(text: "проверим новый макет и всё")
        #expect(PrompterVoiceMatch.position(heard: ["проверим", "новый", "макет", "пожалуй", "и"], in: script.normalized, from: 0) == 4)
    }
    @Test func oneDistantWordCannotJumpOverParagraph() {
        let script = PrompterScript(text: Array(repeating: "другое", count: 20).joined(separator: " ") + " дизайн")
        #expect(PrompterVoiceMatch.position(heard: ["дизайн"], in: script.normalized, from: 0) == nil)
    }
}
