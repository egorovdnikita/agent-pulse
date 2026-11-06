import AgentPulseCore
import AppKit
import Observation

/// Модель Пульта: модули, директор и что сейчас на экране. Мозг маскота получает от неё только `ToolSignal`.
@MainActor
@Observable
final class ConsoleModel {
    private(set) var limits = LimitsModule()
    private(set) var director = ConsoleDirector()
    private(set) var now = Date()
    private(set) var hovering = false
    private(set) var expanded = false
    /// Сколько места оставляет Dock.
    var fit = ConsoleFit.full(width: ConsoleLayout.maxWidth)
    var expandedWidth = ConsoleLayout.expandedMaxWidth
    /// Пульт на левом краю экрана: растёт вправо. Зеркально — влево.
    var onLeft = true
    var enabled = true
    var limitsEnabled = true

    /// Сигнал для мозга маскота.
    @ObservationIgnored var onSignal: ((ToolSignal, Date) -> Void)?
    /// Новый лидер: маскот на мгновение смотрит на Пульт.
    @ObservationIgnored var onLeaderChange: (() -> Void)?
    /// Изменилось то, от чего зависит размер панели.
    @ObservationIgnored var onLayoutChange: (() -> Void)?
    @ObservationIgnored private var lastTick = Date.distantPast
    @ObservationIgnored private var hoverTask: Task<Void, Never>?

    private var modules: [any ConsoleModule] { limitsEnabled ? [limits] : [] }

    private var candidates: [ConsoleCandidate] {
        modules.compactMap { module in
            module.priority(now: now).map { ConsoleCandidate(module: module.id, priority: $0) }
        }
    }

    /// Кто занимает капсулу. Пока в Р1 модуль один, лидер — всегда он.
    var capsule: CapsuleContent? {
        guard director.leader != nil else { return nil }
        return limits.capsule(now: now)
    }

    var alert: ConsoleAlert? { director.alert }

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

    /// Раз в секунду: сброс окон, удержание лидера, обратный отсчёт. Содержимое не меняется — кадров нет.
    func tick(now: Date, agentWaiting: Bool, inputActive: Bool) {
        guard now.timeIntervalSince(lastTick) >= 1 else { return }
        lastTick = now
        if inputActive { director.noteInput(seconds: 1) }
        self.now = now
        apply(limits.tick(now: now))
        refresh(agentWaiting: agentWaiting)
    }

    private func apply(_ signals: [ToolSignal]) {
        for signal in signals {
            onSignal?(signal, now)
            if signal.isAlert { director.raiseAlert(color: ConsoleLook.alertColor) }
        }
    }

    private func refresh(agentWaiting: Bool) {
        let before = director.leader
        director.update(candidates: candidates, now: now, agentWaiting: agentWaiting, expanded: expanded)
        if director.leader != before {
            onLeaderChange?()
            onLayoutChange?()
        }
    }

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
        expanded = on
        onLayoutChange?()
    }

    func toggle() { setExpanded(!expanded) }

    // MARK: - Размеры

    var showsDot: Bool {
        if case .dot = fit { return true }
        return capsule == nil
    }

    /// Кольца в капсуле; при подписи — одно, того, о ком она.
    var visibleRings: [CapsuleRing] {
        let rings = capsule?.rings ?? []
        return showsLabel ? rings.filter { $0.service == capsule?.labelService } : rings
    }

    /// Показать подпись: курсор над капсулой и хватает места.
    var showsLabel: Bool {
        guard hovering, !expanded, capsule != nil, case .full = fit else { return false }
        return true
    }

    /// Ширина капсулы по содержимому: 96–220 pt; Dock может её сузить.
    var capsuleWidth: Double {
        guard !showsDot else { return ConsoleLayout.dotSize }
        let limit: Double = switch fit {
        case .full(let width): width
        case .leader, .dot: ConsoleLayout.minWidth
        }
        guard showsLabel, let label = capsule?.label else { return min(ConsoleLayout.minWidth, limit) }
        let text = (label as NSString).size(withAttributes: [.font: ConsoleLook.labelFont]).width
        return min(limit, max(ConsoleLayout.minWidth, ConsoleLook.ring + ConsoleLook.labelGap + ceil(text) + ConsoleLook.padding * 2))
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
    static let alertColor: UInt32 = 0xFF453A
    @MainActor static let labelFont: NSFont = {
        let base = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 12) } ?? base
    }()
}
