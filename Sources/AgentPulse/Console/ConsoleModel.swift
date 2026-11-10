import AgentPulseCore
import AppKit
import Observation

/// Модель Пульта: модули, директор и что сейчас на экране. Мозг маскота получает от неё только `ToolSignal`.
@MainActor
@Observable
final class ConsoleModel {
    /// Офлайн-промо не читает сохранённые лимиты и личные тексты.
    @ObservationIgnored private let promoMode: Bool

    init(promo: Bool = false) {
        promoMode = promo
        translate = TranslateModule(preferences: promo ? TranslatePreferences() : TranslatePreferences.load())
        limits = LimitsModule(book: promo ? LimitsBook() : LimitsBook.load())
        prompterLibrary = promo ? PrompterLibrary() : PrompterLibrary.load()
        translationTerms = promo ? TranslationTerms() : TranslationTerms.load()
        shelf = promo ? ShelfModule() : ShelfModule.load()
        prompterCheckpoint = promo ? nil : PrompterCheckpoint.load()
        prompterDraft = promo ? "" : PrompterDraft.load().text
        if !promo {
            Task { [weak self] in
                guard let self else { return }
                if let last = self.shelf.items.last { self.loadThumbnail(last.url) }
                self.shelf.items.filter { ShelfFileKind(name: $0.name) == .image }.forEach { self.loadPreview($0.url) }
            }
        }
    }

    private(set) var limits: LimitsModule
    private(set) var prompter = PrompterModule()
    private(set) var dictation = DictationModule()
    private(set) var translate: TranslateModule
    private(set) var translationTerms: TranslationTerms
    var translationLanguages = ["en", "ru", "de"]
    private(set) var shelf = ShelfModule()
    private(set) var director = ConsoleDirector()
    private(set) var now = Date()
    private(set) var expanded = false
    /// Открытая вкладка.
    var tab = ConsoleModuleID.shelf
    /// Над Пультом несут файл.
    var dropTargeted = false
    /// Миниатюра последнего файла на полке.
    private(set) var shelfThumbnail: NSImage?
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
    /// Панель в окне: ещё стоит, пока форма закрывается.
    private(set) var panelMounted = false
    /// Форма раскрыта. Двигается только она, содержимое стоит на месте.
    private(set) var panelOpen = false
    /// Содержимое проявляется на такт позже формы: она открывает его, а не пустоту.
    private(set) var contentShown = false
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    /// Система сдвинула видимую область экрана.
    @ObservationIgnored var placementChanged: () -> Bool = { false }
    /// Превью картинок на полке.
    private(set) var shelfPreviews: [URL: NSImage] = [:]
    private(set) var shelfFileStates: [URL: ShelfFileState] = [:]
    @ObservationIgnored private var shelfRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var shelfRefreshedAt = Date.distantPast
    @ObservationIgnored private var shelfPreviewTasks: [URL: Task<Void, Never>] = [:]
    @ObservationIgnored private var shelfThumbnailTask: Task<Void, Never>?
    private(set) var shelfSelection = ShelfSelection()
    private(set) var shelfHistory = ShelfHistory()
    private var shelfTypeSearch = ShelfTypeSearch()
    /// Рамка выделения, пока ведут мышью.
    var shelfRubber: CGRect?
    /// Где стоят плитки: по ним рамка понимает, что задела.
    @ObservationIgnored var shelfFrames: [URL: CGRect] = [:]
    /// Текст на странице перевода. Живёт в памяти, закрытие Пульта его не трогает.
    var translateInput = ""
    @ObservationIgnored private var translateTask: Task<Void, Never>?
    /// Перевод только что скопирован.
    var translateCopied = false
    var comparingTranslation = false
    private var clearedTranslation: (module: TranslateModule, input: String)?
    var canRecoverTranslation: Bool { translateInput.isEmpty && clearedTranslation != nil }
    private var translationFragment: TextFragment?
    private var translationReview: (module: TranslateModule, input: String)?
    var canRestoreTranslationReview: Bool { translationReview != nil }
    var shelfEnabled = true
    var librarySkin: PalSkin?
    @ObservationIgnored var onShelfPreview: (([URL], Int, Bool) -> Void)?
    var refreshingLimits: Set<LimitService> = []
    var limitRefreshProblems: [LimitService: String] = [:]
    @ObservationIgnored var onRefreshLimits: ((LimitService) -> Void)?

