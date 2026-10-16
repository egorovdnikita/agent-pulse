import AppKit
import QuartzCore
import SwiftUI

/// Процедурный маскот: круглое белое тело и два пиксельных глаза, как на точечном экране. Больше ничего.
/// Рисуется слоями Core Animation: в активных состояниях поза применяется по display link (30 fps),
/// в глубоком сне кадры останавливаются, а дыхание и «Zzz» крутят повторяющиеся CA-анимации — ~0% CPU.
struct MascotView: NSViewRepresentable {
    let animator: MascotAnimator
    let diameter: Double
    /// Панель скрыта — ноль кадров, ноль CPU.
    var paused = false
    /// Сохранено для совместимости вызовов: частоту выбирает сам вид (сон — без кадров).
    var lowFrameRate = false

    /// Холст с запасом над головой — под «Zzz».
    static func boxSize(_ diameter: Double) -> Double {
        diameter * 2.2
    }

    func makeNSView(context: Context) -> MascotLayerView {
        MascotLayerView(animator: animator, diameter: diameter)
    }

    func updateNSView(_ view: MascotLayerView, context: Context) {
        view.diameter = diameter
        view.paused = paused
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MascotLayerView, context: Context) -> CGSize? {
        CGSize(width: Self.boxSize(diameter), height: Self.boxSize(diameter))
    }
}

/// Слои: тень, тело (градиент под маской), по слою на пиксельный глаз, три «z».
@MainActor
final class MascotLayerView: NSView {
    static let frameRate: Float = 30
    /// В покое — только редкие взгляды и моргание: хватает 20 кадров.
    static let idleFrameRate: Float = 20

    let animator: MascotAnimator
    var diameter: Double {
        didSet { if oldValue != diameter { needsLayout = true } }
    }
    var paused = false {
        didSet { if oldValue != paused { updateDriver() } }
    }

    private let canvas = CALayer()
    private let dropShadow = CAGradientLayer()
    private let body = CAGradientLayer()
    private let bodyMask = CAShapeLayer()
    private let eyes = [CAShapeLayer(), CAShapeLayer()]
    /// Смена выражения проявляется построчно сверху вниз — как перерисовка точечного экрана.
    private var eyeShape: PixelEyes.Shape?
    private var shapeChangedAt = -Double.infinity
    /// Лист поз: выражение рисуется сразу, без построчного проявления.
    var instantShapes = false
    private let zees = [CATextLayer(), CATextLayer(), CATextLayer()]

    private var link: CADisplayLink?
    private var calmTimer: Timer?
    private var calm = false

