import AgentPulseCore
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = PulseModel()
    private let notifier = Notifier()
    private var panel: OverlayPanel?
    private var server: SocketServer?
    private var labWindow: NSWindow?
    private var screenTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        notifier.requestAuthorization()
        model.notifier = notifier
        model.hooksInstalled = HookInstaller.isInstalled()

        let panel = OverlayPanel(model: model)
        panel.orderFrontRegardless()
        self.panel = panel

        // Панель переезжает на монитор с курсором. Опрос дешёвый и не требует никаких прав.
        screenTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.followActiveScreen() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.reposition() }
        }

        startServer()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func startServer() {
        let inbox = model.inbox
        let server = SocketServer(path: PulsePaths.socketPath) { data in
            // Разбор — прямо здесь, вне главного потока; время события — момент приёма.
            if let event = ClaudeCodeHooks.parse(data) {
                inbox.yield(.event(event))
            }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            model.serverError = "\(error)"
        }
    }

    // MARK: - Меню

    func setOverlayVisible(_ visible: Bool) {
        model.overlayVisible = visible
        if visible { panel?.orderFrontRegardless() } else { panel?.orderOut(nil) }
    }

    func setAnchor(_ anchor: PulseConfig.Display.Anchor) {
        model.config.display.anchor = anchor
        try? model.config.save()
        panel?.reposition()
    }

    func showLab() {
        if labWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MascotLabView(model: model)))
            window.title = "Mascot Lab"
            window.isReleasedWhenClosed = false
            labWindow = window
        }
        NSApp.activate()
        labWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Хуки

    /// Путь к `pulse-hook` рядом с исполняемым файлом приложения (в бандле и при `swift run`).
    private var hookCommand: String? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let hook = executable.deletingLastPathComponent().appending(path: "pulse-hook")
        guard FileManager.default.isExecutableFile(atPath: hook.path) else { return nil }
        return "\"\(hook.path)\""
    }

    func installHooks() {
        guard let command = hookCommand else {
            showAlert("Не найден pulse-hook", "Он должен лежать рядом с приложением. Соберите проект скриптом scripts/bundle.sh.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Установить хуки Claude Code?"
        alert.informativeText = """
            Agent Pulse добавит хуки в ~/.claude/settings.json, чтобы видеть, что делает агент. \
            Рядом будет создана резервная копия файла. Ваши собственные хуки не изменятся, \
            удаление вернёт файл к исходному виду.

            Ничего не уходит с машины, текст промптов не читается.
            """
        alert.addButton(withTitle: "Установить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try HookInstaller.install(command: command)
            model.hooksInstalled = true
        } catch {
            showAlert("Хуки не установлены", "\(error)")
        }
    }

    func uninstallHooks() {
        do {
            try HookInstaller.uninstall()
            model.hooksInstalled = false
        } catch {
            showAlert("Хуки не удалены", "\(error)")
        }
    }

    private func showAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}
