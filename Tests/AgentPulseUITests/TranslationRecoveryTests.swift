import AgentPulseCore
import Testing
@testable import AgentPulse

@Suite @MainActor struct TranslationRecoveryTests {
    @Test func recoversResultAndInvalidatesRequests() {
        let model = ConsoleModel(promo: true)
        model.typeTranslation("Hello")
        model.finishTranslate(source: "Hello", result: .success("Привет"))
        let version = model.translate.requestVersion
        model.clearTranslation()
        #expect(model.canRecoverTranslation)
        model.recoverTranslation()
        #expect(model.translateInput == "Hello")
        #expect(model.translate.state == .done(source: "Hello", result: "Привет"))
        #expect(model.translate.requestVersion > version)
        #expect(!model.canRecoverTranslation)
        model.clearTranslation()
    }
    @Test func recoveredTextCannotUseAnotherExternalSelectionReceipt() {
        let model = ConsoleModel(promo: true)
        model.translatorEnabled = true
        _ = model.pressTranslate(selection: "First", clipboard: nil)
        model.finishTranslate(source: "First", result: .success("Первый"))
        model.clearTranslation()
        _ = model.pressTranslate(selection: "Second", clipboard: nil)
        model.clearTranslation()
        model.recoverTranslation()
        #expect(model.translateInput == "First")
        #expect(!model.translate.replaceable)
        model.clearTranslation()
    }
    @Test func newInputBlocksRecovery() {
        let model = ConsoleModel(promo: true)
        model.typeTranslation("Hello"); model.finishTranslate(source: "Hello", result: .success("Привет"))
        model.clearTranslation(); model.typeTranslation("New")
        model.recoverTranslation()
        #expect(model.translateInput == "New")
        model.clearTranslation()
    }
}