    init(animator: MascotAnimator, diameter: Double) {
        self.animator = animator
        self.diameter = diameter
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        canvas.isGeometryFlipped = true
        layer?.addSublayer(canvas)

        dropShadow.type = .radial
        body.type = .radial
        body.mask = bodyMask
        for layer in [dropShadow, body] as [CALayer] { canvas.addSublayer(layer) }
        for eye in eyes {
            eye.fillColor = NSColor(white: 0.06, alpha: 1).cgColor
            canvas.addSublayer(eye)
        }
        for zee in zees {
            zee.string = "z"
            zee.alignmentMode = .center
            zee.foregroundColor = NSColor.white.cgColor
            zee.font = NSFont.systemFont(ofSize: 12, weight: .heavy).fontDescriptor.withDesign(.rounded)
                .flatMap { NSFont(descriptor: $0, size: 12) } ?? NSFont.systemFont(ofSize: 12, weight: .heavy)
            zee.shadowColor = NSColor.black.cgColor
            zee.shadowOpacity = 0.45
            zee.shadowOffset = .zero
            zee.opacity = 0
            canvas.addSublayer(zee)
        }
        // Слои не анимируют изменения сами: позу задаём мы, кадр за кадром.
        disableImplicitAnimations(in: canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        canvas.frame = bounds
        for zee in zees { zee.contentsScale = window?.backingScaleFactor ?? 2 }
        apply(animator.pose(at: Date.timeIntervalSinceReferenceDate, cursor: NSEvent.mouseLocation))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDriver()
    }

    private func disableImplicitAnimations(in layer: CALayer) {
        let none: [String: CAAction] = [
            "position": NSNull(), "bounds": NSNull(), "path": NSNull(), "opacity": NSNull(), "colors": NSNull(),
            "locations": NSNull(), "startPoint": NSNull(), "endPoint": NSNull(), "fontSize": NSNull(),
            "lineWidth": NSNull(), "frame": NSNull(), "transform": NSNull(), "contents": NSNull(), "shadowRadius": NSNull(),
        ]
        layer.actions = none
        for sublayer in layer.sublayers ?? [] { disableImplicitAnimations(in: sublayer) }
        bodyMask.actions = none
    }

    // MARK: - Кадры

    private func updateDriver() {
        guard window != nil, !paused else {
            link?.invalidate()
            link = nil
            calmTimer?.invalidate()
            calmTimer = nil
            return
        }
        if !calm, link == nil {
            let link = displayLink(target: self, selector: #selector(step))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: Self.frameRate, preferred: Self.frameRate)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        let t = Date.timeIntervalSinceReferenceDate
        let rate = animator.state == .idle && !animator.hovered ? Self.idleFrameRate : Self.frameRate
        if link.preferredFrameRateRange.preferred != rate {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: rate, preferred: rate)
        }
        apply(animator.pose(at: t, cursor: NSEvent.mouseLocation))
        if animator.isCalm(at: t) { enterCalm() }
    }

    /// Глубокий сон: кадров нет, дыхание и «Zzz» — повторяющиеся анимации Core Animation.
    private func enterCalm() {
        guard !calm else { return }
        calm = true
        link?.invalidate()
        link = nil
        installSleepAnimations()
        calmTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = Date.timeIntervalSinceReferenceDate
                self.animator.ambientAct(at: t)
                guard !self.animator.isCalm(at: t) else { return }
                self.exitCalm()
            }
        }
    }

    private func exitCalm() {
        calm = false
        calmTimer?.invalidate()
        calmTimer = nil
        for layer in [body] as [CALayer] + eyes + zees { layer.removeAllAnimations() }
        canvas.removeAllAnimations()
        updateDriver()
    }

