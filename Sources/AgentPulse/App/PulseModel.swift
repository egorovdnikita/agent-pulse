import AgentPulseCore
import AppKit
import Observation

struct MirrorFrame {
    let id: Int
    let image: NSImage
    let node: String
    let file: String
    let at: Date
}

enum PulseInput: Sendable {
    case event(AgentEvent)
    case signal(Signal)
    case tick(Date)
    case limits(LimitSnapshot)
}

/// Связывает ядро с UI: события → `SessionStore` → состояние маскота, облачко, уведомления.
/// Все входы идут через одну очередь, поэтому порядок событий и тиков сохраняется.
@MainActor
@Observable
final class PulseModel {
    private(set) var sessions: [SessionInfo] = []
    @ObservationIgnored private var completions = CompletionBatch()
    @ObservationIgnored private var completionTarget: CompletionBatch.Entry?
    /// Ожидания, которые ты уже видел (`MascotStateMapper.waitKey`): маскот им больше не служит.
    private var seenWaits: [String: Date] = [:]
    /// Последний полный тик мозга: спрятанным тикает реже.
    private var lastTickAt: Date = .distantPast
    /// Сессии глазами маскота: увиденное ожидание уступает работе других агентов или покою.
    var mascotSessions: [SessionInfo] {
        MascotStateMapper.demotingSeen(sessions, seen: seenWaits)
    }
    private(set) var state: MascotState = .sleep
    private(set) var bubble: Bubble?
    /// При наведении — последнее сообщение (или итог дня), с тем, когда оно было.
    private(set) var hoverMessage: BubbleMessage?
    /// Последнее показанное облачко — его маскот повторяет при наведении.
    private(set) var lastMessage: Bubble?
    private(set) var lastTask: LastTask?
    var overlayVisible = true
    /// Панель закрыта целиком (полноэкранный рабочий стол) — кадры маскота на паузе.
    var overlayOccluded = false
    var hooksInstalled = false
    /// Обёртка statusline стоит: Пульт получает лимиты Claude.
    var statuslineInstalled = false
    /// Исходная команда в обёртке ссылается на скрипт, которого больше нет.
    var statuslineBroken = false
    /// Что с лимитами Codex: для настроек.
    var codexStatus: String?
    /// Следим ли за журналами Cowork (nil — выключено в настройках).
    var coworkWatching: Bool?
    /// Следим ли за агентами в Orca (nil — выключено в настройках).
    var orcaWatching: Bool?
    var browserBridgeInstalled = false
    var companionError: String?
    /// Есть ли у приложения разрешение «Универсальный доступ» (нужно для чата в Claude desktop).
    var accessibilityTrusted = false
    var launchAtLogin = false
    /// Когда от каждого источника пришло последнее событие.
    private(set) var lastEventBySource: [AgentEvent.Source: Date] = [:]
    /// Последний кадр зеркала Figma.
    private(set) var mirror: MirrorFrame?
    private(set) var showMirror = false
    private(set) var isHovering = false
    var serverError: String?
    var config = PulseConfig.load() {
        didSet { if oldValue.mascot != config.mascot { applySkin() } }
    }

    // Мозг
    var mood = Mood()
    var quiet = false
    /// Последняя реакция — для кнопок «мило» и «бесит».
    var lastReaction: String?
    var lastLine: String?
    /// Что случилось у агентов без тебя — показывается при наведении 10 минут после возвращения.
    var awayNews: AwayNews?
    var awayNewsAt: Date?
    /// Новости дизайна: что уже показано, и последняя рассказанная.
    @ObservationIgnored var newsDesk = NewsDesk.load()
    var currentNews: NewsItem?
    var currentNewsAt: Date?
    /// Счётчики дня — вечерний итог при наведении.
    var today: DayMemory.Day?
    /// Сумма за 7 дней — итог недели при наведении.
    var week: DayMemory.Day?
    /// Оценки за сегодня: «мило» и «бесит».
    var feedbackToday: [String: Int] = [:]
    /// Реакции, которые бесят (два «бесит» за неделю), — только глазами.
    var mutedReactions: Set<String> = []

