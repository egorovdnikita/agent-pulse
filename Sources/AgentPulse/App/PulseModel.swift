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
    private(set) var hoverText: String?
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
    @ObservationIgnored private var scheduler = BubbleScheduler()
    @ObservationIgnored private var stateSince = Date()
    /// Читает HTTP-сервер плагина: нужен ли кадр зеркала прямо сейчас.
    @ObservationIgnored let mirrorWish = MirrorWish()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var consumer: Task<Void, Never>?

    init() {
        (stream, inbox) = AsyncStream.makeStream(of: PulseInput.self, bufferingPolicy: .bufferingNewest(256))
        animator.tuning = tuning
        animator.setState(.sleep, at: Date.timeIntervalSinceReferenceDate)
    }

    func start() {
        let stream = stream
        consumer = Task { [weak self] in
            for await input in stream {
                guard let self else { return }
                switch input {
                case .event(let event):
                    let sessions = await self.store.apply(event)
                    self.handle(event, sessions: sessions)
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
        guard let top = dominant else { return "Нет активных сессий" }
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

    /// При наведении — рассказ о последнем запросе, он важнее фоновой реплики.
    var visibleBubbleText: String? {
        hoverText ?? bubble?.text
    }

    /// Ключ для анимации появления: новое облачко — новая вставка.
    var bubbleKey: Int {
        hoverText != nil ? -1 : bubble?.id ?? 0
    }

    // MARK: - События

    private func handle(_ event: AgentEvent, sessions: [SessionInfo]) {
        let now = event.ts
        lastEventBySource[event.source] = now
        if sessions != self.sessions { self.sessions = sessions }
        lastTask = LastTask.updated(lastTask, event: event, session: sessions.first { $0.id == event.sessionId })

        if let reaction = MascotStateMapper.reaction(for: event), MascotStateMapper.dominant(sessions)?.id == event.sessionId {
            playReaction(reaction, now: now)
        }
        notify(event)
        update(now: now)
    }

    func playReaction(_ reaction: MascotReaction, now: Date = Date()) {
        animator.enqueue(reaction)
        if let trigger = reaction.bubbleTrigger {
            scheduler.react(trigger, now: now)
        }
    }

    private func notify(_ event: AgentEvent) {
        guard let notifier else { return }
        let awaitId = "await-\(event.sessionId)"
        let title = [event.source.displayName, event.context].compactMap(\.self).joined(separator: " · ")
        switch event.kind {
        case .awaitingUser where config.events.awaitingUser.notification:
            let fallback = event.awaitReason == .permission ? "Нужно твоё разрешение" : "Агент ждёт тебя"
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
                    id: "done-\(event.sessionId)", title: title, body: "Готово",
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
        scheduler.ambient(MascotStateMapper.ambientTrigger(for: state, target: activityTarget), heldSince: stateSince, now: now)
        scheduler.tick(now: now)
        updateHover()
        updateMirror(now: now)

        if scheduler.current != bubble {
            let isNew = scheduler.current != nil && scheduler.current?.id != bubble?.id
            bubble = scheduler.current
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
            scheduler.react(MascotStateMapper.waitTrigger(reason), now: now)
        }
        if target == .sleep && previous != .sleep {
            scheduler.react(.fallAsleep, now: now)
        }
        state = target
        stateSince = now
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
            && abs(mouse.y - center.y) <= 26
        let nowInteractive = inside || overBubble
        if nowInteractive != interactive {
            interactive = nowInteractive
            onInteractiveChange?(nowInteractive)
        }

        guard inside != isHovering else { return }
        isHovering = inside
        animator.hovered = inside
        if inside {
            switch state {
            case .sleep, .idle:
                hoverText = lastTask?.summary(now: Date()) ?? scheduler.phrase(for: .hoverSleep)
            default:
                hoverText = scheduler.lastText ?? dominant?.phase.text
            }
        } else {
            hoverText = nil
        }
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

    /// Переход к источнику: активируем приложение, в котором живёт агент.
    func activateSource() {
        guard
            let bundleId = dominant?.hostBundleId,
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
        else { return }
        app.activate()
    }
}
