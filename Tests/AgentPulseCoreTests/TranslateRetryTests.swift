import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct TranslateRetryTests {
    @Test func retryKeepsSelectionAndInvalidatesOldResult() {
        var module = TranslateModule()
        _ = module.press(selection: "Hello", clipboard: nil, now: Date())
        let failed = module.requestVersion
        module.fail(source: "Hello", problem: "Нужны языки", request: failed)
        let source = module.retryFailed(source: "Hello", version: failed)
        #expect(source == "Hello")
        #expect(module.replaceable)
        module.finish(source: "Hello", result: "Старый", request: failed)
        #expect(module.state == .working(source: "Hello"))
        module.finish(source: "Hello", result: "Привет", request: module.requestVersion)
        #expect(module.state == .done(source: "Hello", result: "Привет"))
    }
    @Test func newTextOrClearPreventsOldRetry() {
        var module = TranslateModule()
        _ = module.type("Hello")
        module.fail(source: "Hello", problem: "Нужны языки")
        let failed = module.requestVersion
        _ = module.type("New text")
        let old = module.retryFailed(source: "Hello", version: failed)
        #expect(old == nil)
        module.reset()
        let cleared = module.retryFailed(source: "Hello", version: module.requestVersion)
        #expect(cleared == nil)
    }
}
