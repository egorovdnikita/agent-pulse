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
    @Test func newInputBlocksRecovery() {
        let model = ConsoleModel(promo: true)
        model.typeTranslation("Hello"); model.finishTranslate(source: "Hello", result: .success("Привет"))
        model.clearTranslation(); model.typeTranslation("New")
        model.recoverTranslation()
        #expect(model.translateInput == "New")
        model.clearTranslation()
    }
}
