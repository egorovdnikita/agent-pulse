import AgentPulseCore
import AppKit
import SwiftUI

/// Панель поверх всех окон: не крадёт фокус, видна на всех Spaces и поверх полноэкранных приложений.
@MainActor
final class OverlayPanel: NSPanel {
    private let model: PulseModel
    private var currentScreen: NSScreen?

    init(app: AppDelegate) {
        let model = app.model
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        // Без `.fullScreenAuxiliary` **[решение]**: на полноэкранном рабочем столе (видео, презентация, игра)
        // macOS сам не показывает маскота — он не мешает; вышел из полного экрана — маскот на месте.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        // Прозрачные места панели пропускают клики (Dock рядом); ловим мышь только над маскотом и облачком.
        ignoresMouseEvents = true
        model.onInteractiveChange = { [weak self] interactive in
            self?.ignoresMouseEvents = !interactive
        }
        let host = FirstMouseHostingView(rootView: PillView(model: model, app: app))
        // Размер панели задаём сами. Иначе хост пересчитывает размеры окна на каждом кадре анимации —
        // это был главный расход CPU в простое.
        host.sizingOptions = []
        contentView = host
        reposition()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func followActiveScreen() {
        // Курсор ушёл на другой монитор или Dock переехал — панель следует.
        guard let screen = targetScreen(), screen != currentScreen else { return }
        reposition()
    }

    /// Позиция — анкер + отступ на текущем мониторе, а не абсолютные координаты:
    /// при отключении внешнего экрана панель не уезжает за край.
    func reposition() {
        guard motion == nil, !dragging, peek == .none, !walking else { return }
        guard let screen = targetScreen() else { return }
        currentScreen = screen
        let size = PillView.size(diameter: model.config.display.mascotSize)
        setFrame(NSRect(origin: homeOrigin(on: screen), size: size), display: true)
        updateCenter()
        model.animator.zzzSide = model.config.display.anchor.isRight ? -1 : 1
    }

    /// Угол по умолчанию: по горизонтали внутри видимой области (боковой Dock не перекрываем);
    /// снизу — у самого края экрана, на уровне Dock: в углу рядом с ним обычно пусто.
    private func defaultOrigin(on screen: NSScreen) -> NSPoint {
        let display = model.config.display
        let size = PillView.size(diameter: display.mascotSize)
        let visible = screen.visibleFrame
        let margin = 12.0
        let x = display.anchor.isRight ? visible.maxX - size.width - margin : visible.minX + margin
        let y = display.anchor.isTop ? visible.maxY - size.height - margin : screen.frame.minY + 4
        return NSPoint(x: x, y: y)
    }

    /// Дом — угол по умолчанию плюс сдвиг, куда маскота перетащили на этом мониторе.
    private func homeOrigin(on screen: NSScreen) -> NSPoint {
        let base = defaultOrigin(on: screen)
        guard let offset = model.config.display.offsets[Self.key(screen)], offset.count == 2 else { return base }
        return clamp(NSPoint(x: base.x + offset[0], y: base.y + offset[1]), on: screen)
    }

    private static func key(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        return String(number)
    }

    /// Центр маскота в экранных координатах — для взгляда за курсором и hover.
    private func updateCenter() {
        let display = model.config.display
        let box = MascotView.boxSize(display.mascotSize)
        let row = PillView.rowHeight(diameter: display.mascotSize)
        let centerX = display.anchor.isRight ? frame.maxX - box / 2 : frame.minX + box / 2
        // Ряд с маскотом — у края экрана, зеркало — над ним (или под ним, если маскот сверху).
        let centerY = display.anchor.isTop ? frame.maxY - row / 2 : frame.minY + row / 2
        model.animator.screenCenter = CGPoint(x: centerX, y: centerY)
    }

    /// Маскот не уходит за пределы экрана: держим в границах ряд с ним.
    private func clamp(_ origin: NSPoint, on screen: NSScreen) -> NSPoint {
        clamp(origin, in: screen.frame)
    }

    private func clamp(_ origin: NSPoint, in bounds: CGRect) -> NSPoint {
        let size = PillView.size(diameter: model.config.display.mascotSize)
        let row = PillView.rowHeight(diameter: model.config.display.mascotSize)
        let top = model.config.display.anchor.isTop
        let minY = top ? bounds.minY - (size.height - row) : bounds.minY
        let maxY = top ? bounds.maxY - size.height : bounds.maxY - row - (size.height - row)
        return NSPoint(
            x: min(max(origin.x, bounds.minX), bounds.maxX - size.width),
            y: min(max(origin.y, minY), max(minY, maxY))
        )
    }

    private func place(_ origin: NSPoint) {
        setFrameOrigin(origin)
        updateCenter()
    }

    private func animate(to origin: NSPoint, duration: TimeInterval, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrameOrigin(origin)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.updateCenter()
                completion?()
            }
        }
    }

    private func emit(_ kind: SignalKind, value: Double? = nil) {
        model.inbox.yield(.signal(Signal(.interaction, kind, value: value)))
    }

    // MARK: - Перетаскивание и бросок

    private var dragging = false
    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var samples: [(Date, NSPoint)] = []
    private var lastDragSignal = Date.distantPast
    private var motion: Timer?
    private var velocity = CGVector.zero

    func dragChanged() {
        let mouse = NSEvent.mouseLocation
        if !dragging {
            dragging = true
            cancelWandering()
            motion?.invalidate()
            motion = nil
            dragStartMouse = mouse
            dragStartOrigin = frame.origin
            samples.removeAll()
        }
        place(NSPoint(x: dragStartOrigin.x + mouse.x - dragStartMouse.x, y: dragStartOrigin.y + mouse.y - dragStartMouse.y))
        let now = Date()
        samples = samples.filter { now.timeIntervalSince($0.0) < 0.12 } + [(now, mouse)]
        // Глаза смотрят в сторону движения; быстро — «Уиии».
        let speed = currentVelocity()
        model.animator.dragLook = SIMD2(Double(max(-1, min(1, speed.dx / 600))), Double(max(-1, min(1, -speed.dy / 600))))
        if now.timeIntervalSince(lastDragSignal) > 0.3 {
            lastDragSignal = now
            emit(.dragged, value: hypot(speed.dx, speed.dy))
        }
    }

    func dragEnded() {
        guard dragging else { return }
        dragging = false
        model.animator.dragLook = nil
        let v = currentVelocity()
        if hypot(v.dx, v.dy) > 900 {
            fling(v)
        } else {
            velocity = .zero
            settle(thrown: false)
        }
    }

    private func currentVelocity() -> CGVector {
        guard let first = samples.first, let last = samples.last, last.0 > first.0 else { return .zero }
        let dt = last.0.timeIntervalSince(first.0)
        return CGVector(dx: (last.1.x - first.1.x) / dt, dy: (last.1.y - first.1.y) / dt)
    }

    /// Пол: нижний край экрана, на уровне Dock — туда падает маскот при включённой гравитации.
    private func floorY(_ bounds: CGRect) -> Double {
        let size = PillView.size(diameter: model.config.display.mascotSize)
        let row = PillView.rowHeight(diameter: model.config.display.mascotSize)
        return (model.config.display.anchor.isTop ? bounds.minY - (size.height - row) : bounds.minY) + 4
    }

    /// Падение на пол с затухающими отскоками, затем — обычное приземление.
    private func fall(thrown: Bool, bounds: CGRect) {
        let floor = floorY(bounds)
        guard model.config.display.gravity, frame.minY > floor + 1 else {
            finishSettle(thrown: thrown)
            return
        }
        var speed = velocity.dy
        var last = Date()
        let tuning = model.animator.tuning
        motion = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Date()
                let dt = min(1.0 / 30, now.timeIntervalSince(last))
                last = now
                speed -= tuning.gravity * dt
                var y = self.frame.minY + speed * dt
                if y <= floor {
                    y = floor
                    speed = -speed * tuning.floorBounce
                    if abs(speed) < 90 {
                        self.motion?.invalidate()
                        self.motion = nil
                        self.place(NSPoint(x: self.frame.minX, y: floor))
                        self.finishSettle(thrown: thrown)
                        return
                    }
                }
                self.place(NSPoint(x: self.frame.minX, y: y))
            }
        }
    }

    /// Гравитацию включили из меню — падает сразу.
    func gravityChanged() {
        guard model.config.display.gravity, !dragging, motion == nil, let screen = currentScreen ?? targetScreen() else { return }
        velocity = .zero
        fall(thrown: false, bounds: screen.frame)
    }

    /// Бросок: летит по инерции, отскакивает от краёв экрана, затем «Укачало».
    private func fling(_ start: CGVector) {
        guard let screen = currentScreen ?? targetScreen() else { return }
        let bounds = screen.frame
        velocity = start
        var last = Date()
        motion = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Date()
                let dt = min(1.0 / 30, now.timeIntervalSince(last))
                last = now
                let friction = pow(0.08, dt)
                self.velocity = CGVector(dx: self.velocity.dx * friction, dy: self.velocity.dy * friction)
                // С гравитацией полёт — дугой.
                if self.model.config.display.gravity { self.velocity.dy -= self.model.animator.tuning.gravity * dt }
                var origin = NSPoint(x: self.frame.minX + self.velocity.dx * dt, y: self.frame.minY + self.velocity.dy * dt)
                let clamped = self.clamp(origin, in: bounds)
                if clamped.x != origin.x { self.velocity.dx = -self.velocity.dx * 0.6 }
                if clamped.y != origin.y { self.velocity.dy = -self.velocity.dy * 0.6 }
                origin = clamped
                self.place(origin)
                if hypot(self.velocity.dx, self.velocity.dy) < 40 {
                    self.motion?.invalidate()
                    self.motion = nil
                    self.settle(thrown: true)
                }
            }
        }
    }

    /// Отпустили: с гравитацией — сначала падение на пол; потом новое место становится домом.
    private func settle(thrown: Bool) {
        guard let screen = currentScreen ?? targetScreen() else { return }
        place(clamp(frame.origin, on: screen))
        fall(thrown: thrown, bounds: screen.frame)
    }

    private func finishSettle(thrown: Bool) {
        guard let screen = currentScreen ?? targetScreen() else { return }
        let origin = clamp(frame.origin, on: screen)
        place(origin)
        let base = defaultOrigin(on: screen)
        model.config.display.offsets[Self.key(screen)] = [origin.x - base.x, origin.y - base.y]
        try? model.config.save()
        emit(thrown ? .thrown : .dropped)
    }

    /// Вернуть в угол по умолчанию (из меню).
    func resetPosition() {
        model.config.display.offsets.removeAll()
        try? model.config.save()
        returnHome(animated: true)
    }

    // MARK: - Прятки и лунатизм

    private enum Peek { case none, hidden, peeking }
    private var peek = Peek.none
    private var walking = false
    private var peekTimer: Timer?

    func perform(_ action: SpecialAction, line: String?) {
        guard !dragging, motion == nil, peek == .none, !walking, let screen = currentScreen ?? targetScreen() else { return }
        switch action {
        case .peekaboo: peekaboo(line: line, screen: screen)
        case .sleepwalk: sleepwalk(screen: screen)
        case .news: break // рассказывает модель, панель не двигается
        }
    }

    /// Прятки: уезжает за край экрана, через 10 s выглядывает одними глазами — «Ку-ку»; выходит при наведении.
    private func peekaboo(line: String?, screen: NSScreen) {
        let box = MascotView.boxSize(model.config.display.mascotSize)
        let outward = model.config.display.anchor.isRight ? 1.0 : -1.0
        let home = homeOrigin(on: screen)
        peek = .hidden
        animate(to: NSPoint(x: home.x + outward * box, y: home.y), duration: 0.6)
        peekTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.peek == .hidden else { return }
                self.peek = .peeking
                self.animate(to: NSPoint(x: home.x + outward * box * 0.45, y: home.y), duration: 0.5) {
                    if let line { self.model.say(line, duration: 2) }
                }
                // Выходит при наведении или сам через 20 s.
                self.peekTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if self.frame.insetBy(dx: -20, dy: -20).contains(NSEvent.mouseLocation) {
                            self.returnHome(animated: true)
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                    MainActor.assumeIsolated {
                        if self?.peek == .peeking { self?.returnHome(animated: true) }
                    }
                }
            }
        }
    }

    /// Лунатизм: ночью, пока тебя нет, медленно бредёт вдоль края экрана и возвращается к твоему приходу.
    private func sleepwalk(screen: NSScreen) {
        walking = true
        let home = homeOrigin(on: screen)
        let inward = model.config.display.anchor.isRight ? -1.0 : 1.0
        let distance = screen.frame.width * 0.35
        animate(to: clamp(NSPoint(x: home.x + inward * distance, y: home.y), on: screen), duration: 45)
    }

    private func cancelWandering() {
        peekTimer?.invalidate()
        peekTimer = nil
        peek = .none
        walking = false
    }

    func returnHomeIfWandering() {
        if walking || peek != .none { returnHome(animated: true) }
    }

    /// Домой — после пряток, лунатизма или сброса позиции.
    func returnHome(animated: Bool) {
        cancelWandering()
        guard let screen = currentScreen ?? targetScreen() else { return }
        let home = homeOrigin(on: screen)
        if animated { animate(to: home, duration: 0.6) } else { place(home) }
    }

    /// Dock занимает край видимой области своего дисплея. Скрытый Dock не найдём — тогда основной дисплей.
    static func dockScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            let frame = screen.frame, visible = screen.visibleFrame
            return visible.minY > frame.minY + 1 || visible.minX > frame.minX + 1 || visible.maxX < frame.maxX - 1
        }
    }

    private func targetScreen() -> NSScreen? {
        switch model.config.display.screen {
        case "dock":
            return Self.dockScreen() ?? NSScreen.screens.first
        case "main":
            return NSScreen.screens.first
        case "builtin":
            return NSScreen.screens.first { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                    .map { CGDisplayIsBuiltin($0) != 0 } ?? false
            } ?? NSScreen.screens.first
        default:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        }
    }
}

/// Клик по маскоту срабатывает с первого раза, без предварительной активации окна.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