    /// MascotLab: ручное состояние поверх живого.
    var labOverride: MascotState? {
        didSet { update(now: Date()) }
    }
    var labReduceMotion = false
    var tuning = MascotTuning() {
        didSet {
            animator.tuning = tuning
            scheduler.tuning = tuning.bubble
        }
    }

    @ObservationIgnored let console = ConsoleModel()
    /// Агент Codex что-то закончил — лимиты могли измениться.
    @ObservationIgnored var onCodexActivity: (() -> Void)?
    @ObservationIgnored let animator = MascotAnimator()
    @ObservationIgnored var wardrobe = PalWardrobe()
    @ObservationIgnored var installedBots: Set<String> = []
    @ObservationIgnored weak var notifier: Notifier?
    /// Курсор над маскотом или облачком — панель должна ловить мышь.
    @ObservationIgnored var onInteractiveChange: ((Bool) -> Void)?
    @ObservationIgnored private var interactive = false
    @ObservationIgnored nonisolated let inbox: AsyncStream<PulseInput>.Continuation
    @ObservationIgnored private let stream: AsyncStream<PulseInput>
    @ObservationIgnored private let store = SessionStore()
    @ObservationIgnored var scheduler = BubbleScheduler()
    @ObservationIgnored private(set) var stateSince = Date()
    /// Читает HTTP-сервер плагина: нужен ли кадр зеркала прямо сейчас.
    @ObservationIgnored let mirrorWish = MirrorWish()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var consumer: Task<Void, Never>?
    @ObservationIgnored private(set) var director = DirectorActor()
    @ObservationIgnored var body = BodyCondition()
    /// Особые поведения двигают саму панель — их исполняет делегат.
    @ObservationIgnored var onSpecial: ((SpecialAction, String?) -> Void)?
    /// Спрятать панель после долгого простоя (hideWhenIdle) и показать снова.
    @ObservationIgnored var onIdleHide: ((Bool) -> Void)?
    /// Ты пришёл — маскот возвращается домой (после лунатизма или пряток).
    @ObservationIgnored var onUserBack: (() -> Void)?
    @ObservationIgnored var strokeTrail: [(Date, Double)] = []
    @ObservationIgnored var lastMouse: (Date, CGPoint)?
    /// Курсор по всему экрану за последнюю секунду — чтобы заметить, что его трясут.
    @ObservationIgnored var shakeTrail: [(Date, Double)] = []
    /// Номер содержимого перетаскивания, о котором маскот уже удивился.
    @ObservationIgnored var carriedCount = NSPasteboard(name: .drag).changeCount
    /// Служебные отметки между запусками: внезапное выключение, новая macOS, первая встреча.
    @ObservationIgnored var launch = LaunchRecord.load()
    @ObservationIgnored var hiddenForIdle = false
    @ObservationIgnored var promptAt: [String: Date] = [:]
    @ObservationIgnored var toolErrorStreak = 0
    @ObservationIgnored var waitLongSent = false
    @ObservationIgnored var agentBusy = false
    @ObservationIgnored var lastMemorySave = Date()

    init() {
        (stream, inbox) = AsyncStream.makeStream(of: PulseInput.self, bufferingPolicy: .bufferingNewest(256))
        animator.tuning = tuning
        animator.setState(.sleep, at: Date.timeIntervalSinceReferenceDate)
        applySkin()
        connectConsole()
    }

    /// Пульт отдаёт маскоту только обезличенные сигналы. Маскот говорит, Пульт показывает.
    private func connectConsole() {
        let inbox = inbox
        console.enabled = config.console.enabled
        console.limitsEnabled = config.console.limits
        console.prompterEnabled = config.console.prompter
        console.setPrompterSpeed(config.console.prompterSpeed)
        console.setPrompterFollowsVoice(config.console.prompterVoice)
        console.prompterTextSize = config.console.prompterTextSize
        console.dictationEnabled = config.console.dictation
        console.dictationRules = config.console.dictationRules
        console.translatorEnabled = config.console.translator && ConsoleTranslator.isAvailable
        console.shelfEnabled = config.console.shelf
        console.onSound = { [weak self] sound in self?.playSound(sound) }
        console.onSignal = { [weak self] signal, now in
            if let brain = signal.signal(at: now) { inbox.yield(.signal(brain)) }
            self?.notifyConsole(signal)
        }
        console.onLeaderChange = { [weak self] in
            // Только в покое: взгляд не перебивает wait_you и работу агента. Пульт — в углу напротив маскота.
            guard let self, self.state == .idle else { return }
            self.animator.glance(towardX: self.config.display.anchor.isRight ? -1 : 1, at: Date.timeIntervalSinceReferenceDate)
        }
    }

