import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct DictationCorrectionNoticeTests {
    @Test func existingCapsuleDistinguishesCorrectionAndClearsItsSuccess() {
        let now = Date(timeIntervalSince1970: 1000)
        var module = DictationModule()
        _ = module.press(now: now, modelReady: true, correcting: true)
        #expect(module.capsule(now: now).label == "Исправление")
        _ = module.release(now: now.addingTimeInterval(1))
        module.finish(now: now, notice: .corrected)
        #expect(!module.correcting)
        #expect(module.capsule(now: now).label == "Исправлено")
        #expect(module.priority(now: now.addingTimeInterval(2)) == nil)
        _ = module.press(now: now.addingTimeInterval(3), modelReady: true)
        #expect(module.capsule(now: now).label == "Диктовка")
    }
}
