import AgentPulseCore
import AppKit
import Observation

enum CalendarScope: String, CaseIterable {
    case day, week, month

    var title: String {
        switch self {
        case .day: "День"
        case .week: "Неделя"
        case .month: "Месяц"
        }
    }
}

/// Модель Пульта: модули, директор и что сейчас на экране. Мозг маскота получает от неё только `ToolSignal`.
@MainActor
@Observable
final class ConsoleModel {
    private(set) var limits = LimitsModule()
    private(set) var prompter = PrompterModule()
    private(set) var calendar = CalendarModule()
    private(set) var shelf = ShelfModule()
    private(set) var media = MediaModule()
    private(set) var director = ConsoleDirector()
    private(set) var now = Date()
    private(set) var hovering = false
    private(set) var expanded = false
    /// Открытая вкладка.
    var tab = ConsoleModuleID.limits
    var calendarScope = CalendarScope.day
    var calendarDay = Date()
    /// Над Пультом несут файл.
    var dropTargeted = false
    /// Миниатюра последнего файла на полке и обложка трека.
    private(set) var shelfThumbnail: NSImage?
    private(set) var artwork: NSImage?
    /// Сколько места оставляет Dock.
    var fit = ConsoleFit.full(width: ConsoleLayout.maxWidth) { didSet { if fit != oldValue { onLayoutChange?() } } }
    var expandedWidth = ConsoleLayout.expandedMaxWidth
    /// Пульт на левом краю экрана: растёт вправо. Зеркально — влево.
    var onLeft = true
    var enabled = true
    var limitsEnabled = true
    var prompterEnabled = true
    var calendarEnabled = false
    var shelfEnabled = true
    var musicEnabled = true
    /// Громкость системного выхода, 0…1; nil — у устройства её нельзя менять.
    var volume: Double?

    /// Текст в поле суфлёра.
    var prompterDraft = ""
    /// Вместо поля открыт список недавних текстов.
    var prompterRecentOpen = false
    private(set) var prompterLibrary = PrompterLibrary.load()
    private(set) var prompterLines: [PrompterScript.Line] = []
    /// Текущая строка. Отдельно от `prompter`: панель перерисовывается по строкам, а не по таймеру.
    private(set) var prompterLine = 0
    /// Высота выреза экрана, под которым стоит суфлёр.
    var prompterNotch = 0.0
    /// Голос недоступен: почему.
    var prompterVoiceProblem: String?
    private(set) var prompterSpeedShownUntil = Date.distantPast

    /// Сигнал для мозга маскота.
    @ObservationIgnored var onSignal: ((ToolSignal, Date) -> Void)?
    /// Новый лидер: маскот на мгновение смотрит на Пульт.
    @ObservationIgnored var onLeaderChange: (() -> Void)?
    /// Изменилось то, от чего зависит размер панели.
    @ObservationIgnored var onLayoutChange: (() -> Void)?
    /// Открыть ссылку на звонок.
    @ObservationIgnored var onJoin: ((URL) -> Void)?
    @ObservationIgnored var onMediaCommand: ((MediaCommand) -> Void)?
    @ObservationIgnored var onSeek: ((TimeInterval) -> Void)?
    @ObservationIgnored var onVolume: ((Double) -> Void)?
    @ObservationIgnored var onConnectMusic: (() -> Void)?
    /// Суфлёр начался или кончился.
    @ObservationIgnored var onPrompterChange: ((Bool) -> Void)?
    /// Идти за голосом или перестать.
    @ObservationIgnored var onPrompterVoice: ((Bool) -> Void)?
    /// Изменилась скорость: запомнить в настройках.
    @ObservationIgnored var onPrompterSpeed: ((Int) -> Void)?
    /// Галочка «За голосом» во вкладке: настройки сохраняет приложение.
    @ObservationIgnored var onPrompterVoiceToggle: ((Bool) -> Void)?
    @ObservationIgnored private var prompterTimer: Timer?
    @ObservationIgnored private var lastTick = Date.distantPast
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var quietOn = false
    /// Размер, под который уже выложена панель.
    @ObservationIgnored var placedSize = CGSize.zero