    /// В полном экране Пульта не видно: встреча через минуту и лимит «критично» приходят уведомлением, как «ждёт тебя».
    /// Запись диктовки созвоном не считается: для её звуков созвон — это только занятая камера.
    private func playSound(_ sound: ConsoleSound) {
        let call = sound.isDictation ? QuietSense.cameraInUse() : quiet
        guard ConsoleSound.allowed(
            sound, enabled: config.console.sounds, prompter: console.prompter.isActive, call: call,
            quietHours: config.character.isQuietHours(Date())
        ) else { return }
        ConsoleSounds.play(sound)
    }

    private func notifyConsole(_ signal: ToolSignal) {
        guard overlayOccluded else { return }
        switch signal {
        case .limitCritical(let service):
            notifier?.post(id: "limit-\(service.rawValue)", title: "Лимиты", body: "\(service.title): лимит почти исчерпан", sound: false, host: nil)
        default:
            break
        }
    }

    /// Курсор над телом маскота: файл принимается только здесь, а не на всей панели с облачком.
    var cursorOverMascot: Bool {
        guard let center = animator.screenCenter else { return false }
        let mouse = NSEvent.mouseLocation
        return hypot(mouse.x - center.x, mouse.y - center.y) <= config.display.mascotSize / 2 + 8
    }

    /// Съел файл и передал на полку. Мозг получает только сигнал, без имени и пути.
    func feedMascot(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        inbox.yield(.signal(Signal(.console, .fileEaten)))
        console.addToShelf(urls)
    }

    /// Какие боты Agent Pals установлены целиком; перечитывается при смене облика в настройках.
    func applySkin() {
        installedBots = Set(PalSkin.installed().map(\.bot))
        updateWardrobe(now: Date())
    }

    /// Какой бот сейчас на маскоте — правила в `PalWardrobe`: сменяется сам на новой задаче и при пробуждении.
    func updateWardrobe(now: Date) {
        let bot = wardrobe.update(
            mode: PalWardrobe.Mode(config: config.mascot.skin), installed: installedBots, state: state,
            at: now.timeIntervalSinceReferenceDate
        )
        animator.skin = bot.map(PalSkin.init(bot:))
        console.librarySkin = animator.skin
    }