    /// Текст в поле суфлёра.
    var prompterDraft = "" { didSet { schedulePrompterDraftSave() } }
    @ObservationIgnored private var prompterDraftSaveTask: Task<Void, Never>?
    var prompterMarkup = false { didSet { if oldValue != prompterMarkup { onPrompterMarkupChange?(prompterMarkup) } } }
    @ObservationIgnored var onPrompterMarkupChange: ((Bool) -> Void)?
    private(set) var prompterRehearsing = false
    private var prompterCheckpoint: PrompterCheckpoint?
    @ObservationIgnored private var prompterCheckpointSavedAt = Date.distantPast
    var canResumePrompter: Bool { prompterCheckpoint?.fraction(for: prompterDraft) != nil }
    var prompterStartTitle: String { canResumePrompter ? "Продолжить" : "Старт" }
    private(set) var prompterInputInvalid = false
    @ObservationIgnored private var prompterValidationTask: Task<Void, Never>?
    /// Вместо поля открыт список недавних текстов.
    var prompterRecentOpen = false
    private(set) var prompterLibrary: PrompterLibrary
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
    /// Суфлёр начался или кончился.
    @ObservationIgnored var onPrompterChange: ((Bool) -> Void)?
    /// Идти за голосом или перестать.
    @ObservationIgnored var onPrompterVoice: ((Bool) -> Void)?
    /// Изменилась скорость: запомнить в настройках.
    @ObservationIgnored var onPrompterSpeed: ((Int) -> Void)?
    /// Галочка «За голосом» во вкладке: настройки сохраняет приложение.
    @ObservationIgnored var onPrompterVoiceToggle: ((Bool) -> Void)?
    /// Диктовка: записать, закончить запись, открыть настройки модели.
    var dictationReplaying = false
    var dictationReplayUntil = Date.distantPast
    var canReplayDictation: Bool { dictationEnabled && !dictationReplaying && !prompter.isActive && dictation.phase == .idle && now < dictationReplayUntil }
    @ObservationIgnored var onForgetRecentDictation: (() -> Void)?
    @ObservationIgnored var onReplayDictation: (() -> Void)?
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
        if shelfEnabled { list.append(shelf) }
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

    /// До трёх значков других модулей, которым есть что показать. Во время диктовки скрыты.
    var indicators: [ConsoleModuleID] {
        guard capsule?.wave != true else { return [] }
        return modules.filter { $0.id != director.leader?.module && $0.priority(now: now) != nil }.prefix(3).map(\.id)
    }