    /// Новый модуль — одна строка здесь.
    private var modules: [any ConsoleModule] {
        var list: [any ConsoleModule] = []
        if limitsEnabled { list.append(limits) }
        if prompterEnabled { list.append(prompter) }
        if calendarEnabled { list.append(calendar) }
        if shelfEnabled { list.append(shelf) }
        if musicEnabled { list.append(media) }
        return list
    }

    var tabs: [(id: ConsoleModuleID, title: String)] {
        modules.map { ($0.id, $0.title) }
    }

    private var candidates: [ConsoleCandidate] {
        modules.compactMap { module in
            module.priority(now: now).map { ConsoleCandidate(module: module.id, priority: $0) }
        }
    }

    private var leaderModule: (any ConsoleModule)? {
        modules.first { $0.id == director.leader?.module }
    }

    /// Что в капсуле: лидер.
    var capsule: CapsuleContent? {
        leaderModule?.capsule(now: now)
    }

    /// До трёх точек других модулей, которым есть что показать. С кнопкой им нет места: строка важнее.
    var indicators: [UInt32] {
        guard capsule?.action == nil else { return [] }
        return modules.filter { $0.id != director.leader?.module && $0.priority(now: now) != nil }.prefix(3).map(\.accent)
    }

    /// Картинка лидера вместо иконки: миниатюра файла, обложка.
    var leaderImage: NSImage? {
        switch director.leader?.module {
        case .shelf: shelfThumbnail
        case .media: artwork
        default: nil
        }
    }

    var alert: ConsoleAlert? { director.alert }

    // MARK: - Данные модулей

    func ingest(_ snapshot: LimitSnapshot) {
        now = Date()
        apply(limits.book.ingest(snapshot, now: now))
        refresh(agentWaiting: false)
    }

    func markResting(_ service: LimitService) {
        now = Date()
        apply(limits.book.markResting(service))
        refresh(agentWaiting: false)
    }

    func updateCalendar(_ events: [MeetingEvent]) {
        now = Date()
        calendar.update(events: events)
        tickModules()
        refresh(agentWaiting: false)
    }

    func addToShelf(_ urls: [URL]) {
        guard shelfEnabled else { return }
        now = Date()
        apply(shelf.add(urls))
        if let last = shelf.items.last { loadThumbnail(last.url) }
        refresh(agentWaiting: false)
    }

    func removeFromShelf(_ url: URL) {
        shelf.remove(url)
        if shelf.items.isEmpty { shelfThumbnail = nil } else if let last = shelf.items.last { loadThumbnail(last.url) }
        refresh(agentWaiting: false)
    }

    func clearShelf() {
        shelf.clear()
        shelfThumbnail = nil
        refresh(agentWaiting: false)
    }

    private func loadThumbnail(_ url: URL) {
        Task { [weak self] in
            let image = await ShelfThumbnails.image(for: url)
            self?.shelfThumbnail = image
        }
    }

    func updateMedia(_ update: MediaRemoteStream.Update) {
        now = Date()
        switch update {
        case .playing(let playing):
            let keepArtwork = playing.artwork == nil && media.playing?.title == playing.title
            if !keepArtwork { artwork = playing.artwork.flatMap(NSImage.init(data:)) }
            media.playing = playing
        case .nothing:
            media.playing = nil
            artwork = nil
        }
        media.availability = .available
        refresh(agentWaiting: false)
    }

    func setMediaAvailability(_ availability: MediaAvailability) {
        media.availability = availability
    }

    // MARK: - Суфлёр

    var prompterTabOpen: Bool { expanded && tab == .prompter }

    private var prompterText: String? {
        let draft = prompterDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft.isEmpty ? prompterLibrary.texts.first : draft
    }

    /// ⌃⌥P: старт или стоп. Читать нечего — открывает вкладку.
    func togglePrompter() {
        guard prompterEnabled else { return }
        if prompter.isActive {
            stopPrompter()
        } else if prompterText != nil {
            startPrompter()
        } else {
            setExpanded(true)
            tab = .prompter
        }
    }

