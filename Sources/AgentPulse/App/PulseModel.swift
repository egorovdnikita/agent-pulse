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
}

/// Связывает ядро с UI: события → `SessionStore` → состояние маскота, облачко, уведомления.
/// Все входы идут через одну очередь, поэтому порядок событий и тиков сохраняется.
@MainActor
@Observable
final class PulseModel {
    private(set) var sessions: [SessionInfo] = []
    private(set) var state: MascotState = .sleep
    private(set) var bubble: Bubble?
    /// При наведении — последнее сообщение (или итог дня), с тем, когда оно было.
    private(set) var hoverMessage: BubbleMessage?
    /// Последнее показанное облачко — его маскот повторяет при наведении.
    private(set) var lastMessage: Bubble?
    private(set) var lastTask: LastTask?
    var overlayVisible = true
    var hooksInstalled = false
    /// Следим ли за журналами Cowork (nil — выключено в настройках).
    var coworkWatching: Bool?
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
    var config = PulseConfig.load()

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

    @ObservationIgnored let animator = MascotAnimator()
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
    }

    func start() {
        var initial = Director(settings: config.character.directorSettings)
        initial.memory = DayMemory.load()
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
                case .tick(let now):
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

    // MARK: - Производные для UI

    var dominant: SessionInfo? {
        MascotStateMapper.dominant(sessions)
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
        case .waitYou: "exclamationmark.circle.fill"
        case .sleep: "moon.circle"
        default: "circle.circle"
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
        lastEventBySource[event.source] = now
        if sessions != self.sessions { self.sessions = sessions }
        lastTask = LastTask.updated(lastTask, event: event, session: sessions.first { $0.id == event.sessionId })
        feedAgentSignals(event)

        if let reaction = MascotStateMapper.reaction(for: event), MascotStateMapper.dominant(sessions)?.id == event.sessionId {
            playReaction(reaction, source: event.source, now: now)
        }
        notify(event)
        update(now: now)
    }

    func playReaction(_ reaction: MascotReaction, source: AgentEvent.Source? = nil, now: Date = Date()) {
        animator.enqueue(reaction)
        lastReaction = "agent.\(reaction.rawValue)"
        if let trigger = reaction.bubbleTrigger {
            let source = source ?? dominant?.source
            scheduler.react(trigger, category: .agent(source), title: BubbleCategory.agentTitle(source), now: now)
        }
    }

    private func notify(_ event: AgentEvent) {
        guard let notifier else { return }
        let awaitId = "await-\(event.sessionId)"
        let title = [event.source.displayName, event.context].compactMap(\.self).joined(separator: " · ")
        switch event.kind {
        case .awaitingUser where config.events.awaitingUser.notification:
            let fallback = event.awaitReason == .permission ? "Мне нужно твоё разрешение" : "Я жду тебя"
            notifier.post(
                id: awaitId, title: title, body: event.summary ?? fallback,
                sound: config.events.awaitingUser.sound != "none", host: event.hostBundleId
            )
        case .stopped:
            notifier.remove(id: awaitId)
            // Если терминал с агентом и так перед глазами — не дублируем.
            let hostIsFront = event.hostBundleId != nil && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == event.hostBundleId
            if config.events.done.notification && !hostIsFront {
                notifier.post(
                    id: "done-\(event.sessionId)", title: title, body: "Готово, проверь",
                    sound: config.events.done.sound != "none", host: event.hostBundleId
                )
            }
        case .promptSubmitted, .toolStarted, .toolFinished, .sessionEnded:
            notifier.remove(id: awaitId)
        default:
            break
        }
    }

    // MARK: - Тик

    private func update(now: Date) {
        animator.reduceMotion = labReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let target = labOverride ?? MascotStateMapper.state(for: sessions, now: now, sleepAfter: tuning.sleepAfter)
        if target != state {
            // Анти-дребезг: состояние держится минимум minStateHold; ожидание пользователя — сразу.
            if target.isWaiting || now.timeIntervalSince(stateSince) >= tuning.minStateHold {
                transition(to: target, now: now)
            }
        }

        let activityTarget: WorkTarget? = if case .working(let activity) = dominant?.phase { activity.target } else { nil }
        scheduler.ambient(
            MascotStateMapper.ambientTrigger(for: state, target: activityTarget),
            category: .agent(dominant?.source), title: BubbleCategory.agentTitle(dominant?.source), heldSince: stateSince, now: now
        )
        scheduler.tick(now: now)
        updateHover()
        updateMirror(now: now)
        updateAgentBusy(now: now)

        if scheduler.current != bubble {
            let isNew = scheduler.current != nil && scheduler.current?.id != bubble?.id
            bubble = scheduler.current
            if let bubble { lastMessage = bubble }
            if isNew {
                // Маскот на мгновение смотрит на облачко — связывает реплику с персонажем.
                animator.glance(towardX: config.display.anchor.isRight ? -1 : 1, at: now.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func transition(to target: MascotState, now: Date) {
        let previous = state
        if previous.isWaiting && !target.isWaiting {
            scheduler.endWait(now: now)
        }
        if case .waitYou(let reason) = target, previous != target {
            scheduler.react(
                MascotStateMapper.waitTrigger(reason), category: .agent(dominant?.source),
                title: BubbleCategory.agentTitle(dominant?.source), now: now
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
        let showingIt = visibleMessage?.category == .news && lastMessage?.category == .news
        return Date().timeIntervalSince(at) < (showingIt ? 12 * 3600 : 90) ? item : nil
    }

    /// Клик по облачку: новость — открыть статью, иначе как клик по маскоту.
    func tapBubble() {
        if let news = recentNews, let url = URL(string: news.link) {
            NSWorkspace.shared.open(url)
        } else {
            activateSource()
        }
    }

    /// Клик по маскоту: новость — открыть статью; в агентном состоянии — переход к источнику; иначе — тычок.
    func tapMascot() {
        if let news = recentNews, let url = URL(string: news.link) {
            NSWorkspace.shared.open(url)
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
        }
    }

    /// Что показать при наведении. По порядку: что делаю сейчас; что было без тебя; последнее сообщение;
    /// вечером, если сообщение давнее, — итог дня (в пятницу и выходные — недели); иначе «Я тут».
    private func restingMessage(now: Date) -> BubbleMessage {
        if let top = dominant, state != .sleep, state != .idle {
            return HoverStory.working(source: top.source, phase: top.phase, since: promptAt[top.id] ?? top.phaseSince, steps: top.timeline.count, now: now)
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
            var when = HumanTime.ago(age)
            // Под новостью — сколько ещё свежего ждёт своей очереди.
            let more = last.category == .news ? newsDesk.available(now: now).count : 0
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

    /// Переход к источнику: активируем приложение, в котором живёт агент.
    func activateSource() {
        guard
            let bundleId = dominant?.hostBundleId,
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
        else { return }
        app.activate()
    }
}
