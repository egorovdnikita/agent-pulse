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

struct MenuContent: View {
    let app: AppDelegate

    private func chatTitle(_ model: PulseModel) -> String {
        guard model.config.sources.claudeChat else { return "Claude Chat в приложении" }
        return model.accessibilityTrusted
            ? "Claude Chat в приложении: слежу" + lastEvent(model, .claudeChat)
            : "Claude Chat в приложении: нужен «Универсальный доступ»"
    }

    private func coworkTitle(_ model: PulseModel) -> String {
        switch model.coworkWatching {
        case true?: "Cowork: слежу" + lastEvent(model, .cowork)
        case false?: "Cowork: не найден"
        case nil: "Cowork"
        }
    }

    /// « · 3 мин назад» — когда источник последний раз подавал голос.
    private func lastEvent(_ model: PulseModel, _ source: AgentEvent.Source) -> String {
        guard let date = model.lastEventBySource[source] else { return "" }
        let seconds = Date().timeIntervalSince(date)
        let ago = switch seconds {
        case ..<60: "только что"
        case ..<3600: "\(Int(seconds / 60)) мин назад"
        default: "\(Int(seconds / 3600)) ч назад"
        }
        return " · " + ago
    }

    var body: some View {
        let model = app.model
        let active = model.activeSessions
        if active.count > 1 {
            Section("Сейчас") {
                ForEach(active.prefix(6)) { session in
                    Text([session.source.displayName, session.context].compactMap(\.self).joined(separator: " · ") + ": " + session.phase.text)
                }
            }
        } else {
            Text(model.statusLine)
        }
        if let error = model.serverError {
            Text("Сокет недоступен: \(error)")
        }
        Divider()
        Section("Источники") {
            Text((model.hooksInstalled ? "Claude Code: хуки установлены" : "Claude Code: хуки не установлены")
                + lastEvent(model, .claudeCode))
            Toggle(coworkTitle(model), isOn: Binding(
                get: { model.config.sources.cowork },
                set: { app.setCoworkEnabled($0) }
            ))
            if model.browserBridgeInstalled {
                Button("Браузер: мост установлен — показать расширение") { app.revealExtension() }
                Button("Отключить Claude в браузере") { app.uninstallBrowserBridge() }
            } else {
                Button("Подключить Claude в браузере…") { app.installBrowserBridge() }
            }
            Toggle(chatTitle(model), isOn: Binding(
                get: { model.config.sources.claudeChat },
                set: { app.setChatWindowEnabled($0) }
            ))
            if model.config.sources.claudeChat && model.accessibilityTrusted {
                Button("Снимок окна Claude для настройки") { app.saveChatWindowSnapshot() }
            }
            Button("Figma: показать плагин-компаньон") { app.revealFigmaPlugin() }
            if let error = model.companionError {
                Text("Figma: порт занят — \(error)")
            }
        }
        Divider()
        Toggle("Показывать маскота", isOn: Binding(get: { model.overlayVisible }, set: { app.setOverlayVisible($0) }))
        Picker("Угол экрана", selection: Binding(get: { model.config.display.anchor }, set: { app.setAnchor($0) })) {
            Text("Справа сверху").tag(PulseConfig.Display.Anchor.topRight)
            Text("Слева сверху").tag(PulseConfig.Display.Anchor.topLeft)
            Text("Справа снизу").tag(PulseConfig.Display.Anchor.bottomRight)
            Text("Слева снизу").tag(PulseConfig.Display.Anchor.bottomLeft)
        }
        Picker("Дисплей", selection: Binding(get: { model.config.display.screen }, set: { app.setScreen($0) })) {
            Text("С Dock").tag("dock")
            Text("Основной").tag("main")
            Text("С курсором").tag("active")
            Text("Встроенный").tag("builtin")
        }
        Divider()
        if model.hooksInstalled {
            Button("Удалить хуки Claude Code") { app.uninstallHooks() }
        } else {
            Button("Установить хуки Claude Code…") { app.installHooks() }
        }
        if let reaction = model.lastReaction {
            Section("Последняя реакция: \(model.lastLine ?? reaction)") {
                Button("Мило") { model.feedback("мило") }
                Button("Бесит") { model.feedback("бесит") }
            }
        }
        Button("Характер…") { app.showSettings() }
        Button("Вернуть маскота в угол") { app.panel?.resetPosition() }
        Toggle("Гравитация", isOn: Binding(get: { model.config.display.gravity }, set: { app.setGravity($0) }))
        Toggle("Запускать при входе", isOn: Binding(get: { model.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
        Button("Mascot Lab") { app.showLab() }
        Divider()
        Button("Выйти") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
