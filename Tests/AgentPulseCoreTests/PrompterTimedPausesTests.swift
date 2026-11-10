import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct PrompterTimedPausesTests {
    @Test func stopsAndContinuesAcrossPause() {
        var module = PrompterModule(); let now = Date()
        module.start(text: "One\n[pause 2]\nTwo three", now: now, markup: true)
        let wordSeconds = 60.0 / Double(module.speed)
        _ = module.advance(now: now.addingTimeInterval(wordSeconds + 1))
        #expect(module.position == 1)
        #expect(module.holdsForMarkup)
        _ = module.advance(now: now.addingTimeInterval(wordSeconds + 2.2))
        #expect(module.position > 1)
        #expect(!module.holdsForMarkup)
        #expect(abs(module.total - (3 * wordSeconds + 2)) < 0.001)
    }
    @Test func manualPauseFreezesMarkupCountdown() {
        var module = PrompterModule(); let now = Date()
        module.start(text: "One\n[pause 2]\nTwo three", now: now, markup: true)
        let reached = now.addingTimeInterval(60.0 / Double(module.speed) + 1)
        _ = module.advance(now: reached)
        module.togglePause(now: reached)
        _ = module.advance(now: reached.addingTimeInterval(100))
        module.togglePause(now: reached.addingTimeInterval(100))
        _ = module.advance(now: reached.addingTimeInterval(100.5))
        #expect(module.position == 1)
        #expect(module.holdsForMarkup)
        _ = module.advance(now: reached.addingTimeInterval(101.2))
        #expect(module.position > 1)
    }
    @Test func seekingBackReplaysPauseAndVoiceDoesNotWaitForIt() {
        var module = PrompterModule(); let now = Date()
        module.start(text: "One\n[pause 2]\nTwo three", now: now, markup: true)
        module.seek(toFraction: 0.9, now: now)
        module.seek(toFraction: 0, now: now)
        _ = module.advance(now: now.addingTimeInterval(1))
        #expect(module.holdsForMarkup)
        module.stop(); module.followsVoice = true
        module.start(text: "One\n[pause 2]\nTwo three", now: now, markup: true)
        module.hear(["one", "two"], now: now)
        #expect(module.position == 2)
        #expect(!module.holdsForMarkup)
        #expect(module.total < 2)
    }
    @Test func literalByDefault() {
        var module = PrompterModule()
        module.start(text: "One\n[pause 2]\nTwo", now: Date())
        #expect(module.script.words.contains("[pause"))
    }
}