    /// Картинка лидера вместо иконки: миниатюра файла.
    var leaderImage: NSImage? {
        switch director.leader?.module {
        case .shelf: shelfThumbnail
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

    func addToShelf(_ urls: [URL]) {
        guard shelfEnabled else { return }
        now = Date()
        let previous = shelf.items
        let previousCount = previous.count
        apply(shelf.add(urls))
        let added = shelf.items.dropFirst(previousCount)
        guard !added.isEmpty else { return }
        shelfHistory.record(previous)
        saveShelf()
        onSound?(.shelf)
        if let last = added.last { loadThumbnail(last.url) }
        added.filter { ShelfFileKind(name: $0.name) == .image }.forEach { loadPreview($0.url) }
        refresh(agentWaiting: false)
    }

    private func refreshShelfFiles() {
        guard !promoMode, shelfRefreshTask == nil, now.timeIntervalSince(shelfRefreshedAt) >= 3 else { return }
        shelfRefreshedAt = now
        let items = shelf.items
        shelfRefreshTask = Task { [weak self] in
            let results = await Task.detached(priority: .utility) {
                items.map { item in
                    let resolved = item.resolvingReference()
                    return (item, resolved, ShelfFileState.read(resolved.url))
                }
            }.value
            guard let self else { return }
            defer { self.shelfRefreshTask = nil }
            guard self.shelf.items == items else { return }
            let resolved = results.map { $0.1 }
            if resolved != items {
                let mapping = Dictionary(uniqueKeysWithValues: results.map { ($0.0.url, $0.1.url) })
                let selected = Set(self.shelfSelection.urls.compactMap { mapping[$0] })
                self.shelf.restore(resolved)
                self.shelfSelection.replace(with: selected)
                self.shelfSelection.keep(only: self.shelfOrder)
                self.saveShelf()
            }
            var states: [URL: ShelfFileState] = [:]
            for (old, item, state) in results {
                states[item.url] = state
                if old.url != item.url { self.shelfPreviews[old.url] = nil }
                if self.shelfFileStates[item.url] != state {
                    self.shelfPreviewTasks.removeValue(forKey: item.url)?.cancel()
                    self.shelfPreviews[item.url] = nil
                    if !state.available, item.url == self.shelf.items.last?.url {
                        self.shelfThumbnailTask?.cancel()
                        self.shelfThumbnail = nil
                    }
                    if state.available {
                        if ShelfFileKind(name: item.name) == .image { self.loadPreview(item.url) }
                        if item.url == self.shelf.items.last?.url { self.loadThumbnail(item.url) }
                    }
                }
            }
            self.shelfFileStates = states
        }
    }

    private func loadPreview(_ url: URL) {
        shelfPreviewTasks[url]?.cancel()
        shelfPreviewTasks[url] = Task { [weak self] in
            let image = await ShelfThumbnails.preview(for: url)
            guard !Task.isCancelled, let self, self.shelf.items.contains(where: { $0.url == url }) else { return }
            self.shelfPreviews[url] = image
            self.shelfPreviewTasks[url] = nil
        }
    }

    func removeFromShelf(_ url: URL) {
        removeFromShelf([url])
    }

    func removeFromShelf(_ urls: [URL]) {
        guard shelf.items.contains(where: { urls.contains($0.url) }) else { return }
        shelfHistory.record(shelf.items)
        shelf.remove(urls)
        saveShelf()
        for url in urls {
            shelfPreviewTasks.removeValue(forKey: url)?.cancel()
            shelfPreviews[url] = nil
        }
        shelfSelection.keep(only: shelfOrder)
        if let last = shelf.items.last { loadThumbnail(last.url) }
        else {
            shelfThumbnailTask?.cancel()
            shelfThumbnailTask = nil
            shelfThumbnail = nil
        }
        refresh(agentWaiting: false)
    }

    /// В том порядке, в каком плитки стоят на странице: новые первыми.
    var shelfOrder: [URL] { shelf.displayItems.map(\.url) }

    func sortShelf(_ sort: ShelfSort) {
        let old = shelf.items
        shelf.sort(sort)
        guard old != shelf.items else { return }
        shelfHistory.record(old)
        saveShelf()
    }

    func moveShelf(_ urls: [URL], before target: URL) {
        let old = shelf.items
        shelf.move(urls, before: target)
        guard old != shelf.items else { return }
        shelfHistory.record(old)
        saveShelf()
    }

    func bringShelfToFront(from url: URL) {
        let old = shelf.items
        shelf.bringToFront(shelfTargets(from: url))
        guard old != shelf.items else { return }
        shelfHistory.record(old)
        saveShelf()
    }

    func shelfPinActionTitle(from url: URL) -> String {
        let targets = shelfTargets(from: url)
        return shelf.items.filter { targets.contains($0.url) }.allSatisfy(\.isPinned) ? "Открепить" : "Закрепить"
    }

    func pinShelfFiles(from url: URL) {
        let targets = shelfTargets(from: url)
        let pin = !shelf.items.filter { targets.contains($0.url) }.allSatisfy(\.isPinned)
        let old = shelf.items
        shelf.pin(targets, value: pin)
        guard old != shelf.items else { return }
        shelfHistory.record(old)
        saveShelf()
    }

    func clickShelf(_ url: URL, flags: NSEvent.ModifierFlags) {
        shelfTypeSearch.reset()
        shelfSelection.click(url, order: shelfOrder, command: flags.contains(.command), shift: flags.contains(.shift))
    }

    func moveShelfSelection(by step: Int, extending: Bool) {
        shelfTypeSearch.reset()
        shelfSelection.move(by: step, order: shelfOrder, extending: extending)
    }

    @discardableResult
    func searchShelf(_ input: String) -> Bool {
        let order = shelfOrder
        guard let index = shelfTypeSearch.match(input, names: order.map(\.lastPathComponent), now: Date(), from: shelfSelection.focused.flatMap { order.firstIndex(of: $0) }) else { return false }
        shelfSelection.click(order[index], order: order)
        return true
    }

    func selectAllShelf() {
        shelfSelection.selectAll(shelfOrder)
    }

    func clearShelfSelection() {
        shelfTypeSearch.reset()
        shelfSelection.clear()
    }

    func removeSelectedFiles() {
        removeFromShelf(Array(shelfSelection.urls))
    }

    /// Рамка мышью: выбраны плитки, которых она касается.
    func dragRubber(_ rect: CGRect?) {
        shelfRubber = rect
        guard let rect else { return }
        shelfSelection.replace(with: Set(shelfFrames.filter { $0.value.intersects(rect) }.keys))
    }

    /// Системный выбор файлов: несколько сразу. Панель без фокуса, поэтому приложение сначала выходит вперёд.
    func chooseFiles() {
        let chooser = NSOpenPanel()
        chooser.allowsMultipleSelection = true
        chooser.canChooseDirectories = true
        chooser.canChooseFiles = true
        chooser.prompt = "Добавить"
        NSApp.activate()
        let answer = chooser.runModal()
        setExpanded(true)
        tab = .shelf
        if answer == .OK { addToShelf(chooser.urls) }
    }

    func clearShelf() {
        guard !shelf.items.isEmpty else { return }
        shelfHistory.record(shelf.items)
        shelf.clear()
        saveShelf()
        shelfThumbnailTask?.cancel()
        shelfThumbnailTask = nil
        shelfPreviewTasks.values.forEach { $0.cancel() }
        shelfPreviewTasks = [:]
        shelfThumbnail = nil
        shelfPreviews = [:]
        shelfSelection.clear()
        refresh(agentWaiting: false)
    }

    func findShelfFile(_ old: URL) {
        let chooser = NSOpenPanel()
        chooser.allowsMultipleSelection = false
        chooser.canChooseDirectories = true
        chooser.canChooseFiles = true
        chooser.message = "Выбери файл для этой ссылки в Библиотеке"
        chooser.prompt = "Выбрать"
        NSApp.activate()
        let response = chooser.runModal()
        setExpanded(true)
        tab = .shelf
        guard response == .OK, let url = chooser.url else { return }
        var updated = shelf
        guard updated.replace(old, with: url) else { return }
        shelfHistory.record(shelf.items)
        restoreShelf(updated.items)
    }

    func undoShelf() {
        guard let items = shelfHistory.undo(current: shelf.items) else { return }
        restoreShelf(items)
    }

    func redoShelf() {
        guard let items = shelfHistory.redo(current: shelf.items) else { return }
        restoreShelf(items)
    }

    private func restoreShelf(_ items: [ShelfItem]) {
        shelfThumbnailTask?.cancel()
        shelfPreviewTasks.values.forEach { $0.cancel() }
        shelfPreviewTasks = [:]
        shelfPreviews = [:]
        shelfThumbnail = nil
        shelf.restore(items)
        shelfFileStates = [:]
        shelfRefreshedAt = .distantPast
        shelfSelection.keep(only: shelfOrder)
        saveShelf()
        if let last = shelf.items.last { loadThumbnail(last.url) }
        shelf.items.filter { ShelfFileKind(name: $0.name) == .image }.forEach { loadPreview($0.url) }
        refresh(agentWaiting: false)
    }

    private func saveShelf() {
        guard !promoMode else { return }
        try? shelf.save()
    }

    private func loadThumbnail(_ url: URL) {
        shelfThumbnailTask?.cancel()
        shelfThumbnailTask = Task { [weak self] in
            let image = await ShelfThumbnails.image(for: url)
            guard !Task.isCancelled, let self, self.shelf.items.last?.url == url else { return }
            self.shelfThumbnail = image
            self.shelfThumbnailTask = nil
        }
    }

    // MARK: - Суфлёр

    private func schedulePrompterDraftSave() {
        guard !promoMode else { return }
        if prompterDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { clearPrompterCheckpoint() }
        prompterDraftSaveTask?.cancel()
        prompterDraftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flushPrompterDraft()
        }
    }

    func flushPrompterDraft() {
        guard !promoMode else { return }
        prompterDraftSaveTask?.cancel()
        try? PrompterDraft(text: prompterDraft).save()
    }

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

    func preparePromoResume(text: String, position: Double) {
        precondition(promoMode)
        prompterDraft = text
        prompterCheckpoint = PrompterCheckpoint(text: text, position: position)
    }

    func preparePromoUnavailableFiles() {
        precondition(promoMode)
        shelfFileStates = Dictionary(uniqueKeysWithValues: shelf.items.map { ($0.url, ShelfFileState.read($0.url)) })
    }

    /// Виртуальные часы промо: без таймера, записи «Недавних» и показа окна.
    func preparePromoPrompter(_ text: String) {
        precondition(promoMode)
        _ = prompter.start(text: text, now: Date(timeIntervalSinceReferenceDate: 100))
        prompterLines = prompter.script.lines { PrompterLook.fits($0, points: prompterTextSize.points) }
        setExpanded(false)
    }

    func seekPromoPrompter(elapsed: Double, paused: Bool) {
        precondition(promoMode)
        now = Date(timeIntervalSinceReferenceDate: 100 + elapsed)
        prompter.seek(toFraction: elapsed / prompter.total, now: now)
        if (prompter.mode == .paused) != paused { prompter.togglePause(now: now) }
        updatePrompterPlace()
        // Переводим новую строку вверх после начала её чтения: активное слово остаётся видимым.
        if prompterLine > 0 {
            let since = prompter.position - Double(prompterLines[prompterLine].words.lowerBound)
            let p = min(1, max(0, since / 0.65))
            prompterScroll = Double(prompterLine - 1) + 1 - pow(1 - p, 3)
        } else { prompterScroll = 0 }
        refresh(agentWaiting: false)
    }

    func rehearsePrompter(_ fragment: TextFragment) {
        guard fragment.source == prompterDraft else { return }
        startPrompter(text: fragment.text)
    }

    func startPrompter(text override: String? = nil) {
        guard prompterEnabled, !dictationReplaying, dictation.phase == .idle, !prompter.isActive, let text = override ?? prompterText else { return }
        now = Date()
        let resume = override != nil ? nil : prompterCheckpoint?.fraction(for: text)
        guard prompter.start(text: text, now: now, markup: prompterMarkup) else { return }
        prompterRehearsing = override != nil
        if !prompterRehearsing, !promoMode {
            prompterLibrary.remember(text)
            prompterLibrary.save()
        }
        let points = prompterTextSize.points
        prompterLines = prompter.script.lines { PrompterLook.fits($0, points: points) }
        prompterLine = 0
        prompterScroll = 0
        if let resume {
            prompter.seek(toFraction: resume, now: now)
            updatePrompterPlace()
        }
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

    /// Кнопка работает только с видимым черновиком; горячая клавиша сохраняет запуск недавнего.
    func startPrompterDraft() {
        let spoken = prompterMarkup ? PrompterScore(prompterDraft).text : prompterDraft
        guard !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            prompterValidationTask?.cancel()
            prompterInputInvalid = true
            prompterValidationTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.prompterInputInvalid = false
            }
            return
        }
        prompterValidationTask?.cancel()
        prompterInputInvalid = false
        startPrompter()
    }

