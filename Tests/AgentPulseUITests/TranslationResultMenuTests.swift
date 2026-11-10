import AgentPulseCore
import AppKit
import Testing
@testable import AgentPulse

@Suite @MainActor struct TranslationResultMenuTests {
    private func event() throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @Test func nativeMenuCanReverseAndRestoreWithoutReplacingOriginal() throws {
        _ = NSApplication.shared
        let model = ConsoleModel(promo: true)
        model.translatorEnabled = true
        _ = model.pressTranslate(selection: "Hello", clipboard: nil)
        model.finishTranslate(source: "Hello", result: .success("Привет"))
        let view = TranslationResultMenuView()
        view.model = model
        let menu = try #require(view.menu(for: event()))
        #expect(menu.items.map(\.title).contains("Заменить выделенное"))
        let reverse = try #require(menu.items.firstIndex { $0.title == "Проверить обратным переводом" })
        menu.performActionForItem(at: reverse)
        #expect(model.canRestoreTranslationReview)
        #expect(model.translateInput == "Привет")
        #expect(!model.translate.replaceable)
        let back = try #require(view.menu(for: event()))
        let restore = try #require(back.items.firstIndex { $0.title == "Вернуть исходный перевод" })
        back.performActionForItem(at: restore)
        #expect(model.translateInput == "Hello")
        #expect(model.translate.state == .done(source: "Hello", result: "Привет"))
        #expect(model.translate.replaceable)
    }

    @Test func nativeRecoveryMenuRestoresOnlyTextAndCopyActions() throws {
        _ = NSApplication.shared
        let model = ConsoleModel(promo: true)
        model.translatorEnabled = true
        _ = model.pressTranslate(selection: "Hello", clipboard: nil)
        model.finishTranslate(source: "Hello", result: .success("Привет"))
        model.clearTranslation()
        let view = TranslationResultMenuView(); view.model = model
        let menu = try #require(view.menu(for: event()))
        let restore = try #require(menu.items.firstIndex { $0.title == "Восстановить последний перевод" })
        menu.performActionForItem(at: restore)
        #expect(model.translate.state == .done(source: "Hello", result: "Привет"))
        let recovered = try #require(view.menu(for: event()))
        let titles = recovered.items.map(\.title)
        #expect(titles.contains("Скопировать как простой текст · ⇧⌘C"))
        #expect(!titles.contains("Заменить выделенное"))
        model.clearTranslation()
    }

    @Test func readOnlySourceNeverOffersReplacement() throws {
        let model = ConsoleModel(promo: true)
        model.translatorEnabled = true
        _ = model.pressTranslate(selection: "Hello", clipboard: nil, editable: false)
        model.finishTranslate(source: "Hello", result: .success("Привет"))
        let view = TranslationResultMenuView()
        view.model = model
        let menu = try #require(view.menu(for: event()))
        #expect(!menu.items.map(\.title).contains("Заменить выделенное"))
        #expect(menu.items.map(\.title).contains("Скопировать перевод"))
        // Прозрачный вид сам не забирает обычные клики, когда контекстного события нет.
        #expect(view.hitTest(.zero) == nil)
    }
}
