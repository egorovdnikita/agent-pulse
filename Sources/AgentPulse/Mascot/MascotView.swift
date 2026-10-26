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
    private let ovals = [CAShapeLayer(), CAShapeLayer()]
    private let lids = [CAShapeLayer(), CAShapeLayer()]
    private let arcs = [CAShapeLayer(), CAShapeLayer()]
    private let zees = [CATextLayer(), CATextLayer(), CATextLayer()]

    private var link: CADisplayLink?
    private var calmTimer: Timer?
    private var calm = false
    private var shadowKey: [Double] = []
    private var glowKey: [Double] = []
    private var bodyWarmth = -1.0

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
            ovals[index].fillColor = NSColor.black.cgColor
            for stroke in [lids[index], arcs[index]] {
                stroke.fillColor = nil
                stroke.strokeColor = NSColor.black.cgColor
                stroke.lineCap = .round
                stroke.lineJoin = .round
            }
            for layer in [ovals[index], lids[index], arcs[index]] { canvas.addSublayer(layer) }
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
            // Без таймера глубокий сон уже не проснётся сам — сбрасываем его; после паузы кадры решат заново.
            if calm {
                calm = false
                for layer in [glow, body] as [CALayer] + ovals + lids + zees { layer.removeAllAnimations() }
            }
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
        for layer in [glow, body] as [CALayer] + ovals + lids + zees { layer.removeAllAnimations() }
        canvas.removeAllAnimations()
        updateDriver()
    }

    private func installSleepAnimations() {
        let tuning = animator.tuning
        // Свечение дышит: темнее и меньше — светлее и больше.
        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = 0.85
        breath.toValue = 1
        let swell = CABasicAnimation(keyPath: "transform.scale")
        swell.fromValue = Self.glowPulseScale.lowerBound
        swell.toValue = Self.glowPulseScale.upperBound
        let pulse = CAAnimationGroup()
        pulse.animations = [breath, swell]
        pulse.duration = tuning.sleepGlowPeriod / 2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(pulse, forKey: "breath")

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
        Self.falloff(dropShadow, color: NSColor.black, peak: 0.22, inner: shadowInner / shadowRadius, cache: &shadowKey)

        // Свечение: широкое и размытое, пульсирует — темнее и меньше, светлее и больше; ночью теплеет.
        // Пульс — прозрачность и масштаб слоя: градиент пересчитывается, только когда меняется сама поза.
        let pulse = 0.5 + 0.5 * sin(2 * .pi * pose.time / Self.glowPulsePeriod)
        let swell = Self.glowPulseScale.lowerBound + (Self.glowPulseScale.upperBound - Self.glowPulseScale.lowerBound) * pulse
        let glowRadius = radius + pose.glowRadius * 2.1 * unit
        let tint = NSColor(red: 1, green: 1 - 0.05 * pose.glowWarmth, blue: 1 - 0.16 * pose.glowWarmth, alpha: 1)
        glow.bounds = CGRect(x: 0, y: 0, width: glowRadius * 2, height: glowRadius * 2)
        glow.position = center
        Self.falloff(glow, color: tint, peak: pose.glowOpacity, inner: radius * 0.7 / glowRadius, softness: 2.3, cache: &glowKey)
        if !calm {
            glow.opacity = Float(0.85 + 0.15 * pulse)
            glow.transform = CATransform3DMakeScale(swell, swell, 1)
        }

        // Тело светится само: центр чисто белый, к краю — лёгкая прохладная тень объёма; ночью тёплый белый.
        let bodyRect = CGRect(x: center.x - radius * scaleX, y: center.y - radius * scaleY, width: 2 * radius * scaleX, height: 2 * radius * scaleY)
        body.frame = bodyRect
        if bodyMask.frame.size != body.bounds.size {
            bodyMask.frame = body.bounds
            bodyMask.path = CGPath(ellipseIn: body.bounds, transform: nil)
        }
        let warm = pose.glowWarmth
        if (warm * 1000).rounded() != bodyWarmth {
            bodyWarmth = (warm * 1000).rounded()
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
        }

        let eyeWidth = 7.5 * unit * pose.bodyScale * scaleX
        let eyeHeight = 10.5 * unit * pose.bodyScale * scaleY
        let (tiltSin, tiltCos) = (sin(pose.tilt), cos(pose.tilt))
        let closed = min(max((0.35 - pose.eyeScale) / 0.25, 0), 1) * (1 - pose.happy)
        for (index, side) in [-1.0, 1.0].enumerated() {
            let spot = side * (7.5 + pose.eyeSpread) * (1 - 2 * pose.eyeSwap)
            let local = SIMD2((spot + pose.gaze.x * 6) * unit * scaleX, (-2 + pose.gaze.y * 4) * unit * scaleY)
            let rotated = SIMD2(local.x * tiltCos - local.y * tiltSin, local.x * tiltSin + local.y * tiltCos)
            // При взгляде вбок дальний глаз сужается — объём шара.
            let isFar = (side < 0 && pose.gaze.x > 0) || (side > 0 && pose.gaze.x < 0)
            let width = eyeWidth * (isFar ? 1 - 0.15 * min(1, abs(pose.gaze.x)) : 1)
            let height = eyeHeight * pose.eyeScale
            // Веко опускается сверху: прикрытый глаз оседает вниз.
            let eye = CGPoint(x: center.x + rotated.x, y: center.y + rotated.y + (eyeHeight - height) * 0.3)

            let ovalOpacity = (1 - pose.happy) * (1 - closed)
            ovals[index].opacity = Float(height > 0.3 ? ovalOpacity : 0)
            ovals[index].path = CGPath(ellipseIn: CGRect(x: eye.x - width / 2, y: eye.y - height / 2, width: width, height: max(height, 0.01)), transform: nil)

            // Закрытые глаза — веко «‿».
            let lid = CGMutablePath()
            lid.move(to: CGPoint(x: eye.x - eyeWidth * 0.65, y: eye.y))
            lid.addQuadCurve(to: CGPoint(x: eye.x + eyeWidth * 0.65, y: eye.y), control: CGPoint(x: eye.x, y: eye.y + eyeHeight * 0.4))
            lids[index].path = lid
            lids[index].lineWidth = 2 * unit
            lids[index].opacity = Float(closed)

            // Радость — дуга «^».
            let arc = CGMutablePath()
            arc.move(to: CGPoint(x: eye.x - eyeWidth * 0.68, y: eye.y + eyeHeight * 0.15))
            arc.addQuadCurve(to: CGPoint(x: eye.x + eyeWidth * 0.68, y: eye.y + eyeHeight * 0.15), control: CGPoint(x: eye.x, y: eye.y - eyeHeight * 0.6))
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

    /// Свечение пульсирует: период и размах размера.
    static let glowPulsePeriod = 3.4
    static let glowPulseScale: ClosedRange<Double> = 0.88...1.08

    /// Радиальный спад, близкий к гауссову: ровно до `inner`, дальше мягко тает — без видимого края.
    /// `cache` — последние входные данные: тот же градиент не пересобирается каждый кадр.
    private static func falloff(
        _ layer: CAGradientLayer, color: NSColor, peak: Double, inner: Double, softness: Double = 3.2, cache: inout [Double]
    ) {
        let key = ((color.cgColor.components ?? []).map { Double($0) } + [peak, inner, softness]).map { ($0 * 200).rounded() }
        guard key != cache else { return }
        cache = key
        let steps = [0.0, 0.1, 0.22, 0.36, 0.52, 0.7, 0.86, 1.0]
        let fade = steps.map { exp(-softness * $0 * $0) - exp(-softness) * $0 }
        layer.colors = [color.withAlphaComponent(peak).cgColor] + fade.map { color.withAlphaComponent(peak * max(0, $0)).cgColor }
        layer.locations = [0] + steps.map { NSNumber(value: inner + (1 - inner) * $0) }
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
    }

    private static func circle(_ center: CGPoint, _ radius: Double) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
