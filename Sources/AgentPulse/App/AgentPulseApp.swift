import AgentPulseCore
import SwiftUI

/// Menu bar приложение без иконки в Dock (LSUIElement в Info.plist; без бандла — `.accessory` в делегате).
@main
struct AgentPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        MenuBarExtra {
            MenuContent(app: app)
        } label: {
            Image(systemName: app.model.menuSymbol)
        }
    }
}

/// Меню в строке меню и по правому клику на маскоте: только то, что нужно каждый день.
/// Всё остальное — в окне «Настройки».
struct MenuContent: View {
    let app: AppDelegate

    var body: some View {
        let model = app.model
        let active = model.activeSessions
        if active.isEmpty {
            Text("Сейчас никто не работает")
        } else {
            Section("Сейчас") {
                ForEach(active.prefix(6)) { session in
                    let name = [BubbleCategory.agentTitle(session.source), session.context].compactMap(\.self).joined(separator: " · ")
                    Text("\(name) — \(session.phase.text)")
                }
            }
        }
        if let error = model.serverError {
            Text("Сокет недоступен: \(error)")
        }
        if !model.hooksInstalled {
            Button("Подключить Claude Code…") { app.showSettings(.sources) }
        }
        Divider()
        Toggle("Показывать маскота", isOn: Binding(get: { model.overlayVisible }, set: { app.setOverlayVisible($0) }))
        Menu("Новости") {
            Toggle("Рассказывать новости", isOn: Binding(get: { model.config.character.designNews }, set: { app.setDesignNews($0) }))
            Divider()
            ForEach(NewsTopic.allCases, id: \.self) { topic in
                Toggle(topic.title, isOn: Binding(
                    get: { model.config.character.enabledNewsTopics.contains(topic) },
                    set: { app.setNewsTopic(topic, on: $0) }
                ))
                .disabled(!model.config.character.designNews)
            }
        }
        if let reaction = model.lastReaction {
            Section("Последняя реакция: \(model.lastLine ?? reaction)") {
                Button("Мило") { model.feedback("мило") }
                Button("Бесит") { model.feedback("бесит") }
            }
        }
        Divider()
        Button("Вернуть маскота в угол") { app.panel?.resetPosition() }
        Button("Настройки…") { app.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Выйти") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