    func stopPrompter() {
        guard prompter.isActive else { return }
        savePrompterCheckpoint()
        prompter.stop()
        finishPrompter()
    }

    private func finishPrompter(completed: Bool = false) {
        if completed && !prompterRehearsing { clearPrompterCheckpoint() }
        prompterRehearsing = false
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
            finishPrompter(completed: true)
        } else {
            updatePrompterPlace()
            if Date().timeIntervalSince(prompterCheckpointSavedAt) >= 1 { savePrompterCheckpoint() }
        }
    }

    func savePrompterCheckpoint() {
        guard !promoMode, !prompterRehearsing, prompter.isActive else { return }
        prompterCheckpointSavedAt = Date()
        let original = prompterDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = original.isEmpty ? prompter.script.text : original
        let rawWords = text.split(whereSeparator: \.isWhitespace).count
        let scaled = prompter.position / Double(max(1, prompter.script.words.count)) * Double(rawWords)
        let saved = PrompterCheckpoint(text: text, position: scaled)
        guard saved.fraction(for: text) != nil else { clearPrompterCheckpoint(); return }
        prompterCheckpoint = saved
        try? saved.save()
    }

    private func clearPrompterCheckpoint() {
        prompterCheckpoint = nil
        if !promoMode { PrompterCheckpoint.erase() }
    }

    func restartPrompterFromBeginning() {
        clearPrompterCheckpoint()
        startPrompterDraft()
    }

    func seekPrompter(toFraction fraction: Double) {
        prompter.seek(toFraction: fraction, now: Date())
        updatePrompterPlace()
    }

    func restartPrompterSentence() {
        prompter.restartSentence(now: Date())
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

    func fitPrompterDuration(_ seconds: TimeInterval) {
        let score = prompterMarkup ? PrompterScore(prompterDraft) : nil
        let words = (score?.text ?? prompterDraft).split(whereSeparator: \.isWhitespace).count
        guard let timing = PrompterTiming(words: words, target: seconds, pauses: score?.duration ?? 0) else { return }
        prompter.setExactSpeed(timing.speed)
        if timing.limited {
            let alert = NSAlert()
            alert.messageText = "Темп ограничен для удобного чтения"
            alert.informativeText = "При \(timing.speed) словах в минуту доклад займёт \(PrompterModule.clock(timing.seconds))."
            alert.runModal()
        }
    }

    func askPrompterDuration() {
        defer { setExpanded(true); tab = .prompter }
        let alert = NSAlert()
        alert.messageText = "Длительность выступления"
        alert.informativeText = "Введи минуты или время м:с. Темп останется в диапазоне 65–260 слов в минуту."
        let field = NSTextField(string: "5:00")
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Применить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate()
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let seconds = PrompterTiming.parse(field.stringValue) { fitPrompterDuration(seconds) }
        else {
            let problem = NSAlert()
            problem.messageText = "Не удалось распознать время"
            problem.informativeText = "Введи минуты, например 5 или 2,5, либо м:с — 2:30. Допустимо от одной секунды до двух часов."
            problem.runModal()
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
        if prompter.holdsForMarkup { return "Пауза по тексту" }
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
        let score = prompterMarkup ? PrompterScore(prompterDraft) : nil
        let words = (score?.text ?? prompterDraft).split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return nil }
        let time = PrompterModule.clock(Double(words) / Double(prompter.speed) * 60 + (prompter.followsVoice ? 0 : score?.duration ?? 0))
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
        guard let url = urls.first(where: PrompterTextFile.supports) else { return }
        importPrompterFile(url)
    }

    func importPrompterFile(_ url: URL) {
        guard prompterEnabled, !prompter.isActive else { return }
        do {
            let text = try PrompterTextFile.read(url)
            prompterDraft = text
            prompterRecentOpen = false
            openPage(.prompter)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось открыть текст"
            alert.informativeText = "Нужен доступный файл .txt или .md в UTF-8 размером до 2 МБ."
            alert.runModal()
        }
    }

    // MARK: - Диктовка

    func pressDictation(correcting: Bool = false) {
        guard dictationEnabled, !dictationReplaying, !prompter.isActive else { return }
        now = Date()
        let recording = dictation.press(now: now, modelReady: dictationModelReady(), correcting: correcting)
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
        if notice == .inserted || notice == .corrected { onSound?(.inserted) }
        settleDictation()
        guard notice != nil else { return }
        // Сообщение ушло: лидер и показ поверх полного экрана возвращаются сразу, а не ждут случая.
        let length = (notice == .inserted || notice == .corrected) ? DictationModule.insertedLength : DictationModule.noticeLength
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
        translationFragment = nil
        translationReview = nil
        translateTask?.cancel()
        translateCopied = false
        now = Date()
        let text = translate.press(selection: selection, clipboard: clipboard, now: now, editable: editable)
        if let text { translateInput = text }
        tab = .translate
        setExpanded(true)
        tab = .translate
        return text
    }

    /// Текст на странице: перевод идёт, когда набор затихает.
    func typeTranslation(_ text: String, preservingSelection: Bool = false) {
        translationFragment = nil
        translationReview = nil
        translateCopied = false
        translateInput = text
        translateTask?.cancel()
        guard let source = translate.type(text, preservingSelection: preservingSelection) else { return }
        scheduleTranslation(source)
    }

    func translateFragment(_ fragment: TextFragment) {
        guard fragment.source == translateInput else { return }
        typeTranslation(translateInput)
        translateTask?.cancel()
        translationFragment = fragment
        guard let text = translate.type(fragment.text) else { return }
        scheduleTranslation(text)
    }

    private func scheduleTranslation(_ source: String) {
        translateTask?.cancel()
        translateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.runTranslation(source)
        }
    }

    var translationLanguagesPending: Int? {
        guard case .failed(let problem) = translate.state, problem == ConsoleTranslator.needsLanguages,
              !translateInput.isEmpty else { return nil }
        return translate.requestVersion
    }

    func waitForTranslationLanguages(version: Int) async {
        let pendingSource = translationFragment?.text ?? translateInput
        let direction = translate.direction(of: pendingSource)
        while !Task.isCancelled, translationLanguagesPending == version {
            let ready = await ConsoleTranslator.languagesReady(direction: direction)
            guard !Task.isCancelled, translationLanguagesPending == version else { return }
            if ready, let source = translate.retryFailed(source: pendingSource, version: version) {
                // Отдельная задача переживёт отмену SwiftUI .task после выхода из ошибки.
                scheduleTranslation(source)
                return
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func protectTranslationTerm(_ term: String) {
        translationTerms.add(term)
        if !promoMode { try? translationTerms.save() }
        typeTranslation(translateInput, preservingSelection: true)
    }

    func removeTranslationTerm(_ term: String) {
        translationTerms.remove(term)
        if !promoMode { try? translationTerms.save() }
        typeTranslation(translateInput, preservingSelection: true)
    }

    func runTranslation(_ text: String) async {
        let version = translate.requestVersion
        let direction = translate.direction(of: text)
        let result = await ConsoleTranslator.translate(text, direction: direction, protectedTerms: translationTerms.terms)
        guard !Task.isCancelled else { return }
        finishTranslate(source: text, result: result, request: version)
    }

    func flipTranslation() {
        let newInput = translate.flip(sourceText: translateInput)
        saveTranslationLanguages()
        typeTranslation(newInput ?? translateInput)
    }

    func selectTranslationLanguage(_ code: String?, source: Bool) {
        if source { translate.selectSource(code) }
        else if let code { translate.selectTarget(code) }
        saveTranslationLanguages()
        typeTranslation(translateInput, preservingSelection: true)
    }

    func reviewReverseTranslation() {
        guard case .done = translate.state, translationReview == nil else { return }
        let saved = (module: translate, input: translateInput)
        guard let result = translate.flip(sourceText: translateInput) else { return }
        typeTranslation(result)
        translationReview = saved
    }

    func restoreTranslationReview() {
        guard let saved = translationReview else { return }
        translateTask?.cancel()
        translate.restore(saved.module)
        translateInput = saved.input
        translateCopied = false
        translationReview = nil
    }

    private func saveTranslationLanguages() {
        guard !promoMode else { return }
        try? translate.preferences.save()
    }

    func recoverTranslation() {
        guard canRecoverTranslation, let saved = clearedTranslation else { return }
        translateTask?.cancel()
        translate.restore(saved.module)
        translate.discardReplacement()
        translateInput = saved.input
        translationFragment = nil
        translationReview = nil
        clearedTranslation = nil
        translateCopied = false
        saveTranslationLanguages()
    }

    func clearTranslation() {
        if case .done = translate.state { clearedTranslation = (translate, translateInput) }
        translationFragment = nil
        translationReview = nil
        translateTask?.cancel()
        translateInput = ""
        translate.reset()
        translateCopied = false
    }

    func finishTranslate(source: String, result: Result<String, TranslateProblem>, request: Int? = nil) {
        switch result {
        case .success(let text):
            if let fragment = translationFragment {
                guard fragment.text == source, let full = fragment.replacing(with: text, in: translateInput) else { return }
                translate.finish(source: source, result: full, request: request)
            } else { translate.finish(source: source, result: text, request: request) }
        case .failure(let problem): translate.fail(source: source, problem: problem.text, request: request)
        }
    }

    // MARK: - Тик

    /// Раз в секунду: сброс окон, удержание лидера, обратный отсчёт. Содержимое не меняется — кадров нет.
    func tick(now: Date, agentWaiting: Bool, inputActive: Bool) {
        guard now.timeIntervalSince(lastTick) >= 1 else { return }
        lastTick = now
        if inputActive { director.noteInput(seconds: 1) }
        self.now = now
        if expanded && shelfEnabled { refreshShelfFiles() }
        tickModules()
        refresh(agentWaiting: agentWaiting)
    }

    private func tickModules() {
        apply(limits.tick(now: now))
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
        if !on { shelfSelection.clear(); shelfTypeSearch.reset(); comparingTranslation = false }
        if on {
            // Открываем то, что занимает капсулу.
            let ids = tabs.map(\.id)
            // По умолчанию «Библиотека»; на другой раздел — только если он сейчас важнее: запись.
            if let leader = director.leader, leader.priority < .limitsNormal, ids.contains(leader.module) {
                tab = leader.module
            } else if ids.contains(.shelf) {
                tab = .shelf
            } else if !ids.contains(tab), let first = ids.first {
                tab = first
            }
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
        if id != tab { shelfTypeSearch.reset() }
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
        let extras = (dots > 0 ? ConsoleLook.labelGap + dots * ConsoleLook.indicator + (dots - 1) * 6 : 0)
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
    static let sideGap = 8.0
    static let mascot = 22.0
    /// Сколько панель стоит после закрытия: столько идёт пружина формы.
    static let closeMilliseconds = 520
    /// Настолько новая страница сдвинута в начале: чуть-чуть, без полёта через всю панель.
    static let pageShift = 24.0
    static let tabs = 30.0
    static let labelGap = 8.0
    static let padding = 12.0
    static let dot = 6.0
    static let indicator = 14.0
    static let alertColor: UInt32 = 0xFF453A
    @MainActor static let labelFont = ConsoleStyle.nsFont(13, .medium)
    @MainActor static let figureFont = ConsoleStyle.nsFont(14, .medium)
}
