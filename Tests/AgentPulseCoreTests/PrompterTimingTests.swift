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
    @Test func parseDurations() {
        #expect(PrompterTiming.parse("5") == 300)
        #expect(PrompterTiming.parse("2:30") == 150)
        #expect(PrompterTiming.parse("2,5") == 150)
        #expect(PrompterTiming.parse("2:60") == nil)
        #expect(PrompterTiming.parse("-2") == nil)
        #expect(PrompterTiming.parse("nan") == nil)
    }
}
