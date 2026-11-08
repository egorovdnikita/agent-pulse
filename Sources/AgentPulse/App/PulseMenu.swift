import AgentPulseCore
import AppKit
import SwiftUI

/// Меню в строке меню: системное, как у любого приложения Mac. SwiftUI сам рисует его родным `NSMenu`.
struct PulseMenuItems: View {
    let app: AppDelegate

    var body: some View {
        let model = app.model
        let active = model.activeSessions
        if active.isEmpty {
            Text("Сейчас никто не работает")
        } else {
            ForEach(active.prefix(6)) { session in
                Button {} label: {
                    Text(BubbleCategory.sessionTitle(session))
                    Text(session.phase.text)
                }
                .disabled(true)
            }
        }
        if model.serverError != nil {
            Text("Не вижу агентов. Перезапусти приложение")
        }
        if !model.hooksInstalled {
            Button("Подключить Claude Code…") { app.showSettings(.sources) }
        }
        Divider()
        // Реакция без реплики: оценивать нечего, а её внутреннее имя показывать нельзя.
        if model.lastReaction != nil, let line = model.lastLine, !line.isEmpty {
            Section("Как тебе «\(line)»?") {
                Button("Нравится") { model.feedback("мило") }
                Button("Больше не надо") { model.feedback("бесит") }
            }
            Divider()
        }
        Toggle("Показывать маскота", isOn: Binding(get: { model.overlayVisible }, set: { app.setOverlayVisible($0) }))
        Toggle("Рассказывать новости", isOn: Binding(get: { model.config.character.designNews }, set: { app.setDesignNews($0) }))
        Divider()
        Button("Настройки…") { app.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Выйти из Agent Pulse") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// То же меню по правому клику на маскоте: системный `NSMenu` у курсора.
@MainActor
enum PulseMenu {
    static func make(app: AppDelegate) -> NSMenu {
        let model = app.model
        let menu = NSMenu()
        menu.autoenablesItems = false
        let active = model.activeSessions
        if active.isEmpty {
            menu.addItem(disabled("Сейчас никто не работает"))
        } else {
            for session in active.prefix(6) {
                let item = disabled(BubbleCategory.sessionTitle(session))
                if #available(macOS 14.4, *) { item.subtitle = session.phase.text }
                menu.addItem(item)
            }
        }
        if model.serverError != nil { menu.addItem(disabled("Не вижу агентов. Перезапусти приложение")) }
        if !model.hooksInstalled { menu.addItem(ActionItem("Подключить Claude Code…") { app.showSettings(.sources) }) }
        menu.addItem(.separator())
        if model.lastReaction != nil, let line = model.lastLine, !line.isEmpty {
            menu.addItem(.sectionHeader(title: "Как тебе «\(line)»?"))
            menu.addItem(ActionItem("Нравится") { model.feedback("мило") })
            menu.addItem(ActionItem("Больше не надо") { model.feedback("бесит") })
            menu.addItem(.separator())
        }
        let mascot = ActionItem("Показывать маскота") { app.setOverlayVisible(!model.overlayVisible) }
        mascot.state = model.overlayVisible ? .on : .off
        menu.addItem(mascot)
        let news = ActionItem("Рассказывать новости") { app.setDesignNews(!model.config.character.designNews) }
        news.state = model.config.character.designNews ? .on : .off
        menu.addItem(news)
        menu.addItem(.separator())
        menu.addItem(ActionItem("Настройки…", key: ",") { app.showSettings() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("Выйти из Agent Pulse", key: "q") { NSApp.terminate(nil) })
        return menu
    }

    private static func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

/// Пункт меню с действием-замыканием.
@MainActor
private final class ActionItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, key: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fire() {
        handler()
    }
}
