import AppKit
import QuartzCore
import SwiftUI

/// Процедурный маскот: круглое тело с белым свечением и два чёрных овала-глаза. Больше ничего.
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

/// Слои: тень, свечение, тело (градиент под маской), по три слоя на глаз (овал, веко, дуга), три «z».
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
    private let glow = CAGradientLayer()
    private let body = CAGradientLayer()
    private let bodyMask = CAShapeLayer()
    // Глаз: чёрный овал и белый зрачок внутри него — больше ничего.
    private let eyeOvals = [CAShapeLayer(), CAShapeLayer()]
    private let pupilClips = [CALayer(), CALayer()]
    private let pupilMasks = [CAShapeLayer(), CAShapeLayer()]
    private let pupils = [CAShapeLayer(), CAShapeLayer()]
    private let lids = [CAShapeLayer(), CAShapeLayer()]
    private let arcs = [CAShapeLayer(), CAShapeLayer()]
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
        glow.type = .radial
        body.type = .radial
        body.mask = bodyMask
        for layer in [dropShadow, glow, body] as [CALayer] { canvas.addSublayer(layer) }
        for index in 0..<2 {
            eyeOvals[index].fillColor = NSColor.black.cgColor
            pupils[index].fillColor = NSColor.white.cgColor
            pupilClips[index].mask = pupilMasks[index]
            pupilClips[index].addSublayer(pupils[index])
            for stroke in [lids[index], arcs[index]] {
                stroke.fillColor = nil
                stroke.strokeColor = NSColor.black.cgColor
                stroke.lineCap = .round
                stroke.lineJoin = .round
            }
            for layer in [eyeOvals[index], pupilClips[index], lids[index], arcs[index]] { canvas.addSublayer(layer) }
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
        for mask in pupilMasks { mask.actions = none }
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
                guard let self, !self.animator.isCalm(at: Date.timeIntervalSinceReferenceDate) else { return }
                self.exitCalm()
            }
        }
    }

    private func exitCalm() {
        calm = false
        calmTimer?.invalidate()
        calmTimer = nil
        for layer in [glow, body] as [CALayer] + eyeOvals + pupilClips + lids + zees { layer.removeAllAnimations() }
        canvas.removeAllAnimations()
        updateDriver()
    }

    private func installSleepAnimations() {
        let tuning = animator.tuning
        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = tuning.sleepGlow.lowerBound / max(0.01, tuning.sleepGlow.upperBound)
        breath.toValue = 1
        breath.duration = tuning.sleepGlowPeriod / 2
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(breath, forKey: "breath")

        guard !animator.reduceMotion else { return }
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

        // Тень держит силуэт на светлом фоне: мягкая, чуть ниже тела — свет сверху. Спад гауссов, без «кольца».
        let shadowInner = radius - 3 * unit
        let shadowRadius = radius + 9 * unit
        dropShadow.frame = Self.circle(CGPoint(x: base.x, y: base.y + 2 * unit), shadowRadius)
        Self.falloff(dropShadow, color: NSColor.black, peak: 0.22, inner: shadowInner / shadowRadius)

        // Свечение: плотное у края тела, тает плавно; ночью теплеет.
        let glowRadius = radius + pose.glowRadius * 1.3 * unit
        let tint = NSColor(red: 1, green: 1 - 0.05 * pose.glowWarmth, blue: 1 - 0.16 * pose.glowWarmth, alpha: 1)
        glow.frame = Self.circle(center, glowRadius)
        Self.falloff(glow, color: tint, peak: pose.glowOpacity, inner: radius * 0.9 / glowRadius)
        if !calm { glow.opacity = 1 }

        // Тело светится само: центр чисто белый, к краю — лёгкая прохладная тень объёма; ночью тёплый белый.
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

        let eye = Eye.self
        let eyeWidth = eye.width * unit * pose.bodyScale * scaleX
        let eyeHeight = eye.height * unit * pose.bodyScale * scaleY
        let (tiltSin, tiltCos) = (sin(pose.tilt), cos(pose.tilt))
        let closed = min(max((0.35 - pose.eyeScale) / 0.25, 0), 1) * (1 - pose.happy)
        for (index, side) in [-1.0, 1.0].enumerated() {
            let spot = side * (eye.spacing + pose.eyeSpread) * (1 - 2 * pose.eyeSwap)
            // Взгляд: глаз чуть сдвигается по телу, зрачок — внутри белка; вместе — как прежний сдвиг.
            let local = SIMD2((spot + pose.gaze.x * eye.shift.x) * unit * scaleX, (eye.lift + pose.gaze.y * eye.shift.y) * unit * scaleY)
            let rotated = SIMD2(local.x * tiltCos - local.y * tiltSin, local.x * tiltSin + local.y * tiltCos)
            // При взгляде вбок дальний глаз сужается — объём шара.
            let isFar = (side < 0 && pose.gaze.x > 0) || (side > 0 && pose.gaze.x < 0)
            let width = eyeWidth * (isFar ? 1 - 0.15 * min(1, abs(pose.gaze.x)) : 1)
            let height = eyeHeight * pose.eyeScale
            // Веко опускается сверху: прикрытый глаз оседает вниз.
            let at = CGPoint(x: center.x + rotated.x, y: center.y + rotated.y + (eyeHeight - height) * 0.3)
            let oval = CGRect(x: at.x - width / 2, y: at.y - height / 2, width: width, height: max(height, 0.01))
            let ovalPath = CGPath(ellipseIn: oval, transform: nil)

            let open = Float(height > 0.3 ? (1 - pose.happy) * (1 - closed) : 0)
            eyeOvals[index].path = ovalPath
            eyeOvals[index].opacity = open

            // Белый зрачок ходит внутри чёрного глаза и не выходит за него: маска — тот же овал.
            pupilClips[index].frame = canvas.bounds
            pupilClips[index].opacity = open
            pupilMasks[index].frame = canvas.bounds
            pupilMasks[index].path = ovalPath
            let pupilSize = CGSize(width: eye.pupil.width * unit * pose.bodyScale * scaleX, height: eye.pupil.height * unit * pose.bodyScale * scaleY)
            let pupilCenter = CGPoint(
                x: at.x + pose.gaze.x * eye.pupilTravel.x * unit * scaleX * (width / eyeWidth),
                y: at.y + pose.gaze.y * eye.pupilTravel.y * unit * scaleY + (eyeHeight - height) * 0.15
            )
            pupils[index].path = CGPath(
                ellipseIn: CGRect(x: pupilCenter.x - pupilSize.width / 2, y: pupilCenter.y - pupilSize.height / 2, width: pupilSize.width, height: pupilSize.height),
                transform: nil
            )

            let mark = SIMD2(eye.markWidth * unit * pose.bodyScale * scaleX, eye.markHeight * unit * pose.bodyScale * scaleY)
            // Закрытые глаза — веко «‿».
            let lid = CGMutablePath()
            lid.move(to: CGPoint(x: at.x - mark.x * 0.65, y: at.y))
            lid.addQuadCurve(to: CGPoint(x: at.x + mark.x * 0.65, y: at.y), control: CGPoint(x: at.x, y: at.y + mark.y * 0.4))
            lids[index].path = lid
            lids[index].lineWidth = 2 * unit
            lids[index].opacity = Float(closed)

            // Радость — дуга «^».
            let arc = CGMutablePath()
            arc.move(to: CGPoint(x: at.x - mark.x * 0.68, y: at.y + mark.y * 0.15))
            arc.addQuadCurve(to: CGPoint(x: at.x + mark.x * 0.68, y: at.y + mark.y * 0.15), control: CGPoint(x: at.x, y: at.y - mark.y * 0.6))
            arcs[index].path = arc
            arcs[index].lineWidth = 2.4 * unit
            arcs[index].opacity = Float(pose.happy)
        }

        if !calm { applyZees(pose, center: center, radius: radius, unit: unit) }
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

    /// Геометрия глаза при диаметре 48 pt: чёрный овал и белый зрачок.
    enum Eye {
        static let width = 13.0
        static let height = 16.5
        /// Центры глаз — ±spacing по X, lift по Y.
        static let spacing = 9.0
        static let lift = -2.5
        /// Сдвиг всего глаза по телу при взгляде.
        static let shift = SIMD2(2.2, 1.5)
        static let pupil = CGSize(width: 5.6, height: 6.6)
        /// Ход зрачка внутри глаза.
        static let pupilTravel = SIMD2(2.8, 3.4)
        /// Дуги «^» и веко «‿».
        static let markWidth = 10.0
        static let markHeight = 12.0
    }

    private static func circle(_ center: CGPoint, _ radius: Double) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
