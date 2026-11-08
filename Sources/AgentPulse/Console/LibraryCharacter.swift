import AgentPulseCore
import AppKit
import Lottie
import SwiftUI

/// Выбранный сейчас облик, но всегда вариант Working с орбитой, как в Figma.
struct LibraryCharacter: NSViewRepresentable {
    @Environment(\.promoCapture) private var promoCapture
    let skin: PalSkin?
    var paused = false

    func makeNSView(context: Context) -> LibraryCharacterView { LibraryCharacterView() }
    func updateNSView(_ view: LibraryCharacterView, context: Context) {
        view.isHidden = promoCapture != nil
        if promoCapture == nil { view.use(skin); view.paused = paused }
    }
    static func dismantleNSView(_ view: LibraryCharacterView, coordinator: ()) { view.stop() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LibraryCharacterView, context: Context) -> CGSize? {
        CGSize(width: 60, height: 60)
    }
}

@MainActor
final class LibraryCharacterView: NSView {
    private let canvas = CALayer()
    private let backCanvas = CALayer()
    private let backAnimation: LottieAnimationLayer
    private let animation: LottieAnimationLayer
    private let offline: Bool
    private var current: String?
    private var classic: MascotLayerView?
    var paused = false { didSet { if oldValue != paused { playback() } } }

    override convenience init(frame: NSRect) { self.init(frame: frame, offline: false) }

    init(frame: NSRect, offline: Bool) {
        self.offline = offline
        let config = LottieConfiguration(renderingEngine: offline ? .mainThread : .coreAnimation)
        backAnimation = LottieAnimationLayer(animation: nil, configuration: config)
        animation = LottieAnimationLayer(animation: nil, configuration: config)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        backCanvas.isGeometryFlipped = true
        canvas.isGeometryFlipped = true
        canvas.zPosition = 2
        layer?.addSublayer(backCanvas)
        layer?.addSublayer(canvas)
        backCanvas.addSublayer(backAnimation)
        canvas.addSublayer(animation)
        for animation in [backAnimation, animation] {
            animation.loopMode = .loop
            animation.animationLayerDidLoad = { layer, _ in
                MainActor.assumeIsolated {
                    guard let root = layer.animationLayer else { return }
                    root.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
                    root.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    root.position = CGPoint(x: 100, y: 100)
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func use(_ skin: PalSkin?) {
        let key = skin?.configValue ?? PalSkin.classic
        guard key != current else { return }
        current = key
        classic?.removeFromSuperview()
        classic = nil
        let source = skin ?? PalSkin(bot: PalSkin.defaultBot)
        animation.animation = LottieAnimation.filepath(source.url(.working).path)
        backAnimation.animation = nil
        animation.animationSpeed = (animation.animation?.duration ?? 2) / 2
        if skin == nil {
            animation.animation = nil
            // Орбита остаётся из исходного Working, тело — настоящий классический маскот.
            if let data = try? Data(contentsOf: source.url(.working)),
               var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let layers = json["layers"] as? [[String: Any]],
               let shape = layers.firstIndex(where: { $0["nm"] as? String == "Shape" }) {
                let rig = layers.filter { $0["nm"] as? String == "Rig" }
                json["layers"] = rig + Array(layers.suffix(from: shape + 1))
                if let bytes = try? JSONSerialization.data(withJSONObject: json) {
                    backAnimation.animation = try? LottieAnimation.from(data: bytes)
                    backAnimation.animationSpeed = (backAnimation.animation?.duration ?? 2) / 2
                }
                json["layers"] = Array(layers.prefix(while: { $0["nm"] as? String != "Face" }))
                if let bytes = try? JSONSerialization.data(withJSONObject: json) {
                    animation.animation = try? LottieAnimation.from(data: bytes)
                }
            }
            let animator = MascotAnimator()
            animator.setState(.idle, at: Date.timeIntervalSinceReferenceDate)
            let body = MascotLayerView(animator: animator, diameter: 60)
            addSubview(body, positioned: .below, relativeTo: nil)
            body.layer?.zPosition = 1
            classic = body
        }
        needsLayout = true
        playback()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.frame = bounds
        backCanvas.frame = bounds
        for animation in [backAnimation, animation] {
            animation.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
            animation.anchorPoint = CGPoint(x: 0.5, y: PalLayer.bodyCenterY / 200)
            animation.position = CGPoint(x: bounds.midX, y: bounds.midY)
            animation.setAffineTransform(CGAffineTransform(scaleX: 60 / (200 * PalLayer.bodyShare), y: 60 / (200 * PalLayer.bodyShare)))
            if let root = animation.animationLayer {
                root.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
                root.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                root.position = CGPoint(x: 100, y: 100)
            }
        }
        classic?.frame = CGRect(x: bounds.midX - 66, y: bounds.midY - 66, width: 132, height: 132)
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); playback() }
    func seekOffline(_ progress: Double) {
        for clip in [backAnimation, animation] {
            clip.pause()
            clip.currentProgress = progress
            clip.forceDisplayUpdate()
        }
    }

    func stop() { animation.pause(); backAnimation.pause(); classic?.paused = true }
    private func playback() {
        guard !offline, window != nil, !paused else { stop(); return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        classic?.paused = reduced
        for animation in [backAnimation, animation] {
            if reduced { animation.pause(); animation.currentProgress = 0 }
            else { animation.play() }
        }
    }
}
