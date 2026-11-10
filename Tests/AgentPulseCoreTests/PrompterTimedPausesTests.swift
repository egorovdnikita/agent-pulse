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
    @Test func literalByDefault() {
        var module = PrompterModule()
        module.start(text: "One\n[pause 2]\nTwo", now: Date())
        #expect(module.script.words.contains("[pause"))
    }
}
