import AgentPulseCore
import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = PulseModel()
    private let notifier = Notifier()
    private(set) var panel: OverlayPanel?
    private var server: SocketServer?
    private var cowork: CoworkWatcher?
    private var companion: LocalHTTPServer?
    private var chatWindow: ChatWindowWatcher?
    private var senses: [Sense] = []
    private var settingsWindow: NSWindow?
    private var trustTimer: Timer?
    private var labWindow: NSWindow?
    private var screenTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        notifier.requestAuthorization()
        model.notifier = notifier
        model.hooksInstalled = HookInstaller.isInstalled()
        model.browserBridgeInstalled = BrowserBridgeInstaller.isInstalled()
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        if CommandLine.arguments.contains("--register-login-item") && !model.launchAtLogin {
            setLaunchAtLogin(true)
        }
        // Отладка: `open AgentPulse.app --args --state sleep|idle|think|wait` — как ручное состояние в MascotLab.
        if let index = CommandLine.arguments.firstIndex(of: "--state"), index + 1 < CommandLine.arguments.count {
            model.labOverride = switch CommandLine.arguments[index + 1] {
            case "sleep": .sleep
            case "idle": .idle
            case "think": .think
            case "wait": .waitYou(.permission)
            default: nil
            }
        }
        repairInstallations()

        let panel = OverlayPanel(app: self)
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
        startCowork()
        startCompanion()
        startChatWindow()
        model.start()
        startSenses()
        model.onIdleHide = { [weak self] hide in
            guard let self, self.model.overlayVisible else { return }
            if hide { self.panel?.orderOut(nil) } else { self.panel?.orderFrontRegardless() }
        }
        model.onSpecial = { [weak self] action, line in
            self?.panel?.perform(action, line: line)
        }
        model.onUserBack = { [weak self] in
            self?.panel?.returnHomeIfWandering()
        }
        // Отладка: `open AgentPulse.app --args --signal capsLockOn [значение]` — как SignalSimulator.
        if let index = CommandLine.arguments.firstIndex(of: "--signal"), index + 1 < CommandLine.arguments.count,
           let kind = SignalKind(rawValue: CommandLine.arguments[index + 1]) {
            let value = index + 2 < CommandLine.arguments.count ? Double(CommandLine.arguments[index + 2]) : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [model] in model.simulate(kind, value: value) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        cowork?.stop()
        companion?.stop()
        chatWindow?.stop()
        senses.forEach { $0.stop() }
    }

    private func startServer() {
        let inbox = model.inbox
        let server = SocketServer(path: PulsePaths.socketPath) { data in
            // Разбор — прямо здесь, вне главного потока; время события — момент приёма.
            for event in Ingest.parse(data) {
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

    private func startCowork() {
        guard model.config.sources.cowork else {
            model.coworkWatching = nil
            return
        }
        let inbox = model.inbox
        let watcher = CoworkWatcher { events in
            for event in events { inbox.yield(.event(event)) }
        }
        model.coworkWatching = watcher.start()
        cowork = watcher
    }

    /// Сервер для плагина-компаньона Figma: события «ИИ генерирует» и кадры зеркала.
    private func startCompanion() {
        let inbox = model.inbox
        let wish = model.mirrorWish
        let model = model
        let server = LocalHTTPServer { request in
            guard request.method == "POST", request.path == "/figma" else {
                return LocalHTTPServer.Response(status: request.method == "OPTIONS" ? 204 : 404)
            }
            switch FigmaCompanion.parse(request.body) {
            case .events(let events):
                for event in events { inbox.yield(.event(event)) }
            case .frame(let frame):
                Task { @MainActor in model.receiveFrame(frame) }
            case .change, nil:
                break
            }
            return LocalHTTPServer.Response(body: FigmaCompanion.reply(mirror: wish.value))
        }
        do {
            try server.start()
            companion = server
        } catch {
            model.companionError = "\(error)"
        }
    }

    // MARK: - Органы чувств

    func startSenses() {
        senses.forEach { $0.stop() }
        let inbox = model.inbox
        senses = SenseRegistry.make(model.config)
        for sense in senses {
            sense.start { signal in inbox.yield(.signal(signal)) }
        }
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: CharacterSettingsView(app: self)))
            window.title = "Характер"
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Чат в Claude desktop

    private func startChatWindow() {
        model.accessibilityTrusted = ChatWindowWatcher.isTrusted
        guard model.config.sources.claudeChat else { return }
        let inbox = model.inbox
        let watcher = ChatWindowWatcher { events in
            for event in events { inbox.yield(.event(event)) }
        }
        watcher.start()
        chatWindow = watcher
        watchTrust()
    }

    /// Разрешение выдают в Системных настройках, пока приложение работает, — подхватываем без перезапуска.
    private func watchTrust() {
        trustTimer?.invalidate()
        guard !model.accessibilityTrusted else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, ChatWindowWatcher.isTrusted else { return }
                self.model.accessibilityTrusted = true
                self.trustTimer?.invalidate()
                self.trustTimer = nil
            }
        }
    }

    func setChatWindowEnabled(_ enabled: Bool) {
        if enabled && !ChatWindowWatcher.isTrusted {
            let alert = NSAlert()
            alert.messageText = "Следить за чатом в приложении Claude?"
            alert.informativeText = """
                У приложения Claude нет канала событий, поэтому Agent Pulse смотрит на кнопки в его окне \
                через «Универсальный доступ»: идёт ли ответ, ждёт ли Claude одобрения. Текст переписки не читается.

                macOS попросит разрешение: Системные настройки → Конфиденциальность и безопасность → \
                Универсальный доступ → включите Agent Pulse.
                """
            alert.addButton(withTitle: "Продолжить")
            alert.addButton(withTitle: "Отмена")
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            ChatWindowWatcher.requestTrust()
        }
        model.config.sources.claudeChat = enabled
        try? model.config.save()
        chatWindow?.stop()
        chatWindow = nil
        startChatWindow()
    }

    /// Снимок кнопок окна Claude (без текста переписки) — чтобы выставить точные признаки генерации.
    func saveChatWindowSnapshot() {
        let watcher = chatWindow ?? ChatWindowWatcher { _ in }
        watcher.snapshot { text in
            let url = PulsePaths.supportDirectory.appending(path: "claude-window.txt")
            try? FileManager.default.createDirectory(at: PulsePaths.supportDirectory, withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    /// Figma, как и Chrome, грузит плагин из постоянной копии — бандл пересобирается.
    @discardableResult
    private func copyFigmaPlugin() -> URL? {
        guard let source = Bundle.main.resourceURL?.appending(path: "FigmaCompanion"),
              FileManager.default.fileExists(atPath: source.path) else { return nil }
        let stable = PulsePaths.supportDirectory.appending(path: "FigmaCompanion", directoryHint: .isDirectory)
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: PulsePaths.supportDirectory, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: stable)
        try? fileManager.copyItem(at: source, to: stable)
        return stable
    }

    func revealFigmaPlugin() {
        guard let stable = copyFigmaPlugin() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([stable.appending(path: "manifest.json")])
    }

    func setCoworkEnabled(_ enabled: Bool) {
        model.config.sources.cowork = enabled
        try? model.config.save()
        cowork?.stop()
        cowork = nil
        startCowork()
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

    func setScreen(_ screen: String) {
        model.config.display.screen = screen
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

    /// `pulse-hook` рядом с исполняемым файлом приложения (в бандле и при `swift run`).
    private var hookPath: String? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let hook = executable.deletingLastPathComponent().appending(path: "pulse-hook")
        return FileManager.default.isExecutableFile(atPath: hook.path) ? hook.path : nil
    }

    private var hookCommand: String? {
        hookPath.map { "\"\($0)\"" }
    }

    /// Хуки и мост браузера ставились с согласия пользователя. Если приложение с тех пор переехало,
    /// они указывают на старый `pulse-hook` — молча чиним путь (с бэкапом settings.json) и обновляем копии
    /// расширения и плагина, чтобы в них были свежие версии.
    private func repairInstallations() {
        guard let hookPath, let hookCommand else { return }
        if model.hooksInstalled, HookInstaller.needsUpdate(command: hookCommand) {
            _ = try? HookInstaller.install(command: hookCommand)
        }
        if model.browserBridgeInstalled {
            if BrowserBridgeInstaller.needsUpdate(hookPath: hookPath) {
                _ = try? BrowserBridgeInstaller.install(hookPath: hookPath)
            }
            try? copyExtension()
        }
        let plugin = PulsePaths.supportDirectory.appending(path: "FigmaCompanion", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: plugin.path) {
            copyFigmaPlugin()
        }
    }

    // MARK: - Запуск при входе

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            showAlert("Не получилось", "\(error.localizedDescription)")
        }
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Браузер

    /// Расширение в бандле (кладёт scripts/bundle.sh). Chrome грузит его из постоянной копии
    /// в Application Support — бандл пересобирается и исчезает, копия остаётся.
    private var bundledExtensionURL: URL? {
        let url = Bundle.main.resourceURL?.appending(path: "ChromeExtension")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    private var extensionURL: URL {
        PulsePaths.supportDirectory.appending(path: "ChromeExtension", directoryHint: .isDirectory)
    }

    private func copyExtension() throws {
        guard let source = bundledExtensionURL else { return }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: PulsePaths.supportDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: extensionURL.path) {
            try fileManager.removeItem(at: extensionURL)
        }
        try fileManager.copyItem(at: source, to: extensionURL)
    }

    func installBrowserBridge() {
        guard let hook = hookPath else {
            showAlert("Не найден pulse-hook", "Соберите приложение скриптом scripts/bundle.sh.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Подключить Claude в браузере?"
        alert.informativeText = """
            Agent Pulse зарегистрирует мост для расширения в Chrome и других Chromium-браузерах \
            (файл в NativeMessagingHosts). Затем установите само расширение: \
            chrome://extensions → «Режим разработчика» → «Загрузить распакованное» → папка, которая откроется.

            Расширение передаёт только состояние страницы (думает, ждёт, готово), без текста переписки.
            """
        alert.addButton(withTitle: "Подключить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try copyExtension()
            let installed = try BrowserBridgeInstaller.install(hookPath: hook)
            model.browserBridgeInstalled = !installed.isEmpty
            if installed.isEmpty {
                showAlert("Браузер не найден", "Не нашлось ни Chrome, ни другого Chromium-браузера.")
                return
            }
            revealExtension()
        } catch {
            showAlert("Мост не установлен", "\(error)")
        }
    }

    func uninstallBrowserBridge() {
        do {
            try BrowserBridgeInstaller.uninstall()
            model.browserBridgeInstalled = false
        } catch {
            showAlert("Мост не удалён", "\(error)")
        }
    }

    func revealExtension() {
        if !FileManager.default.fileExists(atPath: extensionURL.path) { try? copyExtension() }
        NSWorkspace.shared.activateFileViewerSelecting([extensionURL])
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
