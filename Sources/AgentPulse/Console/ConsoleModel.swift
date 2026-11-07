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
    private(set) var dictation = DictationModule()
    private(set) var translate = TranslateModule()
    private(set) var calendar = CalendarModule()
    private(set) var shelf = ShelfModule()
    private(set) var media = MediaModule()
    private(set) var director = ConsoleDirector()
    private(set) var now = Date()
    private(set) var expanded = false
    /// Открытая вкладка.
    var tab = ConsoleModuleID.shelf
    var calendarScope = CalendarScope.day
    var calendarDay = Date()
    /// Сколько месяцев вперёд открыто: события загружаются на два.
    var calendarMonth = 0
    /// Над Пультом несут файл.
    var dropTargeted = false
    /// Миниатюра последнего файла на полке и обложка трека.
    private(set) var shelfThumbnail: NSImage?
    private(set) var artwork: NSImage?
    /// Сколько места оставляет Dock.
    /// Пульт на левом краю экрана: растёт вправо. Зеркально — влево.
    var onLeft = true
    var enabled = true
    var limitsEnabled = true
    var prompterEnabled = true
    var dictationEnabled = false
    var translatorEnabled = false
    /// Свои правила замены.
    var dictationRules: [DictationRule] = []
    /// Столбики волны, 0…1, новые справа.
    private(set) var dictationLevels = [Float](repeating: 0, count: DictationLook.bars)
    var fit = ConsoleFit.full(width: ConsoleLayout.maxWidth) { didSet { if fit != oldValue { onLayoutChange?() } } }
    var activeWidth = ConsoleLayout.activeWidth
    /// Зазор между капсулой на уровне Dock и панелью над ним.
    var expandedGap = ConsoleLayout.expandedGap
    /// С какой стороны въезжает новая страница: 1 — справа, −1 — слева, 0 — снизу, при раскрытии.
    private(set) var pageTravel = 0
    /// Окно лимита в капсуле, из настроек.
    func setCapsuleWindow(_ kind: LimitWindowKind?) {
        limits.capsuleWindow = kind
    }
    /// Панель в окне: ещё стоит, пока форма закрывается.
    private(set) var panelMounted = false
    /// Форма раскрыта. Двигается только она, содержимое стоит на месте.
    private(set) var panelOpen = false
    /// Содержимое проявляется на такт позже формы: она открывает его, а не пустоту.
    private(set) var contentShown = false
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    /// Тот же маскот, что в углу: сидит у карточки сервиса, который сейчас работает.
    @ObservationIgnored var mascotAnimator: MascotAnimator?
    @ObservationIgnored var mascotService: () -> LimitService? = { nil }
    /// Система сдвинула видимую область экрана.
    @ObservationIgnored var placementChanged: () -> Bool = { false }
    /// Превью картинок на полке.
    private(set) var shelfPreviews: [URL: NSImage] = [:]
    @ObservationIgnored private var mutedVolume = 0.5
    /// Что играло последним. Живёт только в памяти.
    private(set) var rememberedTrack: NowPlaying?
    /// Текст на странице перевода. Живёт в памяти, закрытие Пульта его не трогает.
    var translateInput = ""
    @ObservationIgnored private var translateTask: Task<Void, Never>?
    /// Перевод только что скопирован.
    var translateCopied = false
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
    /// Прочитанные строки с дробной частью: текст едет, а не прыгает.
    private(set) var prompterScroll = 0.0
    var prompterTextSize = PrompterTextSize.medium
    /// Какие клавиши занял кто-то другой: об этом надо сказать, а не молчать.
    var busyKeys: Set<String> = []
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
    /// Диктовка: записать, закончить запись, открыть настройки модели.
    @ObservationIgnored var onDictationStart: (() -> Void)?
    @ObservationIgnored var onDictationStop: ((_ keep: Bool) -> Void)?
    @ObservationIgnored var onDictationNeedsModel: (() -> Void)?
    /// Изменилась диктовка; true — идёт запись, маскот смотрит на Пульт.
    @ObservationIgnored var onDictationActive: ((Bool) -> Void)?
    /// Модель готова к записи.
    @ObservationIgnored var dictationModelReady: () -> Bool = { false }
    /// «Скопировать» и «Заменить выделенное» во вкладке перевода.
    @ObservationIgnored var onTranslateReplace: ((String) -> Void)?
    /// Открыть настройки Пульта; значение — блок, к которому перейти.
    @ObservationIgnored var onOpenSettings: ((String?) -> Void)?
    @ObservationIgnored var onSound: ((ConsoleSound) -> Void)?
    @ObservationIgnored private var prompterTimer: Timer?
    @ObservationIgnored private var dictationLimitTimer: Timer?
    @ObservationIgnored private var lastTick = Date.distantPast
    @ObservationIgnored private var quietOn = false
    /// Размер, под который уже выложена панель.
    @ObservationIgnored var placedSize = CGSize.zero

    /// Новый модуль — одна строка здесь.
    private var modules: [any ConsoleModule] {
        var list: [any ConsoleModule] = []
        if limitsEnabled { list.append(limits) }
        if prompterEnabled { list.append(prompter) }
        if dictationEnabled { list.append(dictation) }
        if calendarEnabled { list.append(calendar) }
        if shelfEnabled { list.append(shelf) }
        if musicEnabled { list.append(media) }
        if translatorEnabled { list.append(translate) }
        return list
    }

    /// У диктовки вкладки нет: она вся в капсуле.
    var tabs: [(id: ConsoleModuleID, title: String)] {
        modules.filter { $0.id != .dictation }.map { ($0.id, $0.title) }
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

    /// До трёх значков других модулей, которым есть что показать. С кнопкой им нет места: строка важнее.
    var indicators: [ConsoleModuleID] {
        guard capsule?.action == nil, capsule?.wave != true else { return [] }
        return modules.filter { $0.id != director.leader?.module && $0.priority(now: now) != nil }.prefix(3).map(\.id)
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
        onSound?(.shelf)
        if let last = shelf.items.last { loadThumbnail(last.url) }
        urls.filter { ShelfFileKind(name: $0.lastPathComponent) == .image }.forEach(loadPreview)
        refresh(agentWaiting: false)
    }

    private func loadPreview(_ url: URL) {
        Task { [weak self] in
            let image = await ShelfThumbnails.preview(for: url)
            self?.shelfPreviews[url] = image
        }
    }

    func removeFromShelf(_ url: URL) {
        shelf.remove(url)
        if shelf.items.isEmpty { shelfThumbnail = nil } else if let last = shelf.items.last { loadThumbnail(last.url) }
        refresh(agentWaiting: false)
    }

    func clearShelf() {
        shelf.clear()
        shelfThumbnail = nil
        shelfPreviews = [:]
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
            // Последний трек остаётся на странице: пустота после паузы выглядит как поломка.
            if var last = media.playing {
                last.isPlaying = false
                rememberedTrack = last
            }
            media.playing = nil
        }
        media.availability = .available
        refresh(agentWaiting: false)
    }

    /// Клик по динамику: тишина и обратно, к той же громкости.
    func toggleMute() {
        guard let current = volume else { return }
        let target = current > 0 ? 0 : max(mutedVolume, 0.1)
        if current > 0 { mutedVolume = current }
        onVolume?(target)
        volume = target
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
        let points = prompterTextSize.points
        prompterLines = prompter.script.lines { PrompterLook.fits($0, points: points) }
        prompterLine = 0
        prompterScroll = 0
        setExpanded(false)
        // Тишина — сразу, а не на следующем тике.
        tickModules()
        refresh(agentWaiting: false)
        prompterTimer = Timer.scheduledTimer(withTimeInterval: PrompterLook.tick, repeats: true) { [weak self] _ in
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
            updatePrompterPlace()
        }
    }

    func seekPrompter(toFraction fraction: Double) {
        prompter.seek(toFraction: fraction, now: Date())
        updatePrompterPlace()
    }

    func jumpPrompter(lines step: Int) {
        prompter.jump(lines: step, in: prompterLines, now: Date())
        updatePrompterPlace()
    }

    private func updatePrompterPlace() {
        let line = PrompterScript.lineIndex(of: prompter.word, in: prompterLines)
        if line != prompterLine { prompterLine = line }
        prompterScroll = PrompterScript.scroll(position: prompter.position, in: prompterLines)
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
        if Date() < prompterSpeedShownUntil { return prompter.multiplierText }
        if prompter.mode == .paused { return "Пауза" }
        if prompter.voiceHolds(now: Date()) { return "Жду голос" }
        return nil
    }

    /// «Вставить»: буфер читается только по этому нажатию.
    func pastePrompterText() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        prompterDraft = text
    }

    /// Сколько займёт текст при нынешней скорости.
    var prompterEstimate: String? {
        let words = prompterDraft.split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return nil }
        let time = PrompterModule.clock(Double(words) / Double(prompter.speed) * 60)
        return "\(words) \(HumanTime.plural(words, "слово", "слова", "слов")) · \(time)"
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

    // MARK: - Диктовка

    func pressDictation() {
        guard dictationEnabled, !prompter.isActive else { return }
        now = Date()
        let recording = dictation.press(now: now, modelReady: dictationModelReady())
        settleDictation()
        guard recording else {
            if dictation.notice == .needsModel { onDictationNeedsModel?() }
            return
        }
        dictationLevels = [Float](repeating: 0, count: DictationLook.bars)
        onSound?(.recordStart)
        onDictationStart?()
        dictationLimitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.dictation.reachedLimit(now: Date()) else { return }
                self.releaseDictation()
            }
        }
    }

    func releaseDictation() {
        guard dictation.phase == .recording else { return }
        dictationLimitTimer?.invalidate()
        dictationLimitTimer = nil
        now = Date()
        let keep = dictation.release(now: now)
        if keep { onSound?(.recordStop) }
        onDictationStop?(keep)
        settleDictation()
    }

    func finishDictation(notice: DictationModule.Notice?) {
        now = Date()
        dictation.finish(now: now, notice: notice)
        if notice == .inserted { onSound?(.inserted) }
        settleDictation()
        guard notice != nil else { return }
        // Сообщение ушло: лидер и показ поверх полного экрана возвращаются сразу, а не ждут случая.
        let length = notice == .inserted ? DictationModule.insertedLength : DictationModule.noticeLength
        DispatchQueue.main.asyncAfter(deadline: .now() + length + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                self.settleDictation()
            }
        }
    }

    /// Поверх полного экрана: раскрытый Пульт и диктовка, иначе не видно, идёт ли запись.
    var showsOverFullScreen: Bool {
        expanded || (dictationEnabled && dictation.priority(now: Date()) != nil)
    }

    func hearDictation(level: Float) {
        // Речь редко громче 0.1 по RMS: растягиваем, чтобы волна была видна.
        dictationLevels.removeFirst()
        dictationLevels.append(min(1, (level * 8).squareRoot()))
    }

    /// Тишина и лидер — сразу, а не на следующем тике.
    private func settleDictation() {
        onDictationActive?(dictation.phase == .recording)
        tickModules()
        refresh(agentWaiting: false)
    }

    // MARK: - Перевод

    func pressTranslate(selection: String?, clipboard: String?, editable: Bool = true) -> String? {
        guard translatorEnabled else { return nil }
        now = Date()
        let text = translate.press(selection: selection, clipboard: clipboard, now: now, editable: editable)
        if let text { translateInput = text }
        tab = .translate
        setExpanded(true)
        tab = .translate
        return text
    }

    /// Текст на странице: перевод идёт, когда набор затихает.
    func typeTranslation(_ text: String) {
        translateInput = text
        translateTask?.cancel()
        guard let source = translate.type(text) else { return }
        translateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.runTranslation(source)
        }
    }

    func runTranslation(_ text: String) async {
        let result = await ConsoleTranslator.translate(text, direction: translate.direction(of: text))
        finishTranslate(source: text, result: result)
    }

    func flipTranslation() {
        translate.flip()
        typeTranslation(translateInput)
    }

    func clearTranslation() {
        translateTask?.cancel()
        translateInput = ""
        translate.reset()
    }

    func finishTranslate(source: String, result: Result<String, TranslateProblem>) {
        switch result {
        case .success(let text): translate.finish(source: source, result: text)
        case .failure(let problem): translate.fail(source: source, problem: problem.text)
        }
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
            if case .limitCritical = signal { onSound?(.limitCritical) }
            if signal.drawsGlance { onLeaderChange?() }
        }
    }

    private func refresh(agentWaiting: Bool) {
        let before = director.leader
        director.update(candidates: candidates, now: now, agentWaiting: agentWaiting, expanded: expanded)
        if director.leader != before { onLeaderChange?() }
        // Раскладка читает настройки Dock: только когда размер правда изменился, а не на каждом тике.
        if panelSize != placedSize || placementChanged() { onLayoutChange?() }
    }

    // MARK: - Состояния

    func setExpanded(_ on: Bool) {
        guard on != expanded else { return }
        if on {
            // Открываем то, что занимает капсулу.
            let ids = tabs.map(\.id)
            // По умолчанию «Файлы»; на другой раздел — только если он сейчас важнее: запись, встреча.
            if let leader = director.leader, leader.priority < .limitsNormal, ids.contains(leader.module) {
                tab = leader.module
            } else if ids.contains(.shelf) {
                tab = .shelf
            } else if !ids.contains(tab), let first = ids.first {
                tab = first
            }
            calendarDay = now
            calendarMonth = 0
        }
        expanded = on
        closeTask?.cancel()
        if on {
            pageTravel = 0
            panelMounted = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.expanded else { return }
                    self.panelOpen = true
                    self.contentShown = true
                }
            }
            onLeaderChange?()
        } else {
            panelOpen = false
            contentShown = false
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(ConsoleLook.closeMilliseconds))
                guard !Task.isCancelled else { return }
                self?.panelMounted = false
            }
        }
        onLayoutChange?()
    }

    func toggle() { setExpanded(!expanded) }

    /// Для отрисовки в файлы: сразу конечное состояние, без анимации.
    func showPanelNow() {
        setExpanded(true)
        panelOpen = true
        contentShown = true
    }

    /// Соседняя страница: клавиши и свайп. По кругу не идёт: край страниц должен чувствоваться.
    func movePage(by step: Int) {
        let ids = tabs.map(\.id)
        guard let index = ids.firstIndex(of: tab), ids.indices.contains(index + step) else { return }
        openPage(ids[index + step])
    }

    func selectPage(number: Int) {
        let ids = tabs.map(\.id)
        if ids.indices.contains(number - 1) { openPage(ids[number - 1]) }
    }

    /// Открыть страницу: следующая появляется справа, предыдущая слева, откуда бы ни пришла команда.
    func openPage(_ id: ConsoleModuleID) {
        let ids = tabs.map(\.id)
        guard id != tab, let old = ids.firstIndex(of: tab), let new = ids.firstIndex(of: id) else {
            tab = id
            return
        }
        pageTravel = new > old ? 1 : -1
        tab = id
    }

    func copyTranslation(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        translateCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated { self?.translateCopied = false }
        }
    }

    // MARK: - Размеры

    var showsDot: Bool {
        if dropTargeted { return false }
        if case .dot = fit { return true }
        return capsule == nil
    }

    /// Кольца в капсуле; если на два нет места — самое тесное.
    var visibleRings: [CapsuleRing] {
        let rings = capsule?.rings ?? []
        guard ringsWidth(rings) + ConsoleLook.padding * 2 > capsuleLimit,
              let tightest = rings.max(by: { ($0.fraction ?? -1) < ($1.fraction ?? -1) }) else { return rings }
        return [tightest]
    }

    private var capsuleLimit: Double {
        switch fit {
        case .full(let width): width
        case .leader, .dot: ConsoleLayout.minWidth
        }
    }

    private func ringsWidth(_ rings: [CapsuleRing]) -> Double {
        let sides = rings.map { ring in
            let figure = (ring.figure as NSString).size(withAttributes: [.font: ConsoleLook.figureFont]).width
            return ConsoleLook.mark + ConsoleLook.sideGap + ceil(figure) + (ring.fraction == nil ? 0 : ConsoleLook.sideGap + ConsoleLook.dot)
        }
        return sides.reduce(0, +) + Double(max(0, sides.count - 1)) * ConsoleLook.ringGap
    }

    /// Строка в капсуле, если на неё хватает места.
    var capsuleText: String? {
        guard case .full = fit else { return nil }
        return capsule?.text
    }

    /// Ширина капсулы по содержимому: 96–220 pt; Dock может её сузить.
    var capsuleWidth: Double {
        guard !showsDot else { return ConsoleLayout.dotSize }
        if capsule?.wave == true {
            if case .full = fit { return activeWidth }
            return ConsoleLayout.minWidth
        }
        let limit = capsuleLimit
        let dots = Double(indicators.count)
        let extras = (capsule?.action != nil ? ConsoleLook.joinWidth + ConsoleLook.labelGap : 0)
            + (dots > 0 ? ConsoleLook.labelGap + dots * ConsoleLook.indicator + (dots - 1) * 6 : 0)
        guard let text = capsuleText else {
            let content = ringsWidth(visibleRings) + (dots > 0 ? ConsoleLook.labelGap + dots * ConsoleLook.indicator + (dots - 1) * 6 : 0)
            return min(limit, max(ConsoleLayout.minWidth, ceil(content) + ConsoleLook.padding * 2))
        }
        let full = capsule?.tail.map { "\(text) \($0)" } ?? text
        let width = (full as NSString).size(withAttributes: [.font: ConsoleLook.labelFont]).width
        return min(limit, max(ConsoleLayout.minWidth, ConsoleLook.ring + ConsoleLook.labelGap + ceil(width) + extras + ConsoleLook.padding * 2))
    }

    var capsuleHeight: Double { showsDot ? ConsoleLayout.dotSize : ConsoleLayout.capsuleHeight }

    var panelSize: CGSize {
        guard expanded else { return CGSize(width: capsuleWidth, height: capsuleHeight) }
        return CGSize(
            width: ConsoleLayout.expandedWidth + ConsoleLayout.overshoot,
            height: ConsoleLayout.expandedHeight + expandedGap + capsuleHeight + ConsoleLayout.overshoot
        )
    }
}

/// Волна диктовки.
enum DictationLook {
    static let bars = 32
    static let barWidth = 3.0
    static let barGap = 3.0
    static let height = 18.0
}

/// Размеры капсулы вне ядра: шрифт есть только у AppKit.
enum ConsoleLook {
    static let ring = 18.0
    static let ringGap = 14.0
    static let mark = 15.0
    static let sideGap = 7.0
    static let mascot = 22.0
    /// Сколько панель стоит после закрытия: столько идёт пружина формы.
    static let closeMilliseconds = 520
    /// Настолько новая страница сдвинута в начале: чуть-чуть, без полёта через всю панель.
    static let pageShift = 24.0
    static let tabs = 30.0
    static let labelGap = 8.0
    static let padding = 12.0
    static let joinWidth = 40.0
    static let dot = 6.0
    static let indicator = 14.0
    static let alertColor: UInt32 = 0xFF453A
    @MainActor static let labelFont = ConsoleStyle.nsFont(13, .medium)
    @MainActor static let figureFont = ConsoleStyle.nsFont(15, .medium)
}
