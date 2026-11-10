import Foundation
import Testing
@testable import AgentPulse

@Suite @MainActor struct DictationReplayAvailabilityTests {
    @Test func replayUnavailableWhileReadingOrAnotherReplay() {
        let model = ConsoleModel(promo: true)
        model.dictationEnabled = true
        model.dictationReplayUntil = Date().addingTimeInterval(120)
        #expect(model.canReplayDictation)
        model.dictationReplaying = true
        #expect(!model.canReplayDictation)
        model.dictationReplaying = false
        model.prompterDraft = "Один два три"
        model.startPrompterDraft()
        #expect(!model.canReplayDictation)
        model.stopPrompter()
        #expect(model.canReplayDictation)
        model.dictationEnabled = false
        #expect(!model.canReplayDictation)
    }
    @Test func cannotStartPrompterDuringPendingPaste() {
        let model = ConsoleModel(promo: true)
        model.prompterDraft = "Один два три"
        model.dictationReplaying = true
        model.startPrompterDraft()
        #expect(!model.prompter.isActive)
    }
}
