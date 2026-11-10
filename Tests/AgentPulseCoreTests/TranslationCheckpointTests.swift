import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct TranslationCheckpointTests {
    @Test func restoresOriginalPairTextAndSelectionWithoutAcceptingOldRequests() {
        var module = TranslateModule()
        _ = module.press(selection: "Hello", clipboard: nil, now: Date())
        module.finish(source: "Hello", result: "Привет")
        let saved = module
        let reversed = module.flip(sourceText: "Hello")!
        _ = module.type(reversed)
        let stale = module.requestVersion
        module.restore(saved)
        #expect(module.state == saved.state)
        #expect(module.preferences == saved.preferences)
        #expect(module.replaceable)
        #expect(module.requestVersion > stale)
        _ = module.type("Hello")
        module.finish(source: "Hello", result: "Запоздалый", request: stale)
        #expect(module.state == .working(source: "Hello"))
    }
}
