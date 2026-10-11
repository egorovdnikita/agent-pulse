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
        body.colors = [NSColor.white.cgColor, NSColor.white.cgColor, NSColor(white: 0.9, alpha: 1).cgColor]
        body.locations = [0, 0.45, 1]
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
        for layer in [glow, body] as [CALayer] + ovals + lids + zees { layer.removeAllAnimations() }
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

    private func apply(_ pose: MascotPose) {
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

        // Тень держит силуэт на светлом фоне; чуть ниже тела — свет сверху.
        let shadowRadius = radius + 8 * unit
        dropShadow.frame = Self.circle(CGPoint(x: base.x, y: base.y + 1.5 * unit), shadowRadius)
        dropShadow.colors = [NSColor.black.withAlphaComponent(0.25).cgColor, NSColor.black.withAlphaComponent(0.25).cgColor, NSColor.clear.cgColor]
        dropShadow.locations = [0, NSNumber(value: (radius - 4 * unit) / shadowRadius), 1]
        dropShadow.startPoint = CGPoint(x: 0.5, y: 0.5)
        dropShadow.endPoint = CGPoint(x: 1, y: 1)

        // Свечение; ночью теплеет.
        let glowRadius = radius + pose.glowRadius * unit
        let tint = NSColor(red: 1, green: 1 - 0.07 * pose.glowWarmth, blue: 1 - 0.2 * pose.glowWarmth, alpha: 1)
        glow.frame = Self.circle(center, glowRadius)
        glow.colors = [tint.withAlphaComponent(pose.glowOpacity).cgColor, tint.withAlphaComponent(pose.glowOpacity).cgColor, tint.withAlphaComponent(0).cgColor]
        glow.locations = [0, NSNumber(value: radius * 0.8 / glowRadius), 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        if !calm { glow.opacity = 1 }

        // Белое тело со светотенью: свет сверху слева.
        let bodyRect = CGRect(x: center.x - radius * scaleX, y: center.y - radius * scaleY, width: 2 * radius * scaleX, height: 2 * radius * scaleY)
        body.frame = bodyRect
        bodyMask.frame = body.bounds
        bodyMask.path = CGPath(ellipseIn: body.bounds, transform: nil)
        body.startPoint = CGPoint(x: 0.35, y: 0.32)
        body.endPoint = CGPoint(x: 0.35 + 0.675, y: 0.32 + 0.675)

        let eyeWidth = 7 * unit * pose.bodyScale * scaleX
        let eyeHeight = 10 * unit * pose.bodyScale * scaleY
        let (tiltSin, tiltCos) = (sin(pose.tilt), cos(pose.tilt))
        let closed = min(max((0.35 - pose.eyeScale) / 0.25, 0), 1) * (1 - pose.happy)
        for (index, side) in [-1.0, 1.0].enumerated() {
            let spot = side * (8 + pose.eyeSpread) * (1 - 2 * pose.eyeSwap)
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
            lids[index].lineWidth = 1.8 * unit
            lids[index].opacity = Float(closed)

            // Радость — дуга «^».
            let arc = CGMutablePath()
            arc.move(to: CGPoint(x: eye.x - eyeWidth * 0.6, y: eye.y + eyeHeight * 0.15))
            arc.addQuadCurve(to: CGPoint(x: eye.x + eyeWidth * 0.6, y: eye.y + eyeHeight * 0.15), control: CGPoint(x: eye.x, y: eye.y - eyeHeight * 0.55))
            arcs[index].path = arc
            arcs[index].lineWidth = 2.2 * unit
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

    private static func circle(_ center: CGPoint, _ radius: Double) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