    func start() {
        // Mac между запусками: выключился внезапно, обновилась система. Сказать, когда всё проснётся.
        let started = launch.start(bootTime: Date().timeIntervalSince1970 - ClockSense.uptime,
                                   osVersion: LaunchRecord.systemVersion(ProcessInfo.processInfo.operatingSystemVersion, build: Self.osBuild),
                                   now: Date())
        try? launch.save()
        for (index, kind) in started.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8 + Double(index) * 6) { [weak self] in self?.simulate(kind) }
        }
        var initial = Director(settings: directorSettings)
        initial.memory = DayMemory.load()
        initial.ledger = ReactionLedger.load()
        initial.mutedReactions = Self.loadMuted()
        mutedReactions = initial.mutedReactions
        director = DirectorActor(initial)
        body.darkTheme = AppearanceSense.isDark
        let stream = stream
        consumer = Task { [weak self] in
            for await input in stream {
                guard let self else { return }
                switch input {
                case .event(let event):
                    let sessions = await self.store.apply(event)
                    self.handle(event, sessions: sessions)
                case .signal(let signal):
                    await self.handleSignal(signal)
                case .limits(let snapshot):
                    self.console.ingest(snapshot)
                    self.console.limits.book.save()
                case .tick(let now):
                    // Маскот спрятан (полный экран, простой) — курсор и облачко не нужны, мозг тикает раз в секунду.
                    // Во сне — как обычно: тряска курсора и поглаживание ловятся только на частых замерах.
                    if self.overlayOccluded, now.timeIntervalSince(self.lastTickAt) < 1 { continue }
                    self.lastTickAt = now
                    let sessions = await self.store.tick(now: now)
                    if sessions != self.sessions { self.sessions = sessions }
                    self.update(now: now)
                }
            }
        }
        let inbox = inbox
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            inbox.yield(.tick(Date()))
        }
    }

    /// Номер сборки macOS («25G83») — тот, что меняется при любом обновлении.
    static var osBuild: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    // MARK: - Производные для UI

    var dominant: SessionInfo? {
        MascotStateMapper.dominant(mascotSessions)
    }

    /// Сессии, где агент что-то делает или ждёт: их больше одной — на маскоте счётчик.
    var activeSessions: [SessionInfo] {
        sessions.filter { $0.phase != .idle }
    }

    var statusLine: String {
        guard let top = dominant else { return "Сейчас никто не работает" }
        let project = top.context.map { "\($0): " } ?? ""
        return project + top.phase.text
    }

    var menuSymbol: String {
        switch state {
        case .waitYou: "bell-bing"
        case .sleep: "moon-sleep"
        default: "sleeping-circle"
        }
    }

    /// Что сейчас в облачке: текущая реплика или, при наведении, последнее сообщение.
    var visibleMessage: BubbleMessage? {
        if let bubble { return BubbleMessage(bubble) }
        return hoverMessage
    }

    var visibleBubbleText: String? { visibleMessage?.text }

    /// Ключ для анимации появления: новое облачко — новая вставка.
    var bubbleKey: Int {
        bubble?.id ?? (hoverMessage != nil ? -1 : 0)
    }

    // MARK: - События

    private func handle(_ event: AgentEvent, sessions: [SessionInfo]) {
        let now = event.ts
        completions.observe(event)
        lastEventBySource[event.source] = now
        if sessions != self.sessions { self.sessions = sessions }
        lastTask = LastTask.updated(lastTask, event: event, session: sessions.first { $0.id == event.sessionId })
        feedAgentSignals(event)
        if event.kind == .rateLimited, let service = LimitService(source: event.source) { console.markResting(service) }
        if event.kind == .stopped, event.source == .codex || event.agent == "Codex" { onCodexActivity?() }

        if (event.kind != .stopped || event.isError), let reaction = MascotStateMapper.reaction(for: event), MascotStateMapper.dominant(sessions)?.id == event.sessionId {
            let host = sessions.first { $0.id == event.sessionId }?.hostBundleId ?? event.hostBundleId
            playReaction(reaction, source: event.source, host: host, now: now)
        }
        notify(event)
        update(now: now)
    }

    func playReaction(_ reaction: MascotReaction, source: AgentEvent.Source? = nil, host: String? = nil, now: Date = Date()) {
        animator.enqueue(reaction)
        lastReaction = "agent.\(reaction.rawValue)"
        if let trigger = reaction.bubbleTrigger {
            let host = source == nil ? dominant?.hostBundleId : host
            let source = source ?? dominant?.source
            scheduler.react(
                trigger, category: .agent(source, host: host), title: BubbleCategory.agentTitle(source, host: host), now: now
            )
        }
    }

    private func notify(_ event: AgentEvent) {
        guard let notifier else { return }
        let awaitId = "await-\(event.sessionId)"
        let origin = BubbleCategory.origin(event.source, agent: event.agent, host: event.hostBundleId)
        let title = [origin, event.context].compactMap(\.self).joined(separator: " · ")
        // Маскота видно — он скажет сам; уведомление только когда его не видно (полный экран, спрятан).
        let mascotHidden = overlayOccluded
        switch event.kind {
        case .awaitingUser where config.events.awaitingUser.notification && mascotHidden:
            let fallback = event.awaitReason == .permission ? "Мне нужно твоё разрешение" : "Я жду тебя"
            notifier.post(
                id: awaitId, title: title, body: event.summary ?? fallback,
                sound: config.events.awaitingUser.sound != "none", host: event.hostBundleId,
                source: event.source, sessionID: event.sessionId
            )
        case .stopped:
            notifier.remove(id: awaitId)
            if config.events.done.notification && mascotHidden && event.isError {
                notifier.post(
                    id: "done-\(event.sessionId)", title: title, body: "Готово, проверь",
                    sound: config.events.done.sound != "none", host: event.hostBundleId,
                    source: event.source, sessionID: event.sessionId
                )
            }
        case .promptSubmitted, .toolStarted, .toolFinished, .sessionEnded, .rateLimited:
            notifier.remove(id: awaitId)
        default:
            break
        }
    }

    private func flushCompletions(now: Date) {
        let urgent = mascotSessions.contains { MascotStateMapper.rank($0.phase) >= 5 }
        guard let batch = completions.takeReady(now: now, allowed: overlayOccluded || !urgent), let latest = batch.last else { return }
        let sameOrigin = batch.allSatisfy { $0.source == latest.source && $0.host == latest.host }
        let title = sameOrigin ? BubbleCategory.agentTitle(latest.source, host: latest.host) : "Нейросети"
        let text = batch.count == 1 ? "Готово, проверь" : "Готово: \(batch.count) \(HumanTime.plural(batch.count, "задача", "задачи", "задач"))"
        completionTarget = latest
        if overlayOccluded {
            if config.events.done.notification {
                notifier?.post(id: "done-batch-" + latest.id, title: title, body: text,
                               sound: config.events.done.sound != "none", host: latest.host, source: latest.source, sessionID: latest.id)
            }
        } else if batch.count == 1 {
            playReaction(.done, source: latest.source, host: latest.host, now: now)
        } else {
            animator.enqueue(.done)
            lastReaction = "agent.done"
            scheduler.say(text, duration: max(scheduler.tuning.result, BubbleTuning.readingTime(text)),
                          category: sameOrigin ? .agent(latest.source, host: latest.host) : .together,
                          title: title, agent: true, now: now)
        }
    }

    // MARK: - Тик

    private func update(now: Date) {
        animator.reduceMotion = labReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // Увиденные ожидания забываются, когда сессия перестала ждать.
        let waitingKeys = Set(sessions.compactMap(MascotStateMapper.waitKey))
        if seenWaits.keys.contains(where: { !waitingKeys.contains($0) }) { seenWaits = seenWaits.filter { waitingKeys.contains($0.key) } }
        let target = labOverride ?? MascotStateMapper.state(for: mascotSessions, now: now, sleepAfter: tuning.sleepAfter)
        if case .working(let activity) = dominant?.phase { animator.workTarget = activity.target }
        updateWardrobe(now: now)
        if target != state {
            // Анти-дребезг: состояние держится минимум minStateHold; ожидание пользователя — сразу.
            if target.isWaiting || now.timeIntervalSince(stateSince) >= tuning.minStateHold {
                transition(to: target, now: now)
            }
        }

        let activityTarget: WorkTarget? = if case .working(let activity) = dominant?.phase { activity.target } else { nil }
        scheduler.ambient(
            MascotStateMapper.ambientTrigger(for: state, target: activityTarget),
            category: .agent(dominant?.source, host: dominant?.hostBundleId),
            title: BubbleCategory.agentTitle(dominant?.source, host: dominant?.hostBundleId), heldSince: stateSince, now: now
        )
        if scheduler.noteActivity(active: PresenceSense.idleSeconds < 1.5, now: now) {
            for key in waitingKeys { seenWaits[key] = now }
            Self.brainLog.notice("wait seen → \(MascotStateMapper.state(for: self.mascotSessions, now: now, sleepAfter: self.tuning.sleepAfter).logName, privacy: .public)")
        }
        flushCompletions(now: now)
        scheduler.tick(now: now)
        console.tick(now: now, agentWaiting: state.isWaiting, inputActive: PresenceSense.idleSeconds < 1.5)
        updateHover()
        updateMirror(now: now)
        updateAgentBusy(now: now)

        if scheduler.current != bubble {
            let isNew = scheduler.current != nil && scheduler.current?.id != bubble?.id
            bubble = scheduler.current
            if let bubble { lastMessage = bubble }
            // Говорит во сне — странно: на время облачка просыпается. Кроме «Вздремну».
            animator.speaking = bubble.map { $0.category != .rest } ?? false
            if isNew, let bubble, bubble.trigger.isWait {
                // VoiceOver: самое важное — «жду тебя» — зачитывается вслух. Остальное — нет, чтобы не болтать.
                NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                    .announcement: "\(bubble.title): \(bubble.text)",
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ])
            }
            if isNew {
                // Маскот на мгновение смотрит на облачко — связывает реплику с персонажем.
                animator.glance(towardX: config.display.anchor.isRight ? -1 : 1, at: now.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func transition(to target: MascotState, now: Date) {
        let previous = state
        let summary = sessions.map { "\($0.source.rawValue):\($0.phase.logName)" }.joined(separator: ",")
        Self.brainLog.notice("state \(previous.logName, privacy: .public) → \(target.logName, privacy: .public) [\(summary, privacy: .public)]")
        if previous.isWaiting && !target.isWaiting {
            scheduler.endWait(now: now)
        }
        if case .waitYou(let reason) = target, previous != target {
            scheduler.react(
                MascotStateMapper.waitTrigger(reason), category: .agent(dominant?.source, host: dominant?.hostBundleId),
                title: BubbleCategory.agentTitle(dominant?.source, host: dominant?.hostBundleId), now: now
            )
        }
        if target == .sleep && previous != .sleep {
            scheduler.react(.fallAsleep, now: now)
        }
        state = target
        stateSince = now
        waitLongSent = false
        animator.setState(target, at: now.timeIntervalSinceReferenceDate)
    }

    // MARK: - Hover и клик

    /// Hover считаем по положению курсора, а не по tracking area: панель не бывает ключевой.
    private func updateHover() {
        guard let center = animator.screenCenter else { return }
        let mouse = NSEvent.mouseLocation
        let diameter = config.display.mascotSize
        let inside = hypot(mouse.x - center.x, mouse.y - center.y) <= diameter / 2 + 4

        // Облачко лежит со стороны, противоположной краю экрана.
        let box = MascotView.boxSize(diameter)
        let near = box / 2 - PillView.bubbleOverlap(diameter: diameter)
        let bubbleMinX = config.display.anchor.isRight ? center.x - near - BubbleView.maxWidth : center.x + near
        let overBubble = visibleBubbleText != nil
            && mouse.x >= bubbleMinX && mouse.x <= bubbleMinX + BubbleView.maxWidth
            && abs(mouse.y - center.y) <= 46
        let nowInteractive = inside || overBubble
        if nowInteractive != interactive {
            interactive = nowInteractive
            onInteractiveChange?(nowInteractive)
        }

        if inside { detectStroke(mouse.x) } else if !strokeTrail.isEmpty { strokeTrail.removeAll() }
        detectFlyby(mouse, center: center, radius: diameter / 2)
        detectShake(mouse.x)
        detectCarried(mouse, center: center, radius: diameter / 2)
        // Печатаешь — маскот не мельтешит.
        animator.typing = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 1.5

        guard inside != isHovering else { return }
        isHovering = inside
        animator.hovered = inside
        hoverMessage = inside ? restingMessage(now: Date()) : nil
    }

    // MARK: - Зеркало Figma

    func receiveFrame(_ frame: FigmaFrame) {
        guard config.sources.figmaMirror, let image = NSImage(data: frame.png) else { return }
        mirror = MirrorFrame(id: (mirror?.id ?? 0) + 1, image: image, node: frame.node, file: frame.file, at: frame.at)
    }

    /// Зеркало видно, пока агент рисует в Figma (и минуту после), или при наведении — 10 минут после кадра.
    private func updateMirror(now: Date) {
        let drawing = if case .working(let activity) = dominant?.phase { activity.target == .figma } else { false }
        mirrorWish.value = drawing && config.sources.figmaMirror
        let age = mirror.map { now.timeIntervalSince($0.at) } ?? .infinity
        let visible = (drawing && age < 60) || (isHovering && age < 600)
        if visible != showMirror { showMirror = visible }
    }

    /// Только что рассказанная новость — клик открывает статью. При наведении на неё — ещё 12 часов.
    var recentNews: NewsItem? {
        guard let item = currentNews, let at = currentNewsAt else { return nil }
        let showingIt = visibleMessage?.category.isNews == true && lastMessage?.category.isNews == true
        return Date().timeIntervalSince(at) < (showingIt ? 12 * 3600 : 90) ? item : nil
    }

    /// Клик по облачку: новость — открыть статью, иначе как клик по маскоту.
    func tapBubble() {
        if let news = recentNews, let url = URL(string: news.link) {
            open(news, url)
        } else {
            activateSource()
        }
    }

    /// Открыл статью — запоминаем вкус: такие темы и источники звучат чаще.
    private func open(_ news: NewsItem, _ url: URL) {
        NSWorkspace.shared.open(url)
        newsDesk.record(.opened, for: news)
        saveNewsDesk()
    }

    /// Клик по маскоту: новость — открыть статью; в агентном состоянии — переход к источнику; иначе — тычок.
    func tapMascot() {
        if let news = recentNews, let url = URL(string: news.link) {
            open(news, url)
            return
        }
        switch state {
        case .work, .think, .waitYou:
            activateSource()
        case .idle, .sleep:
            if let done = lastTask, Date().timeIntervalSince(done.at) < 60, dominant?.hostBundleId != nil {
                activateSource()
            } else {
                simulate(.poke)
                Haptics.tap()
            }
        }
    }

    /// Поглаживание: курсор ходит туда-сюда над маскотом — три разворота за полторы секунды.
    private func detectStroke(_ x: Double) {
        let now = Date()
        strokeTrail = strokeTrail.filter { now.timeIntervalSince($0.0) < 1.5 } + [(now, x)]
        var reversals = 0
        var direction = 0.0
        var travel = 0.0
        for (previous, next) in zip(strokeTrail, strokeTrail.dropFirst()) {
            let dx = next.1 - previous.1
            guard abs(dx) > 2 else { continue }
            travel += abs(dx)
            if direction != 0, (dx > 0) != (direction > 0) { reversals += 1 }
            direction = dx
        }
        if reversals >= 3, travel > 30 {
            strokeTrail.removeAll()
            simulate(.stroke)
            Haptics.purr()
        }
    }

    /// Трясёшь курсор, чтобы найти его (macOS его увеличивает): четыре разворота и много пути за секунду.
    private func detectShake(_ x: Double) {
        let now = Date()
        shakeTrail = shakeTrail.filter { now.timeIntervalSince($0.0) < 1 } + [(now, x)]
        var reversals = 0
        var direction = 0.0
        var travel = 0.0
        for (previous, next) in zip(shakeTrail, shakeTrail.dropFirst()) {
            let dx = next.1 - previous.1
            guard abs(dx) > 20 else { continue }
            travel += abs(dx)
            if direction != 0, (dx > 0) != (direction > 0) { reversals += 1 }
            direction = dx
        }
        if reversals >= 4, travel > tuning.shakeTravel {
            shakeTrail.removeAll()
            simulate(.cursorShake)
        }
    }

    /// Над маскотом несут файл: кнопка зажата, а у системного буфера перетаскивания новое содержимое.
    /// Что несут — не читаем, только номер изменения.
    private func detectCarried(_ mouse: CGPoint, center: CGPoint, radius: Double) {
        guard NSEvent.pressedMouseButtons & 1 != 0, hypot(mouse.x - center.x, mouse.y - center.y) <= radius + 12 else { return }
        let count = NSPasteboard(name: .drag).changeCount
        guard count != carriedCount else { return }
        carriedCount = count
        simulate(.itemCarried)
    }

    /// Что показать при наведении. По порядку: что делаю сейчас; что было без тебя; последнее сообщение;
    /// вечером, если сообщение давнее, — итог дня (в пятницу и выходные — недели); иначе «Я тут».
    private func restingMessage(now: Date) -> BubbleMessage {
        // Ожидание, которое ты уже видел, маскот не изображает, но при наведении напоминает о нём первым.
        if let waiting = MascotStateMapper.dominant(sessions), case .awaitingUser = waiting.phase,
           MascotStateMapper.waitKey(waiting).map({ seenWaits[$0] != nil }) == true {
            return HoverStory.working(source: waiting.source, host: waiting.hostBundleId, phase: waiting.phase, since: waiting.phaseSince, steps: 0, now: now)
        }
        if let top = dominant, state != .sleep, state != .idle {
            return HoverStory.working(source: top.source, host: top.hostBundleId, phase: top.phase, since: promptAt[top.id] ?? top.phaseSince, steps: top.timeline.count, now: now)
        }
        if let news = awayNews, let at = awayNewsAt, now.timeIntervalSince(at) < 10 * 60 {
            return BubbleMessage(category: .claude, title: "Claude", text: news.summary, when: HumanTime.ago(now.timeIntervalSince(at)))
        }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let age = lastMessage.map { now.timeIntervalSince($0.shownAt) } ?? .infinity
        let summary = today.flatMap { day in
            HoverStory.summary(today: day, week: week ?? day, weekday: calendar.component(.weekday, from: now), hour: hour)
        }
        if let summary, hour >= 18 || calendar.isDateInWeekend(now), age > 30 * 60 {
            return summary
        }
        if let last = lastMessage, age < 12 * 3600 {
            var when = [last.note, HumanTime.ago(age)].compactMap(\.self).joined(separator: " · ")
            // Под новостью — сколько ещё свежего ждёт своей очереди.
            let more = last.category.isNews ? newsDesk.available(now: now).count : 0
            if more > 0 { when += " · ещё \(more)" }
            return BubbleMessage(category: last.category, title: last.title, text: last.text, when: when)
        }
        return summary ?? BubbleMessage(category: .rest, title: BubbleCategory.rest.title, text: scheduler.phrase(for: .hoverSleep))
    }

    /// Курсор быстро прошёл сквозь маскота: отрезок между двумя замерами задевает тело.
    private func detectFlyby(_ mouse: CGPoint, center: CGPoint, radius: Double) {
        let now = Date()
        defer { lastMouse = (now, mouse) }
        guard let (then, from) = lastMouse, !isHovering else { return }
        let dt = now.timeIntervalSince(then)
        guard dt > 0, dt < 0.3 else { return }
        let dx = mouse.x - from.x, dy = mouse.y - from.y
        let length = hypot(dx, dy)
        guard length / dt > tuning.flybySpeed, length > 0 else { return }
        // Ближайшая к центру точка отрезка.
        let along = max(0, min(1, ((center.x - from.x) * dx + (center.y - from.y) * dy) / (length * length)))
        let closest = CGPoint(x: from.x + along * dx, y: from.y + along * dy)
        if hypot(closest.x - center.x, closest.y - center.y) <= radius {
            simulate(.cursorFlyby, value: length / dt)
        }
    }

    /// Реплика от имени тела (прятки: «Ку-ку»).
    func say(_ text: String, duration: TimeInterval) {
        scheduler.say(text, duration: duration, category: .mood, now: Date())
    }

    /// Клик ведёт к видимому завершению; ожидание пользователя сохраняет приоритет.
    func activateSource() {
        if let session = dominant, case .awaitingUser = session.phase {
            AgentNavigation.open(source: session.source, sessionID: session.id, host: session.hostBundleId)
        } else if let target = completionTarget, let bubble,
                  bubble.trigger == .done || (bubble.trigger == .line && bubble.text.hasPrefix("Готово: ")) {
            AgentNavigation.open(source: target.source, sessionID: target.id, host: target.host)
        } else if let session = dominant {
            AgentNavigation.open(source: session.source, sessionID: session.id, host: session.hostBundleId)
        }
    }

}

/// Короткие имена для журнала: только вид фазы, без текста сообщений.
extension MascotState {
    var logName: String {
        switch self {
        case .waitYou: "wait"
        case .work: "work"
        default: String(describing: self)
        }
    }
}

extension Phase {
    var logName: String {
        switch self {
        case .idle: "idle"
        case .received: "received"
        case .thinking: "thinking"
        case .working: "working"
        case .awaitingUser: "awaiting"
        case .done: "done"
        case .failed: "failed"
        case .resting: "resting"
        }
    }
}