    private func installSleepAnimations() {
        let tuning = animator.tuning
        guard !animator.reduceMotion else { return }
        // Дыхание во сне: тело чуть поднимается и опускается, без кадров на CPU.
        let breath = CABasicAnimation(keyPath: "transform.translation.y")
        breath.fromValue = 0
        breath.toValue = -0.8 * diameter / 48
        breath.duration = tuning.sleepGlowPeriod / 2
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for layer in [body] as [CALayer] + eyes { layer.add(breath, forKey: "breath") }

        let unit = diameter / 48
        let radius = diameter / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let side = animator.zzzSide
        let period = 2.6
        let now = CACurrentMediaTime()
        for (index, zee) in zees.enumerated() {
            let start = CGPoint(x: center.x + side * (radius * 0.55 + 4 * unit), y: center.y - radius * 0.7)
            let end = CGPoint(x: start.x + side * 18 * unit, y: start.y - 24 * unit)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: start)
            move.toValue = NSValue(point: end)
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 1
            grow.toValue = 22.0 / 13.0
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.7, 1, 0.7, 0]
            fade.keyTimes = [0, 0.15, 0.5, 0.85, 1]
            let group = CAAnimationGroup()
            group.animations = [move, grow, fade]
            group.duration = period
            group.repeatCount = .infinity
            group.timeOffset = period * Double(index) / 3
            group.beginTime = now
            zee.fontSize = 13 * unit
            zee.bounds = CGRect(x: 0, y: 0, width: 20 * unit, height: 20 * unit)
            zee.shadowRadius = 2 * unit
            zee.add(group, forKey: "zzz")
        }
    }

    // MARK: - Поза → слои

    func apply(_ pose: MascotPose) {
        guard bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let unit = diameter / 48
        let base = CGPoint(x: bounds.midX + pose.bodyOffset.x * unit, y: bounds.midY + pose.bodyOffset.y * unit)
        let radius = diameter / 2 * pose.bodyScale
        // Растяжение и сжатие с сохранением объёма; нижний край тела остаётся на месте — тело «стоит».
        let scaleY = 1 + pose.squash
        let scaleX = 1 / scaleY.squareRoot()
        let center = CGPoint(x: base.x, y: base.y + radius * (1 - scaleY))

        // Тень держит силуэт на светлом фоне: узкая и мягкая, чуть ниже тела. Свечения нет.
        let shadowInner = radius - 2 * unit
        let shadowRadius = radius + 5 * unit
        dropShadow.frame = Self.circle(CGPoint(x: base.x, y: base.y + 1.5 * unit), shadowRadius)
        Self.falloff(dropShadow, color: NSColor.black, peak: 0.2, inner: shadowInner / shadowRadius)

        // Белое тело: центр чисто белый, к краю — лёгкая прохладная тень объёма; ночью тёплый белый.
        let bodyRect = CGRect(x: center.x - radius * scaleX, y: center.y - radius * scaleY, width: 2 * radius * scaleX, height: 2 * radius * scaleY)
        body.frame = bodyRect
        bodyMask.frame = body.bounds
        bodyMask.path = CGPath(ellipseIn: body.bounds, transform: nil)
        let warm = pose.glowWarmth
        func shade(_ white: Double, cool: Double) -> CGColor {
            NSColor(
                red: white - cool * 0.4 * (1 - warm),
                green: white - cool * 0.2 - 0.012 * warm,
                blue: white - 0.035 * warm,
                alpha: 1
            ).cgColor
        }
        body.colors = [shade(1, cool: 0), shade(0.995, cool: 0.005), shade(0.955, cool: 0.02), shade(0.9, cool: 0.04)]
        body.locations = [0, 0.4, 0.78, 1]
        body.startPoint = CGPoint(x: 0.4, y: 0.34)
        body.endPoint = CGPoint(x: 0.4 + 0.66, y: 0.34 + 0.66)

        applyEyes(pose, center: center, unit: unit, scaleX: scaleX, scaleY: scaleY)

        if !calm { applyZees(pose, center: center, radius: radius, unit: unit) }
    }

    /// Пиксельные глаза. Сетка привязана к центру тела, поэтому взгляд и веки движутся шагами в пиксель.
    private func applyEyes(_ pose: MascotPose, center: CGPoint, unit: Double, scaleX: Double, scaleY: Double) {
        let eye = Eye.self
        let pixel = eye.pixel * unit * pose.bodyScale
        let width = eye.width * unit * pose.bodyScale * scaleX
        let height = eye.height * unit * pose.bodyScale * scaleY
        let closed = min(max((0.35 - pose.eyeScale) / 0.25, 0), 1) * (1 - pose.happy)

        let shape: PixelEyes.Shape = if pose.glyph != .none {
            .glyph(pose.glyph)
        } else if pose.happy > 0.5 {
            .arc(width: width * 1.15)
        } else if closed > 0.5 {
            .lid(width: width * 1.15)
        } else {
            .oval(width: width, height: height * pose.eyeScale)
        }
        // Новое выражение (не моргание) — проявляется построчно за 0.12 s.
        let now = CACurrentMediaTime()
        if eyeShape != nil, !Self.sameKind(shape, eyeShape) { shapeChangedAt = now }
        eyeShape = shape
        let reveal = animator.reduceMotion || instantShapes ? 1 : min(1, (now - shapeChangedAt) / 0.12)

        let (tiltSin, tiltCos) = (sin(pose.tilt), cos(pose.tilt))
        for (index, side) in [-1.0, 1.0].enumerated() {
            let spot = side * (eye.spacing + pose.eyeSpread) * (1 - 2 * pose.eyeSwap)
            var local = SIMD2((spot + pose.gaze.x * eye.shift.x) * unit * scaleX, (eye.lift + pose.gaze.y * eye.shift.y) * unit * scaleY)
            local = SIMD2(local.x * tiltCos - local.y * tiltSin, local.x * tiltSin + local.y * tiltCos)
            // Прикрытый глаз оседает вниз — веко опускается сверху.
            if case .oval = shape { local.y += (height - height * pose.eyeScale) * 0.3 }
            // Положение глаза — в целых пикселях от центра тела.
            let origin = CGPoint(x: center.x + (local.x / pixel).rounded() * pixel, y: center.y + (local.y / pixel).rounded() * pixel)

            var cells = PixelEyes.cells(shape, mirrored: side < 0, pixel: pixel)
            // При взгляде вбок дальний глаз сужается на столбец — объём шара.
            let isFar = (side < 0 && pose.gaze.x > 0.5) || (side > 0 && pose.gaze.x < -0.5)
            if isFar, case .oval = shape, let edge = cells.map(\.0).max(by: { abs($0) < abs($1) }) {
                cells.removeAll { $0.0 == edge }
            }
            let rows = cells.map(\.1)
            let maxRow = rows.max().map { top in
                let bottom = rows.min() ?? top
                return bottom + Int((Double(top - bottom + 1) * reveal).rounded(.up)) - 1
            }
            eyes[index].path = PixelEyes.path(cells, origin: origin, pixel: pixel, gap: pixel * eye.gap, maxRow: maxRow)
        }
    }

    private static func sameKind(_ a: PixelEyes.Shape, _ b: PixelEyes.Shape?) -> Bool {
        switch (a, b) {
        case (.oval, .oval?), (.arc, .arc?), (.lid, .lid?): true
        case (.glyph(let x), .glyph(let y)?): x == y
        default: false
        }
    }

    /// Геометрия глаз при диаметре 48 pt.
    enum Eye {
        /// Размер пикселя.
        static let pixel = 1.65
        /// Зазор между пикселями, доля пикселя.
        static let gap = 0.14
        static let width = 10.2
        static let height = 13.6
        static let spacing = 9.0
        static let lift = -2.5
        /// Сдвиг глаз при взгляде.
        static let shift = SIMD2(5, 3.4)
    }

    /// Три «z» всплывают от макушки внутрь экрана, растут и тают по очереди.
    private func applyZees(_ pose: MascotPose, center: CGPoint, radius: Double, unit: Double) {
        let period = 2.6
        for (index, zee) in zees.enumerated() {
            guard pose.zzz > 0.01 else {
                zee.opacity = 0
                continue
            }
            let phase = (pose.time / period + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            zee.fontSize = (13 + 9 * phase) * unit
            zee.bounds = CGRect(x: 0, y: 0, width: 30 * unit, height: 30 * unit)
            zee.shadowRadius = 2 * unit
            zee.position = CGPoint(
                x: center.x + pose.zzzSide * (radius * 0.55 + 4 * unit + 18 * unit * phase),
                y: center.y - radius * 0.7 - 24 * unit * phase
            )
            zee.opacity = Float(pose.zzz * sin(.pi * phase))
            zee.transform = CATransform3DIdentity
        }
    }

    /// Радиальный спад, близкий к гауссову: ровно до `inner`, дальше мягко тает — без видимого края.
    private static func falloff(_ layer: CAGradientLayer, color: NSColor, peak: Double, inner: Double) {
        let steps = [0.0, 0.12, 0.28, 0.48, 0.7, 0.88, 1.0]
        let fade = steps.map { exp(-3.2 * $0 * $0) - exp(-3.2) * $0 }
        layer.colors = [color.withAlphaComponent(peak).cgColor] + fade.map { color.withAlphaComponent(peak * max(0, $0)).cgColor }
        layer.locations = [0] + steps.map { NSNumber(value: inner + (1 - inner) * $0) }
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
    }

    private static func circle(_ center: CGPoint, _ radius: Double) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