    func startPrompter() {
        guard !prompter.isActive, let text = prompterText else { return }
        now = Date()
        guard prompter.start(text: text, now: now) else { return }
        prompterLibrary.remember(text)
        prompterLibrary.save()
        prompterLines = prompter.script.lines(fits: PrompterLook.fits)
        prompterLine = 0
        setExpanded(false)
        // Тишина — сразу, а не на следующем тике.
        tickModules()
        refresh(agentWaiting: false)
        prompterTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advancePrompter() }
        }
        onPrompterChange?(true)
        if prompter.followsVoice { onPrompterVoice?(true) }
    }

    func stopPrompter() {
        guard prompter.isActive else { return }
        prompter.stop()
        finishPrompter()
    }

    private func finishPrompter() {
        prompterTimer?.invalidate()
        prompterTimer = nil
        now = Date()
        onPrompterVoice?(false)
        onPrompterChange?(false)
        tickModules()
        refresh(agentWaiting: false)
    }

    private func advancePrompter() {
        let finished = prompter.advance(now: Date())
        if finished {
            finishPrompter()
        } else {
            let line = PrompterScript.lineIndex(of: prompter.word, in: prompterLines)
            if line != prompterLine { prompterLine = line }
        }
    }

    func togglePrompterPause() {
        prompter.togglePause(now: Date())
    }

    func changePrompterSpeed(faster: Bool) {
        prompter.changeSpeed(faster: faster)
        prompterSpeedShownUntil = Date().addingTimeInterval(1.5)
        onPrompterSpeed?(prompter.speed)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            self?.prompterSpeedShownUntil = .distantPast
        }
    }

    func setPrompterSpeed(_ value: Int) {
        prompter.setSpeed(value)
    }

    func setPrompterFollowsVoice(_ on: Bool) {
        prompter.followsVoice = on
        prompterVoiceProblem = nil
        if prompter.isActive { onPrompterVoice?(on) }
    }

    func prompterVoiceFailed(_ problem: String) {
        prompter.followsVoice = false
        prompterVoiceProblem = problem
    }

    func prompterHeard(_ words: [String]) {
        prompter.hear(words, now: Date())
    }

    /// Строка в углу панели: пауза, ожидание голоса, новая скорость.
    var prompterStatus: String? {
        if Date() < prompterSpeedShownUntil { return "\(prompter.speed) слов в минуту" }
        if prompter.mode == .paused { return "Пауза" }
        if prompter.voiceHolds(now: Date()) { return "Жду голос" }
        return nil
    }

    func forgetPrompterText(_ text: String) {
        prompterLibrary.remove(text)
        prompterLibrary.save()
    }

    /// Текстовый файл в поле суфлёра: читается только то, что ты бросил сам.
    func dropped(_ urls: [URL]) {
        guard prompterTabOpen, !prompter.isActive else {
            addToShelf(urls)
            return
        }
        guard let url = urls.first(where: { ["txt", "md"].contains($0.pathExtension.lowercased()) }),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        prompterDraft = text
    }

    // MARK: - Тик

    /// Раз в секунду: сброс окон, удержание лидера, обратный отсчёт. Содержимое не меняется — кадров нет.
    func tick(now: Date, agentWaiting: Bool, inputActive: Bool) {
        guard now.timeIntervalSince(lastTick) >= 1 else { return }
        lastTick = now
        if inputActive { director.noteInput(seconds: 1) }
        self.now = now
        tickModules()
        refresh(agentWaiting: agentWaiting)
    }

    private func tickModules() {
        apply(limits.tick(now: now))
        if calendarEnabled { apply(calendar.tick(now: now)) }
        let quiet = modules.contains { $0.wantsQuiet(now: now) }
        if quiet != quietOn {
            quietOn = quiet
            apply([.quiet(quiet)])
        }
    }

    private func apply(_ signals: [ToolSignal]) {
        for signal in signals {
            onSignal?(signal, now)
            if signal.isAlert { director.raiseAlert(color: ConsoleLook.alertColor) }
            if signal.drawsGlance { onLeaderChange?() }
        }
    }

    private func refresh(agentWaiting: Bool) {
        let before = director.leader
        director.update(candidates: candidates, now: now, agentWaiting: agentWaiting, expanded: expanded)
        if director.leader != before { onLeaderChange?() }
        // Раскладка читает настройки Dock: только когда размер правда изменился, а не на каждом тике.
        if panelSize != placedSize { onLayoutChange?() }
    }

    // MARK: - Состояния

    func setHover(_ inside: Bool) {
        hoverTask?.cancel()
        guard inside else {
            hovering = false
            onLayoutChange?()
            return
        }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            self.hovering = true
            self.onLayoutChange?()
        }
    }

    func setExpanded(_ on: Bool) {
        guard on != expanded else { return }
        if on {
            // Открываем то, что занимает капсулу.
            let ids = modules.map(\.id)
            if let leader = director.leader?.module, ids.contains(leader) {
                tab = leader
            } else if !ids.contains(tab), let first = ids.first {
                tab = first
            }
            calendarDay = now
        }
        expanded = on
        onLayoutChange?()
    }

    func toggle() { setExpanded(!expanded) }

    // MARK: - Размеры

    var showsDot: Bool {
        if dropTargeted { return false }
        if case .dot = fit { return true }
        return capsule == nil
    }

    /// Кольца в капсуле; при подписи — одно, того, о ком она.
    var visibleRings: [CapsuleRing] {
        let rings = capsule?.rings ?? []
        return showsLabel ? rings.filter { $0.service == capsule?.labelService } : rings
    }

    /// Показать подпись: курсор над капсулой и хватает места. У встречи и трека строка видна и так.
    var showsLabel: Bool {
        guard hovering, !expanded, capsule != nil, capsule?.text == nil, case .full = fit else { return false }
        return true
    }

    /// Строка в капсуле, если на неё хватает места.
    var capsuleText: String? {
        guard case .full = fit else { return nil }
        return capsule?.text ?? (showsLabel ? capsule?.label : nil)
    }

    /// Ширина капсулы по содержимому: 96–220 pt; Dock может её сузить.
    var capsuleWidth: Double {
        guard !showsDot else { return ConsoleLayout.dotSize }
        let limit: Double = switch fit {
        case .full(let width): width
        case .leader, .dot: ConsoleLayout.minWidth
        }
        let dots = Double(indicators.count)
        let extras = (capsule?.action != nil ? ConsoleLook.joinWidth + ConsoleLook.labelGap : 0)
            + (dots > 0 ? ConsoleLook.labelGap + dots * ConsoleLook.dot + (dots - 1) * 4 : 0)
        guard let text = capsuleText else { return min(max(ConsoleLayout.minWidth, 0), limit) }
        let full = capsule?.tail.map { "\(text) \($0)" } ?? text
        let width = (full as NSString).size(withAttributes: [.font: ConsoleLook.labelFont]).width
        return min(limit, max(ConsoleLayout.minWidth, ConsoleLook.ring + ConsoleLook.labelGap + ceil(width) + extras + ConsoleLook.padding * 2))
    }

    var capsuleHeight: Double { showsDot ? ConsoleLayout.dotSize : ConsoleLayout.capsuleHeight }

    var panelSize: CGSize {
        guard expanded else { return CGSize(width: capsuleWidth, height: capsuleHeight) }
        return CGSize(width: expandedWidth, height: ConsoleLayout.expandedHeight + ConsoleLayout.expandedGap + capsuleHeight)
    }
}

/// Размеры капсулы вне ядра: шрифт есть только у AppKit.
enum ConsoleLook {
    static let ring = 18.0
    static let ringGap = 8.0
    static let labelGap = 8.0
    static let padding = 12.0
    static let joinWidth = 40.0
    static let dot = 6.0
    static let alertColor: UInt32 = 0xFF453A
    @MainActor static let labelFont: NSFont = {
        let base = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 12) } ?? base
    }()
}
