import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct TranslateReplacementTests {
    private func selection(editable: Bool = true) -> TranslateModule {
        var module = TranslateModule()
        _ = module.press(selection: "Hello", clipboard: nil, now: Date(), editable: editable)
        module.finish(source: "Hello", result: "Привет")
        return module
    }

    @Test func changingLanguagesKeepsOriginalSelectionAndRejectsOldResult() {
        var module = selection()
        let old = module.requestVersion
        module.selectTarget("de")
        _ = module.type("Hello", preservingSelection: true)
        module.finish(source: "Hello", result: "Привет", request: old)
        #expect(module.state == .working(source: "Hello"))
        module.finish(source: "Hello", result: "Hallo", request: module.requestVersion)
        #expect(module.replaceable)
        module.selectSource(nil)
        _ = module.type("Hello", preservingSelection: true)
        #expect(module.replaceable)
    }

    @Test func manualEditingAndClearRemoveSelection() {
        var module = selection()
        _ = module.type("Hello")
        #expect(!module.replaceable)
        module.selectTarget("de")
        _ = module.type("Hello", preservingSelection: true)
        #expect(!module.replaceable)
        module = selection()
        module.reset()
        _ = module.type("Hello", preservingSelection: true)
        #expect(!module.replaceable)
    }

    @Test func swapAndDifferentInputCannotReplaceOriginal() {
        var module = selection()
        let result = module.flip(sourceText: "Hello")
        _ = module.type(result!, preservingSelection: true)
        #expect(!module.replaceable)
        module = selection()
        _ = module.type("Different text", preservingSelection: true)
        #expect(!module.replaceable)
    }

    @Test func readOnlySelectionCannotBecomeReplaceable() {
        var module = selection(editable: false)
        module.selectTarget("de")
        _ = module.type("Hello", preservingSelection: true)
        #expect(!module.replaceable)
    }
}
