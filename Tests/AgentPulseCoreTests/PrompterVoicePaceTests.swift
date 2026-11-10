import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct PrompterVoicePaceTests {
    let start = Date(timeIntervalSince1970: 1000)
    @Test func measuresSpeechButNotDuplicatePartialResultsOrLongSilence() {
        var pace = PrompterVoicePace()
        #expect(pace.observe(word: 0, now: start) == nil)
        #expect(pace.observe(word: 4, now: start.addingTimeInterval(2)) == 120)
        #expect(pace.observe(word: 4, now: start.addingTimeInterval(2.5)) == nil)
        #expect(pace.observe(word: 8, now: start.addingTimeInterval(4)) == 120)
        #expect(pace.observe(word: 9, now: start.addingTimeInterval(20)) == nil)
    }
    @Test func smoothsChangesAndIgnoresLargeSeek() {
        var pace = PrompterVoicePace()
        _ = pace.observe(word: 0, now: start)
        _ = pace.observe(word: 4, now: start.addingTimeInterval(2))
        #expect(pace.observe(word: 8, now: start.addingTimeInterval(3)) == 150)
        #expect(pace.observe(word: 35, now: start.addingTimeInterval(4)) == nil)
        pace.reset()
        #expect(pace.observe(word: 36, now: start.addingTimeInterval(10)) == nil)
    }
    @Test func voiceModeAdaptsReadingEstimateAndPauseResetsSample() {
        let words = ["один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять", "десять"]
        var module = PrompterModule()
        module.followsVoice = true
        _ = module.start(text: words.joined(separator: " "), now: start)
        module.hear(Array(words.prefix(4)), now: start.addingTimeInterval(2))
        module.hear(Array(words.prefix(8)), now: start.addingTimeInterval(4))
        #expect(module.speed == 120)
        module.togglePause(now: start.addingTimeInterval(4))
        module.togglePause(now: start.addingTimeInterval(60))
        module.hear(words, now: start.addingTimeInterval(62))
        #expect(module.speed == 120)
        #expect(module.position == 10)
    }

}
