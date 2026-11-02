import AgentPulseCore
import AppKit
import Lottie
import QuartzCore

/// Облик Agent Pals: два слоя Lottie для кроссфейда. Клипы играют на движке Core Animation —
/// петли крутит рендер-сервер, CPU в покое не тратится. Тело (сдвиг, масштаб, сжатие, наклон)
/// по-прежнему задаёт процедурная поза — прыжки, тычки, бросок и поглаживание работают как раньше.
@MainActor
final class PalLayer: CALayer {
    /// Доля холста 200×200, которую занимает тело бота по ширине (замер Circle: 107 из 200).
    static let bodyShare = 0.535
    /// Центр тела в кадре ниже центра холста: 111.5 из 200 у всех 18 ботов (замер по Idle).
    /// Слой крутится и масштабируется вокруг центра тела, и тело встаёт ровно в центр маскота — на линию хвостика облачка.
    static let bodyCenterY = 111.5

    private var front: LottieAnimationLayer?
    private var back: LottieAnimationLayer?
    private(set) var skin: PalSkin?
    private(set) var clip: PalClip?
    private var cache: [PalClip: LottieAnimation] = [:]
    var frozen = false {
        didSet { if oldValue != frozen { syncPlayback() } }
    }
    var stopped = false {
        didSet { if oldValue != stopped { syncPlayback() } }
    }

    override init() {
        super.init()
        actions = ["position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "opacity": NSNull()]
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Переодевание: старый бот сжимается и тает, новый выпрыгивает с лёгким перелётом.
    static let morphOut = 0.16
    static let morphIn = 0.42
    private var popNext = false

    /// Сменить бота: клипы перечитываются. Был другой бот — переодевание, первый показ — сразу.
    func use(_ skin: PalSkin?) {
        guard skin != self.skin else { return }
        let dressed = self.skin != nil && skin != nil
        self.skin = skin
        cache.removeAll()
        clip = nil
        back?.removeFromSuperlayer()
        back = nil
        if let old = front {
            front = nil
            if dressed {
                leave(old)
            } else {
                old.removeFromSuperlayer()
            }
        }
        popNext = dressed
    }

    private func leave(_ old: LottieAnimationLayer) {
        old.zPosition = 0
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.55
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [shrink, fade]
        group.duration = Self.morphOut
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        CATransaction.begin()
        CATransaction.setCompletionBlock { old.removeFromSuperlayer() }
        old.opacity = 0
        old.add(group, forKey: "leave")
        CATransaction.commit()
    }

    private func pop(_ layer: LottieAnimationLayer) {
        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [0.55, 0.55, 1.1, 0.97, 1]
        grow.keyTimes = [0, 0.3, 0.65, 0.85, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0, 1, 1]
        fade.keyTimes = [0, 0.3, 0.5, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = Self.morphIn
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "pop")
    }

    /// Показать клип: новый слой проявляется поверх старого за `PalChoreographer.crossfade`.
    func show(_ next: PalClip, restart: Bool = false) {
        guard let skin, next != clip || restart, let animation = animation(next, skin: skin) else { return }
        let animate = clip != nil
        clip = next

        let incoming = back ?? makeLayer()
        incoming.animation = animation
        fit(incoming)
        incoming.zPosition = 1
        front?.zPosition = 0
        if incoming.superlayer == nil { addSublayer(incoming) }
        let outgoing = front
        front = incoming
        back = outgoing
        syncPlayback()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        incoming.opacity = 1
        outgoing?.opacity = 0
        CATransaction.commit()
        if popNext {
            popNext = false
            pop(incoming)
            return
        }
        guard animate else { return }
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = PalChoreographer.crossfade
        incoming.add(fadeIn, forKey: "fade")
        if let outgoing {
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1
            fadeOut.toValue = 0
            fadeOut.duration = PalChoreographer.crossfade
            outgoing.add(fadeOut, forKey: "fade")
        }
    }

    /// Холст пака: у всех 234 клипов один кадр 200×200 и одна посадка бота.
    static let canvas = 200.0

    /// Клипы рисуются в родном размере холста; под маскота их масштабирует трансформ слоя.
    private func fit(_ layer: LottieAnimationLayer) {
        let rect = CGRect(x: 0, y: 0, width: Self.canvas, height: Self.canvas)
        if bounds != rect {
            bounds = rect
            anchorPoint = CGPoint(x: 0.5, y: Self.bodyCenterY / Self.canvas)
        }
        layer.frame = rect
        Self.center(layer)
    }

    /// `LottieAnimationLayer`, в отличие от `LottieAnimationView`, не раскладывает корень анимации:
    /// тот стоит центром в (0, 0), и бот уезжает влево-вверх на пол-холста. Ставим его по центру сами.
    private static func center(_ layer: LottieAnimationLayer) {
        guard let root = layer.animationLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        root.bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
        root.position = CGPoint(x: canvas / 2, y: canvas / 2)
        CATransaction.commit()
    }

    private func makeLayer() -> LottieAnimationLayer {
        let layer = LottieAnimationLayer(animation: nil, configuration: LottieConfiguration(renderingEngine: .coreAnimation))
        layer.loopMode = .loop
        layer.animationLayerDidLoad = { layer, _ in
            MainActor.assumeIsolated { PalLayer.center(layer) }
        }
        layer.contentsGravity = .resizeAspect
        layer.actions = ["opacity": NSNull(), "bounds": NSNull(), "position": NSNull()]
        return layer
    }

    /// Играет только передний слой; скрытая панель или Reduce Motion — стоп-кадр.
    private func syncPlayback() {
        back?.pause()
        guard let front else { return }
        if stopped {
            front.pause()
        } else if frozen {
            front.pause()
            front.currentProgress = 0.3
        } else {
            front.play()
        }
    }

    private func animation(_ clip: PalClip, skin: PalSkin) -> LottieAnimation? {
        if let cached = cache[clip] { return cached }
        let loaded = LottieAnimation.filepath(skin.url(clip).path)
        cache[clip] = loaded
        return loaded
    }
}
