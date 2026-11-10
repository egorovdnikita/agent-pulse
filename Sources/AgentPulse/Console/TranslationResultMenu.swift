import AgentPulseCore
import AppKit
import SwiftUI

/// Перехватывает только контекстный клик; обычное выделение остаётся у текста SwiftUI.
struct TranslationResultMenu: NSViewRepresentable {
    let model: ConsoleModel
    func makeNSView(context: Context) -> TranslationResultMenuView { TranslationResultMenuView() }
    func updateNSView(_ view: TranslationResultMenuView, context: Context) { view.model = model }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TranslationResultMenuView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

final class TranslationResultMenuView: NSView {
    weak var model: ConsoleModel?
    private var actions: [() -> Void] = []
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp?.currentEvent,
              event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else { return nil }
        return super.hitTest(point)
    }
    override func rightMouseDown(with event: NSEvent) { presentMenu(event) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { presentMenu(event) }
        else { super.mouseDown(with: event) }
    }
    private func presentMenu(_ event: NSEvent) {
        guard let menu = menu(for: event), menu.numberOfItems > 0 else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        actions = []
        func add(_ title: String, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = actions.count
            actions.append(action)
            menu.addItem(item)
        }
        if model.canRecoverTranslation {
            add("Восстановить последний перевод") { model.recoverTranslation() }
        }
        if model.canRestoreTranslationReview {
            add("Вернуть исходный перевод") { model.restoreTranslationReview() }
        }
        if case .done(_, let result) = model.translate.state {
            add("Скопировать перевод") { model.copyTranslation(result) }
            add("Скопировать как простой текст · ⇧⌘C") { model.copyTranslation(result) }
            if model.translate.replaceable { add("Заменить выделенное") { model.onTranslateReplace?(result) } }
            if !model.canRestoreTranslationReview { add("Проверить обратным переводом") { model.reviewReverseTranslation() } }
        }
        return menu
    }
    @objc private func performMenuAction(_ item: NSMenuItem) {
        guard actions.indices.contains(item.tag) else { return }
        actions[item.tag]()
    }
}
