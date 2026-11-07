import AgentPulseCore
import Carbon.HIToolbox
import AppKit
import os
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = PulseModel()
    private let notifier = Notifier()
    private(set) var panel: OverlayPanel?
    private(set) var consolePanel: ConsolePanel?
    private let consoleHotKey = ConsoleHotKey(id: 1)
    private let prompterHotKey = ConsoleHotKey(id: 2)
    private let prompterFaster = ConsoleHotKey(id: 3)
    private let prompterSlower = ConsoleHotKey(id: 4)
    private let prompterVoice = PrompterVoice()
    private let dictationHotKey = ConsoleHotKey(id: 5)
    private let translateHotKey = ConsoleHotKey(id: 6)
    private(set) var dictation: DictationController?
    private var menuPanel: PulseMenuPanel?
    private var prompterPanel: PrompterPanel?
    private var codexTimer: Timer?
    private var codexFetchedAt = Date.distantPast
    private var codexFetching = false
    private let calendarProvider = CalendarProvider()
    private let screenshots = ScreenshotWatcher()
    private var mediaSense: MediaPlayerSense?
    private var server: SocketServer?
    private var cowork: CoworkWatcher?
    private var orca: OrcaWatcher?
    private var companion: LocalHTTPServer?
    private var chatWindow: ChatWindowWatcher?
    private var senses: [Sense] = []
    private var settingsWindow: NSWindow?
    private var trustTimer: Timer?
    private var screenTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ConsoleStyle.registerFont()
        NSApp.setActivationPolicy(.accessory)
        // Отладка: `--design-sheet out.png` — нарисовать ключевые позы и выйти.
        if let index = CommandLine.arguments.firstIndex(of: "--design-sheet"), index + 1 < CommandLine.arguments.count {
            DesignSheet.render(to: URL(filePath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--bubble-sheet"), index + 1 < CommandLine.arguments.count {
            BubbleSheet.render(to: URL(filePath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        notifier.requestAuthorization()
        model.notifier = notifier
        model.hooksInstalled = HookInstaller.isInstalled()
        model.statuslineInstalled = StatuslineInstaller.isInstalled()
        model.statuslineBroken = StatuslineInstaller.originalIsBroken()
        model.browserBridgeInstalled = BrowserBridgeInstaller.isInstalled()
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        // `install.sh --login`: перерегистрировать, даже если включено, — после переезда бандла
        // запись «Запускать при входе» указывает на старый путь.
        if CommandLine.arguments.contains("--register-login-item") {
            if model.launchAtLogin { try? SMAppService.mainApp.unregister() }
            setLaunchAtLogin(true)
        }
        // Отладка: `open "Agent Pulse.app" --args --state sleep|idle|think|wait` — как ручное состояние в MascotLab.
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
        startConsole()

        // Панель переезжает на монитор с курсором; на её экране что-то развернули на весь экран — прячемся.
        // Опрос дешёвый и не требует никаких прав: только размеры окон, без названий и содержимого.
        screenTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel?.followActiveScreen()
                self?.followConsoleScreen()
                self?.pollFullScreen()
            }
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.watchFullScreen()
                    if name == NSWorkspace.activeSpaceDidChangeNotification { self?.ensureOnActiveSpace() }
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel?.reposition()
                self?.placeConsole()
            }
        }

        startServer()
        startCowork()
        startOrca()
        startCompanion()
        startChatWindow()
        model.start()
        startSenses()
        model.introduce(force: CommandLine.arguments.contains("--intro"))
        model.onIdleHide = { [weak self] hide in
            self?.idleHidden = hide
            self?.updatePanelVisibility()
        }
        model.onSpecial = { [weak self] action, line in
            self?.panel?.perform(action, line: line)
        }
        model.onUserBack = { [weak self] in
            self?.panel?.returnHomeIfWandering()
        }
        // Отладка: `open "Agent Pulse.app" --args --signal userAway --signal agentDone` — как SignalSimulator,
        // сигналы по очереди с интервалом в полсекунды.
        let arguments = CommandLine.arguments
        let kinds = arguments.indices.compactMap { index in
            arguments[index] == "--signal" && index + 1 < arguments.count ? SignalKind(rawValue: arguments[index + 1]) : nil
        }
        for (order, kind) in kinds.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(order) * 0.5) { [model] in model.simulate(kind) }
        }
        // Отладка: `--news-now` — загрузить ленты и сразу рассказать новость, минуя ожидание Director.
        if arguments.contains("--news-now") {
            Task { [model] in
                let items = await NewsSense.load()
                model.receiveNews(items)
                model.scheduler.quiet = false
                model.tellNews(at: Date(), duration: 8, ignoringQuiet: true)
            }
        }
        if let index = arguments.firstIndex(of: "--settings-sheet"), index + 1 < arguments.count {
            SettingsSheet.render(app: self, to: URL(filePath: arguments[index + 1]))
            exit(0)
        }
        // Отладка: `--settings sources` — сразу открыть «Настройки» на вкладке.
        if let index = arguments.firstIndex(of: "--settings") {
            let tab = index + 1 < arguments.count ? SettingsNavigation.Tab(rawValue: arguments[index + 1]) : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showSettings(tab) }
        }
        // Отладка: `--pin-space` — привязать маскота к текущему рабочему столу, как бывает после
        // показа во время перехода; смена стола должна вернуть его на все столы (`ensureOnActiveSpace`).
        if arguments.contains("--pin-space") {
            // `--pin-space hard` — как в жизни: поведение «на всех столах» на месте, а окно всё равно на одном столе.
            let hard = arguments.contains("hard")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.panel?.collectionBehavior = []
                if hard {
                    self?.panel?.orderFrontRegardless()
                    self?.panel?.collectionBehavior = OverlayPanel.spaceBehavior
                }
            }
        }
        // Отладка: `--rebuild-panel` — пересоздать панель, как последняя ступень самолечения.
        if arguments.contains("--rebuild-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.rebuildPanel() }
        }
        // Отладка: `--behavior doze` — как «Поведение вручную» в MascotLab.
        let behaviors = arguments.indices.compactMap { index in
            arguments[index] == "--behavior" && index + 1 < arguments.count ? MascotReaction(rawValue: arguments[index + 1]) : nil
        }
        for behavior in behaviors {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [model] in model.animator.enqueue(behavior) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        cowork?.stop()
        orca?.stop()
        companion?.stop()
        chatWindow?.stop()
        mediaSense?.stop()
        screenshots.stop()
        senses.forEach { $0.stop() }
        model.markCleanExit()
    }

    private func startServer() {
        let inbox = model.inbox
        let server = SocketServer(path: PulsePaths.socketPath) { data in
            // Разбор — прямо здесь, вне главного потока; время события — момент приёма.
            switch Ingest.route(data) {
            case .events(let events):
                for event in events { inbox.yield(.event(event)) }
            case .limits(let snapshot):
                inbox.yield(.limits(snapshot))
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

    /// Агенты в Orca. Claude Code оттуда же виден через хуки Pulse подробнее — без хуков берём его из Orca.
    private func startOrca() {
        orca?.stop()
        orca = nil
        guard model.config.sources.orca else {
            model.orcaWatching = nil
            return
        }
        let inbox = model.inbox
        // Установленный хук не означает, что текущий агент его загрузил.
        // Каналы объединяются по providerSession.id в OrcaStatus.
        let watcher = OrcaWatcher(includeClaude: true, includeCodex: true) { events in
            for event in events { inbox.yield(.event(event)) }
        }
        model.orcaWatching = watcher.start()
        orca = watcher
    }

    func setOrcaEnabled(_ enabled: Bool) {
        model.config.sources.orca = enabled
        try? model.config.save()
        startOrca()
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

    // MARK: - Пульт

    private func startConsole() {
        let console = model.console
        let panel = ConsolePanel(model: console)
        consolePanel = panel
        var wasExpanded = false
        console.onLayoutChange = { [weak self] in
            guard let self else { return }
            self.placeConsole()
            if console.expanded != wasExpanded {
                wasExpanded = console.expanded
                panel.expandedChanged(overFullScreen: self.fullScreenHidden)
                self.updateConsoleVisibility()
            }
        }
        placeConsole()
        updateConsoleVisibility()
        applyConsoleHotKey()
        model.onCodexActivity = { [weak self] in self?.refreshCodex(force: false) }
        // Раз в 5 мин: процесс живёт только на время запроса.
        codexTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCodex(force: true) }
        }
        refreshCodex(force: true)
        console.onJoin = { url in NSWorkspace.shared.open(url) }
        console.onMediaCommand = { [weak self] in self?.mediaSense?.send($0) }
        console.onSeek = { [weak self] in self?.mediaSense?.seek(to: $0) }
        console.onVolume = { [weak console] value in
            SystemVolume.set(value)
            console?.volume = value
        }
        console.onConnectMusic = { [weak self] in self?.startScriptMedia() }
        startPrompter()
        startDictation()
        renderConsoleSheet()
        // Отладка: `--menu-demo` — показать меню маскота без правого клика.
        if CommandLine.arguments.contains("--menu-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.showMenu() }
        }
        if model.config.console.calendar { startCalendar() }
        startMedia()
        startScreenshots()
        // Отладка: `--shelf-demo путь` — положить файл на полку, как бросок.
        if let index = CommandLine.arguments.firstIndex(of: "--shelf-demo"), index + 1 < CommandLine.arguments.count {
            console.addToShelf([URL(fileURLWithPath: CommandLine.arguments[index + 1])])
        }
        // Отладка: `--meeting-demo минут [ссылка]` — подставная встреча через столько минут.
        if let index = CommandLine.arguments.firstIndex(of: "--meeting-demo"), index + 1 < CommandLine.arguments.count {
            let minutes = Double(CommandLine.arguments[index + 1]) ?? 8
            let link = index + 2 < CommandLine.arguments.count ? URL(string: CommandLine.arguments[index + 2]).flatMap(MeetingLinks.classify) : nil
            let start = Date().addingTimeInterval(minutes * 60)
            console.calendarEnabled = true
            console.updateCalendar([MeetingEvent(id: "demo", title: "Синк", start: start, end: start.addingTimeInterval(1800), link: link)])
        }
        // Отладка: `--limits-demo [critical]` — подставные лимиты, `--console-open` — сразу раскрыть.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--limits-demo") {
            let critical = index + 1 < arguments.count && arguments[index + 1] == "critical"
            let now = Date()
            let reset = now.addingTimeInterval(2 * 3600 + 14 * 60)
            console.ingest(LimitSnapshot(service: .claude, windows: [
                LimitWindow(kind: .fiveHour, usedPercent: critical ? 96 : 76, resetsAt: reset),
                LimitWindow(kind: .week, usedPercent: 41, resetsAt: now.addingTimeInterval(4 * 86_400)),
            ], at: now))
        }
        if arguments.contains("--console-open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { console.setExpanded(true) }
        }
        // Отладка: `--console-tab media` — сразу открыть вкладку.
        if let index = arguments.firstIndex(of: "--console-tab"), index + 1 < arguments.count,
           let tab = ConsoleModuleID(rawValue: arguments[index + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                console.setExpanded(true)
                console.tab = tab
            }
        }
    }

    /// Отладка: `--console-sheet папка` — нарисовать капсулу и все страницы в файлы, без окон.
    private func renderConsoleSheet() {
        guard let index = CommandLine.arguments.firstIndex(of: "--console-sheet"), index + 1 < CommandLine.arguments.count else { return }
        let console = model.console
        let folder = URL(filePath: CommandLine.arguments[index + 1])
        let now = Date()
        console.ingest(LimitSnapshot(service: .claude, windows: [
            LimitWindow(kind: .fiveHour, usedPercent: 31, resetsAt: now.addingTimeInterval(3 * 3600 + 24 * 60)),
            LimitWindow(kind: .week, usedPercent: 84, resetsAt: now.addingTimeInterval(4 * 86_400)),
        ], at: now))
        console.ingest(LimitSnapshot(service: .codex, windows: [
            LimitWindow(kind: .fiveHour, usedPercent: 100, resetsAt: now.addingTimeInterval(1800)),
            LimitWindow(kind: .week, usedPercent: 12, resetsAt: now.addingTimeInterval(5 * 86_400)),
        ], at: now))
        console.calendarEnabled = true
        console.updateCalendar([
            MeetingEvent(id: "1", title: "Синк команды", start: now.addingTimeInterval(1800), end: now.addingTimeInterval(3600)),
            MeetingEvent(id: "2", title: "Обзор дизайна", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(9000)),
        ])
        console.addToShelf([URL(filePath: "/System/Library/CoreServices/Finder.app"), URL(filePath: "/etc/hosts")])
        console.updateMedia(.playing(NowPlaying(
            title: "Название трека", artist: "Исполнитель", isPlaying: true, duration: 240, elapsed: 80, at: now
        )))
        console.prompterDraft = "Здравствуйте! Сегодня покажу, что изменилось в Пульте."
        ConsoleSheet.render(console, app: self, to: folder)
        exit(0)
    }

    private func startDictation() {
        let console = model.console
        let controller = DictationController(console: console, settings: { [model] in model.config.console }, showSettings: { [weak self] in self?.showSettings(.console, anchor: "Диктовка") })
        dictation = controller
        console.onDictationActive = { [weak self] on in
            guard let self else { return }
            self.model.animator.watchesConsole = on ? (self.model.config.display.anchor.isRight ? -1 : 1) : nil
            self.updateConsoleVisibility()
        }
        console.onOpenSettings = { [weak self] anchor in self?.showSettings(.console, anchor: anchor) }
        applyDictationHotKeys()
        // Отладка: `--dictation-model` — скачать модель, `--dictation-demo файл.wav [секунд]` — весь путь без микрофона.
        if CommandLine.arguments.contains("--dictation-model") { controller.models.download() }
        if let index = CommandLine.arguments.firstIndex(of: "--dictation-demo"), index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            let seconds = index + 2 < CommandLine.arguments.count ? Double(CommandLine.arguments[index + 2]) ?? 4 : 4
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { controller.runDemo(path: path, holdFor: seconds) }
        }
    }

    func applyDictationHotKeys() {
        let config = model.config.console
        let console = model.console
        let dictating = dictationHotKey.set(
            code: config.enabled && config.dictation ? kVK_ANSI_D : nil,
            released: { [weak console] in console?.releaseDictation() },
            action: { [weak console] in console?.pressDictation() }
        )
        let translating = translateHotKey.set(code: config.enabled && config.translator && ConsoleTranslator.isAvailable ? kVK_ANSI_T : nil) {
            [weak self] in self?.dictation?.pressTranslate()
        }
        if !dictating || !translating { Self.log.notice("клавиша диктовки или перевода занята") }
    }

    func setDictationEnabled(_ on: Bool) {
        model.config.console.dictation = on
        try? model.config.save()
        if !on { model.console.releaseDictation() }
        model.console.dictationEnabled = on
        applyDictationHotKeys()
    }

    func setDictationLanguage(_ language: String) {
        model.config.console.dictationLanguage = language
        try? model.config.save()
    }

    func setDictationRules(_ rules: [DictationRule]) {
        model.config.console.dictationRules = rules
        try? model.config.save()
    }

    func setDictationHistory(_ on: Bool) {
        model.config.console.dictationHistory = on
        try? model.config.save()
        if !on { dictation?.clearHistory() }
    }

    func setTranslatorEnabled(_ on: Bool) {
        model.config.console.translator = on
        try? model.config.save()
        model.console.translatorEnabled = on && ConsoleTranslator.isAvailable
        applyDictationHotKeys()
    }

    /// Универсальный доступ: система спросит только сейчас, когда ты сам включил.
    func setConsoleAccessibility(_ on: Bool) {
        model.config.console.accessibility = on
        try? model.config.save()
        if on {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    private func startPrompter() {
        let console = model.console
        let panel = PrompterPanel(model: console)
        prompterPanel = panel
        console.onPrompterChange = { [weak self, weak panel] on in
            guard let self, let panel else { return }
            self.model.animator.watchesCamera = on
            // Стрелки заняты только на время суфлёра: они нужны и другим приложениям.
            self.prompterFaster.set(code: on ? kVK_UpArrow : nil) { [weak console] in console?.changePrompterSpeed(faster: true) }
            self.prompterSlower.set(code: on ? kVK_DownArrow : nil) { [weak console] in console?.changePrompterSpeed(faster: false) }
            if on {
                panel.place(fallback: self.consoleScreen, hiddenFromSharing: self.model.config.console.prompterHidden)
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }
        console.onPrompterVoice = { [weak self, weak console] on in
            guard let self else { return }
            if on, let console { self.prompterVoice.start(text: console.prompter.script.text) } else { self.prompterVoice.stop() }
        }
        console.onPrompterSpeed = { [weak self] speed in
            self?.model.config.console.prompterSpeed = speed
            try? self?.model.config.save()
        }
        console.onPrompterVoiceToggle = { [weak self] on in self?.setPrompterVoice(on) }
        prompterVoice.onWords = { [weak console] in console?.prompterHeard($0) }
        prompterVoice.onFailure = { [weak console, weak self] failure in
            console?.prompterVoiceFailed(failure.rawValue)
            self?.model.config.console.prompterVoice = false
            try? self?.model.config.save()
        }
        applyPrompterHotKey()
        // Отладка: `--prompter-demo [голос]` — сразу запустить подставной текст.
        if let index = CommandLine.arguments.firstIndex(of: "--prompter-demo") {
            console.prompterDraft = Self.prompterDemo
            if index + 1 < CommandLine.arguments.count, CommandLine.arguments[index + 1] == "голос" {
                console.setPrompterFollowsVoice(true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { console.startPrompter() }
        }
    }

    private static let prompterDemo = """
    Добрый день, коллеги. Сегодня расскажу про новый экран оплаты и про то, что мы узнали за две недели тестов.
    Начну с главного: люди стали быстрее находить нужную кнопку, а ошибок при вводе карты стало заметно меньше.
    Дальше покажу, что ещё предстоит сделать до конца месяца и где нам понадобится помощь.
    """

    func applyPrompterHotKey() {
        let on = model.config.console.enabled && model.config.console.prompter
        let registered = prompterHotKey.set(code: on ? kVK_ANSI_P : nil) { [weak self] in self?.model.console.togglePrompter() }
        if !registered { Self.log.notice("hotkey суфлёра занята") }
    }

    func setPrompterEnabled(_ on: Bool) {
        model.config.console.prompter = on
        try? model.config.save()
        if !on {
            model.console.stopPrompter()
            model.console.setExpanded(false)
        }
        model.console.prompterEnabled = on
        applyPrompterHotKey()
    }

    func setPrompterHidden(_ on: Bool) {
        model.config.console.prompterHidden = on
        try? model.config.save()
        prompterPanel?.sharingType = on ? .none : .readOnly
    }

    func setPrompterVoice(_ on: Bool) {
        model.config.console.prompterVoice = on
        try? model.config.save()
        model.console.setPrompterFollowsVoice(on)
    }

    private var consoleScreen: NSScreen? {
        panel?.screen ?? NSScreen.main
    }

    private var placedConsoleScreen: NSScreen?

    /// Пульт живёт на экране маскота.
    private func placeConsole() {
        guard let consolePanel, let screen = consoleScreen else { return }
        placedConsoleScreen = screen
        consolePanel.place(on: screen, anchor: model.config.display.anchor)
    }

    private func followConsoleScreen() {
        if consoleScreen != placedConsoleScreen { placeConsole() }
    }

    /// В полном экране Пульт скрыт, но раскрытый клавишей показывается поверх него.
    func updateConsoleVisibility() {
        guard let consolePanel else { return }
        let console = model.console
        let show = console.enabled && (!fullScreenHidden || console.showsOverFullScreen)
        if show, !consolePanel.isVisible {
            consolePanel.rejoinAllSpaces()
            consolePanel.orderFrontRegardless()
        }
        if !show, consolePanel.isVisible { consolePanel.orderOut(nil) }
    }

    func applyConsoleHotKey() {
        let enabled = model.config.console.enabled
        let registered = consoleHotKey.set(letter: enabled ? model.config.console.hotkey : "") { [weak self] in
            self?.model.console.toggle()
        }
        if !registered { Self.log.notice("hotkey занята") }
    }

    func setConsoleEnabled(_ on: Bool) {
        model.config.console.enabled = on
        try? model.config.save()
        model.console.enabled = on
        if !on { model.console.setExpanded(false) }
        updateConsoleVisibility()
        applyConsoleHotKey()
        if !on { model.console.stopPrompter() }
        model.console.prompterEnabled = on && model.config.console.prompter
        applyPrompterHotKey()
        if !on { model.console.releaseDictation() }
        applyDictationHotKeys()
    }

    func setLimitsEnabled(_ on: Bool) {
        model.config.console.limits = on
        try? model.config.save()
        model.console.limitsEnabled = on
        if on { refreshCodex(force: true) }
    }

    // MARK: - Календарь, музыка, снимки

    /// Календарь спрашивает разрешение при включении; отказали — модуль скрыт.
    func setCalendarEnabled(_ on: Bool) {
        if !on {
            model.config.console.calendar = false
            try? model.config.save()
            model.console.calendarEnabled = false
            calendarProvider.stop()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            NSApp.activate()
            let granted = await self.calendarProvider.requestAccess()
            guard granted else {
                self.showAlert("Нет доступа к календарю", "Системные настройки → Конфиденциальность и безопасность → Календари → включите Agent Pulse.")
                return
            }
            self.model.config.console.calendar = true
            try? self.model.config.save()
            self.model.console.calendarEnabled = true
            self.startCalendar()
        }
    }

    private func startCalendar() {
        guard CalendarProvider.authorized else {
            model.console.calendarEnabled = false
            return
        }
        calendarProvider.start { [weak self] events in self?.model.console.updateCalendar(events) }
    }

    func setShelfEnabled(_ on: Bool) {
        model.config.console.shelf = on
        try? model.config.save()
        model.console.shelfEnabled = on
        if !on { model.console.clearShelf() }
        startScreenshots()
    }

    func setShelfScreenshots(_ on: Bool) {
        model.config.console.shelfScreenshots = on
        try? model.config.save()
        startScreenshots()
    }

    private func startScreenshots() {
        screenshots.stop()
        guard model.config.console.shelf, model.config.console.shelfScreenshots else { return }
        screenshots.start { [weak self] urls in self?.model.console.addToShelf(urls) }
    }

    func setMusicEnabled(_ on: Bool) {
        model.config.console.music = on
        try? model.config.save()
        model.console.musicEnabled = on
        startMedia()
    }

    /// Сначала MediaRemote: он видит любой плеер. Не работает — честно «недоступно», а запасной путь по кнопке.
    private func startMedia() {
        mediaSense?.stop()
        mediaSense = nil
        let console = model.console
        console.updateMedia(.nothing)
        guard model.config.console.music else { return }
        console.volume = SystemVolume.get()
        guard let sense = AdapterMediaSense() else {
            console.setMediaAvailability(.unavailable)
            return
        }
        mediaSense = sense
        sense.start(onUpdate: { update in
            console.updateMedia(update)
            console.volume = SystemVolume.get()
        }, onFailure: { [weak self] in
            self?.mediaSense = nil
            console.setMediaAvailability(.unavailable)
        })
    }

    /// AppleScript для «Музыки» и Spotify: разрешение Automation спросит сама macOS.
    private func startScriptMedia() {
        let console = model.console
        let sense = ScriptMediaSense()
        mediaSense = sense
        sense.start(onUpdate: { console.updateMedia($0) }, onFailure: {})
    }

    func setConsoleHotKey(_ letter: String) {
        model.config.console.hotkey = letter
        try? model.config.save()
        applyConsoleHotKey()
    }

    func setCodexPath(_ path: String) {
        model.config.console.codexPath = path.isEmpty ? nil : path
        try? model.config.save()
        refreshCodex(force: true)
    }

    func setCodexHome(_ home: String) {
        model.config.console.codexHome = home.isEmpty ? nil : home
        try? model.config.save()
        refreshCodex(force: true)
    }

    /// Лимиты Codex: раз в 5 мин и после его событий, но не чаще раза в минуту.
    private func refreshCodex(force: Bool) {
        let settings = model.config.console
        guard settings.enabled, settings.limits, !codexFetching else { return }
        guard force || Date().timeIntervalSince(codexFetchedAt) >= 60 else { return }
        guard let codex = CodexAppServer.locate(configured: settings.codexPath) else {
            model.codexStatus = "codex не найден"
            return
        }
        codexFetching = true
        codexFetchedAt = Date()
        let inbox = model.inbox
        Task { [weak self] in
            let snapshot = await CodexAppServer.fetch(codex: codex, home: settings.codexHome)
            if let snapshot { inbox.yield(.limits(snapshot)) }
            self?.codexFetching = false
            self?.model.codexStatus = snapshot == nil ? "нет данных: нужен codex login" : "работает"
        }
    }

    private var statuslinePath: String? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let wrapper = executable.deletingLastPathComponent().appending(path: StatuslineInstaller.marker)
        return FileManager.default.isExecutableFile(atPath: wrapper.path) ? wrapper.path(percentEncoded: false) : nil
    }

    func installStatusline() {
        guard let path = statuslinePath else {
            showAlert("Не найден pulse-statusline", "Он должен лежать рядом с приложением. Соберите проект скриптом scripts/bundle.sh.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Подключить лимиты Claude?"
        alert.informativeText = """
            Agent Pulse обернёт команду statusLine в ~/.claude/settings.json. Ваша строка продолжит работать как раньше:             ей передаётся тот же ввод, её вывод не меняется. Рядом будет создана резервная копия файла,             отключение вернёт исходную команду.

            Pulse берёт только проценты и время сброса. Ничего не уходит с машины.
            """
        alert.addButton(withTitle: "Подключить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try StatuslineInstaller.install(wrapperPath: path)
            model.statuslineInstalled = true
        } catch {
            showAlert("Лимиты не подключены", "\(error)")
        }
    }

    func uninstallStatusline() {
        do {
            try StatuslineInstaller.uninstall()
            model.statuslineInstalled = false
        } catch {
            showAlert("Обёртка не снята", "\(error)")
        }
    }

    // MARK: - Органы чувств

    func startSenses() {
        senses.forEach { $0.stop() }
        let inbox = model.inbox
        senses = SenseRegistry.make(model.config) { [model] items in model.receiveNews(items) }
        for sense in senses {
            sense.start { signal in inbox.yield(.signal(signal)) }
        }
    }

    func setNewsTopic(_ topic: NewsTopic, on: Bool) {
        var topics = model.config.character.enabledNewsTopics
        if on { topics.insert(topic) } else { topics.remove(topic) }
        model.config.character.newsTopics = NewsTopic.allCases.filter(topics.contains).map(\.rawValue)
        try? model.config.save()
        startSenses()
    }

    func setDesignNews(_ on: Bool) {
        model.config.character.designNews = on
        try? model.config.save()
        startSenses()
        if !on { model.simulate(.newsFresh, value: 0) }
    }

    /// Облик маскота: `PalSkin.classic` или `agent-pals/<Бот>`.
    func setSkin(_ skin: String) {
        model.config.mascot.skin = skin
        try? model.config.save()
    }

    func setGravity(_ on: Bool) {
        model.config.display.gravity = on
        try? model.config.save()
        panel?.gravityChanged()
    }

    private let settingsSelection = SettingsSelection()

    /// Одно окно «Настройки» с вкладками; `tab` — сразу открыть нужную. Пока окно открыто,
    /// у приложения есть иконка в Dock и меню — как у обычного окна настроек; закрыли — снова только маскот.
    func showMenu() {
        let menu = menuPanel ?? PulseMenuPanel(app: self)
        menuPanel = menu
        menu.show(at: NSEvent.mouseLocation)
    }

    func showSettings(_ tab: SettingsNavigation.Tab? = nil, anchor: String? = nil) {
        if let tab { settingsSelection.tab = tab }
        settingsSelection.anchor = anchor
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsRoot(app: self, selection: settingsSelection))
            controller.sizingOptions = [.preferredContentSize]
            // Заголовок прозрачный и лежит поверх содержимого: запас под него дал бы пустую полосу внизу окна.
            controller.safeAreaRegions = []
            let window = NSWindow(contentViewController: controller)
            window.title = "Настройки"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Клик по иконке в Dock или повторный запуск из Launchpad — открыть настройки.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func setMascotSize(_ size: Double) {
        model.config.display.mascotSize = size
        try? model.config.save()
        panel?.reposition()
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
        updatePanelVisibility()
    }

    // MARK: - Видимость панели

    /// Журнал видимости: `log show --predicate 'subsystem == "io.github.egorovdnikita.agentpulse"' --last 1d`.
    static let log = Logger(subsystem: "io.github.egorovdnikita.agentpulse", category: "panel")
    private var idleHidden = false
    private var fullScreenHidden = false

    /// Маскот виден, если его не выключили, он не спрятался от долгого простоя
    /// и на его экране ничего не развёрнуто на весь экран **[решение]**.
    func updatePanelVisibility() {
        guard let panel else { return }
        let show = model.overlayVisible && !idleHidden && !fullScreenHidden
        model.overlayOccluded = !show
        if show != panel.isVisible {
            Self.log.notice("panel \(show ? "show" : "hide", privacy: .public): visible=\(self.model.overlayVisible) idle=\(self.idleHidden) fullscreen=\(self.fullScreenHidden)")
        }
        if show, !panel.isVisible {
            panel.rejoinAllSpaces()
            panel.orderFrontRegardless()
        }
        if !show, panel.isVisible { panel.orderOut(nil) }
    }

    /// Самолечение: после смены рабочего стола маскот должен быть и здесь. Если панель видима,
    /// но на этом столе её нет (и это не полноэкранный стол, где её нет нарочно) — возвращаем на все столы.
    /// Одного переобъявления «на всех столах» мало: 3 ноября после полноэкранного Chrome оно срабатывало
    /// 12 раз подряд и не помогало — WindowServer держал окно на одном столе. Поэтому по ступеням:
    /// 1) убрать окно и выложить заново; 2) не помогло — пересоздать панель (новое окно на всех столах).
    private func ensureOnActiveSpace() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.panelStuck else { return }
            Self.log.notice("panel rejoin: была только на одном рабочем столе — выкладываю заново")
            self.panel?.orderOut(nil)
            self.panel?.rejoinAllSpaces()
            self.panel?.orderFrontRegardless()
            self.rejoinConsole()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.panelStuck else { return }
                Self.log.notice("panel rebuild: выкладка не помогла — пересоздаю панель")
                self.rebuildPanel()
            }
        }
    }

    private func rejoinConsole() {
        guard let consolePanel, consolePanel.isVisible, !consolePanel.isOnActiveSpace else { return }
        consolePanel.orderOut(nil)
        consolePanel.rejoinAllSpaces()
        consolePanel.orderFrontRegardless()
    }

    /// Панель видима, но на текущем обычном рабочем столе её нет.
    private var panelStuck: Bool {
        guard let panel, panel.isVisible else { return false }
        return !panel.isOnActiveSpace && !fullScreenHidden && NSMenu.menuBarVisible()
    }

    /// Новое окно вместо прилипшего: позиция, видимость и маскот те же — модель общая.
    private func rebuildPanel() {
        let old = panel
        let fresh = OverlayPanel(app: self)
        panel = fresh
        fresh.orderFrontRegardless()
        // Без close(): у программно созданного окна он отпускает объект дважды. Ссылок больше нет — уйдёт само.
        old?.orderOut(nil)
        updatePanelVisibility()
    }

    /// Сколько проверок подряд экран закрыт: переход между рабочими столами мелькает на мгновение,
    /// полноэкранное видео держится — прячемся после двух проверок подряд (~1 s).
    private var coveredStreak = 0
    /// Список окон стоит заметно (и нам, и WindowServer): в спокойном состоянии смотрим раз в 2 s,
    /// а сразу после смены рабочего стола или приложения и пока подозреваем полный экран — каждые 0.5 s.
    private var fullScreenTick = 0
    private var fullScreenWatchUntil = Date.distantPast

    private func watchFullScreen() {
        fullScreenWatchUntil = Date().addingTimeInterval(3)
        checkFullScreen()
    }

    private func pollFullScreen() {
        fullScreenTick += 1
        let eager = fullScreenHidden || coveredStreak > 0 || Date() < fullScreenWatchUntil
        guard eager || fullScreenTick % 4 == 0 else { return }
        checkFullScreen()
    }

    private func checkFullScreen() {
        guard let panel, let screen = panel.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) else { return }
        // Окно на весь экран должно быть у приложения, с которым ты сейчас работаешь.
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // И строка меню на этом экране скрыта: на обычном рабочем столе она видна всегда.
        let covered = (front.map { QuietSense.fullScreenWindow(on: screen, owner: $0) } ?? false)
            && !QuietSense.menuBarVisible(on: screen)
        coveredStreak = covered ? coveredStreak + 1 : 0
        let hide = coveredStreak >= 2
        guard hide != fullScreenHidden else { return }
        fullScreenHidden = hide
        // Без имени приложения: маскот не знает, чем ты занят.
        Self.log.notice("fullscreen \(hide ? "on" : "off", privacy: .public)")
        updatePanelVisibility()
        updateConsoleVisibility()
    }

    func setAnchor(_ anchor: PulseConfig.Display.Anchor) {
        model.config.display.anchor = anchor
        try? model.config.save()
        panel?.reposition()
        placeConsole()
    }

    func setScreen(_ screen: String) {
        model.config.display.screen = screen
        try? model.config.save()
        panel?.reposition()
    }

    // MARK: - Хуки

    /// `pulse-hook` рядом с исполняемым файлом приложения (в бандле и при `swift run`).
    private var hookPath: String? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let hook = executable.deletingLastPathComponent().appending(path: "pulse-hook")
        return FileManager.default.isExecutableFile(atPath: hook.path) ? hook.path : nil
    }

    private var hookCommand: String? {
        hookPath.map(HookInstaller.command(hookPath:))
    }

    /// Хуки и мост браузера ставились с согласия пользователя. Если приложение с тех пор переехало,
    /// они указывают на старый `pulse-hook` — молча чиним путь (с бэкапом settings.json) и обновляем копии
    /// расширения и плагина, чтобы в них были свежие версии.
    private func repairInstallations() {
        guard let hookPath, let hookCommand else { return }
        if model.hooksInstalled, HookInstaller.needsUpdate(command: hookCommand) {
            _ = try? HookInstaller.install(command: hookCommand)
        }
        if model.statuslineInstalled, let statuslinePath { StatuslineInstaller.repair(wrapperPath: statuslinePath) }
        // Копии у Codex (ChatGPT, Orca) тоже получают новую команду — переезд или удаление приложения их не ломает.
        HookInstaller.repairCopies(command: hookCommand)
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
            startOrca()
        } catch {
            showAlert("Хуки не установлены", "\(error)")
        }
    }

    /// Снимает хуки отовсюду: Claude Code и копии у Codex (ChatGPT, Orca). С бэкапами.
    func uninstallHooks() {
        do {
            try HookInstaller.uninstallEverywhere()
            model.hooksInstalled = false
            startOrca()
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
