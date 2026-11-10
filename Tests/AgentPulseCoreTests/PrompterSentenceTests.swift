import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct PrompterSentenceTests {
    @Test func russianAndEmoji() {
        let script = PrompterScript(text: "Первое предложение. 🙂 Второе длинное предложение!")
        #expect(script.sentenceStart(at: 1) == 0)
        #expect(script.sentenceStart(at: 5) == 2)
        #expect(PrompterScript(text: "").sentenceStart(at: 10) == 0)
    }
    @Test func restartKeepsPausedState() {
        var module = PrompterModule(); let now = Date()
        module.start(text: "One sentence. Another longer sentence.", now: now)
        module.seek(toFraction: 0.9, now: now)
        module.togglePause(now: now)
        module.restartSentence(now: now)
        #expect(module.position == 2)
        #expect(module.mode == .paused)
    }
}
