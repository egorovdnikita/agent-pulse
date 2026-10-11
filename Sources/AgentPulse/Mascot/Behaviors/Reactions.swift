import AgentPulseCore
import Foundation

struct ActiveReaction {
    let kind: MascotReaction
    let start: Double
    var fired: Set<Int> = []
}

/// One-shot реакции поверх кадра состояния.
enum ReactionPlayer {
    static func duration(_ kind: MascotReaction, tuning: MascotTuning) -> Double {
        switch kind {
        case .notice: tuning.noticeDuration
        case .step: tuning.stepDuration
        case .done: tuning.doneDuration
        case .error: tuning.errorDuration
        }
    }

    /// `progress` — 0…1.
    static func apply(_ reaction: inout ActiveReaction, progress: Double, tuning: MascotTuning, to frame: inout BehaviorFrame) {
        func blinkOnce(_ id: Int, at mark: Double, _ request: BlinkRequest) {
            guard progress >= mark, !reaction.fired.contains(id) else { return }
            reaction.fired.insert(id)
            frame.blink = request
        }

        switch reaction.kind {
        case .notice:
            // Глаза распахиваются, взгляд на пользователя, подпрыгивание, двойное моргание.
            frame.eyeScale = tuning.noticeEyeScale
            frame.gaze = .zero
            frame.restGaze = .zero
            frame.saccade = nil
            frame.bodyOffset.y = -tuning.hopHeight * sin(.pi * progress)
            blinkOnce(0, at: 0.45, .double)
        case .step:
            // Кивок: тело вниз и обратно, короткое моргание.
            frame.bodyOffset.y = 2 * sin(.pi * progress)
            frame.bodyScale = 1 - 0.03 * sin(.pi * progress)
            blinkOnce(0, at: 0.3, .single)
        case .done:
            // Дуги «^ ^», два подпрыгивания, вспышка свечения.
            frame.happy = 1
            frame.bodyOffset.y = -tuning.hopHeight * abs(sin(2 * .pi * progress))
            frame.glowOpacity = min(1, frame.glowOpacity + 0.4 * (1 - progress))
            frame.glowRadiusScale = 1 + 0.5 * (1 - progress)
        case .error:
            // Глаза сжимаются, тело трясётся по X три цикла, свечение гаснет до 40%.
            frame.eyeScale = tuning.errorEyeScale
            frame.bodyOffset.x = 2 * sin(2 * .pi * 3 * progress) * (1 - progress)
            frame.glowOpacity *= 0.4
        }
    }
}
