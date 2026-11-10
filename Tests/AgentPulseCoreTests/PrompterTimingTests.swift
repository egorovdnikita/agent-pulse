import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct PrompterTimingTests {
    @Test func targetAndBounds() {
        #expect(PrompterTiming(words: 600, target: 300)?.speed == 120)
        #expect(PrompterTiming(words: 600, target: 330, pauses: 30)?.seconds == 330)
        #expect(PrompterTiming(words: 600, target: 20)?.limited == true)
        #expect(PrompterTiming(words: 0, target: 20) == nil)
        #expect(PrompterTiming(words: 600, target: .nan) == nil)
    }
    @Test func exactTempoIsVisibleAndButtonsReturnToSteps() {
        var module = PrompterModule()
        module.setExactSpeed(120)
        #expect(module.multiplierText == "0.92x")
        module.changeSpeed(faster: true)
        #expect(module.multiplierText == "1.25x")
    }
    @Test func runningScriptDurationIncludesMarkupPause() {
        var module = PrompterModule()
        module.start(text: "One two three\n[pause 2]\nFour five six", now: Date(), markup: true)
        let timing = module.fitDuration(5)
        #expect(timing?.speed == 120)
        #expect(module.total == 5)
    }
    @Test func parseDurations() {
        #expect(PrompterTiming.parse("5") == 300)
        #expect(PrompterTiming.parse("2:30") == 150)
        #expect(PrompterTiming.parse("2,5") == 150)
        #expect(PrompterTiming.parse("2:60") == nil)
        #expect(PrompterTiming.parse("-2") == nil)
        #expect(PrompterTiming.parse("nan") == nil)
        #expect(PrompterTiming.parse("0:01") == 1)
        #expect(PrompterTiming.parse("0:00") == nil)
        #expect(PrompterTiming.parse("0,001") == nil)
        #expect(PrompterTiming.parse("1.5:20") == nil)
        #expect(PrompterTiming.parse("120:00") == 7200)
        #expect(PrompterTiming.parse("120:01") == nil)
    }
}
