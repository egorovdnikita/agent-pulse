import AgentPulseCore
import Foundation

struct ActiveReaction {
    let kind: MascotReaction
    let start: Double
    var fired: Set<Int> = []
}

/// One-shot реакции поверх кадра состояния. Только пять параметров тела: взгляд, форма глаз, тело, наклон, свечение.
enum ReactionPlayer {
    static func duration(_ kind: MascotReaction, tuning: MascotTuning) -> Double {
        switch kind {
        case .notice: tuning.noticeDuration
        case .step: tuning.stepDuration
        case .done: tuning.doneDuration
        case .error: tuning.errorDuration
        default: tuning.reactionDurations[kind.rawValue] ?? 1.5
        }
    }

    /// Плавное появление и уход: 0 на краях, 1 в середине.
    private static func envelope(_ p: Double, attack: Double = 0.15, release: Double = 0.2) -> Double {
        min(1, p / attack, (1 - p) / release)
    }

    /// `progress` — 0…1, `elapsed` — секунды от начала.
    static func apply(_ reaction: inout ActiveReaction, progress p: Double, elapsed: Double, side: Double, tuning: MascotTuning, to frame: inout BehaviorFrame) {
        func blinkOnce(_ id: Int, at mark: Double, _ request: BlinkRequest) {
            guard p >= mark, !reaction.fired.contains(id) else { return }
            reaction.fired.insert(id)
            frame.blink = request
        }
        let e = envelope(p)

        switch reaction.kind {
        case .notice:
            // Глаза распахиваются, взгляд на пользователя; присел — и подпрыгнул; двойное моргание.
            frame.eyeScale = tuning.noticeEyeScale
            frame.gaze = .zero
            frame.restGaze = .zero
            frame.saccade = nil
            frame.bodyOffset.y = p < 0.2
                ? tuning.anticipation * sin(.pi * p / 0.2)
                : -tuning.hopHeight * sin(.pi * (p - 0.2) / 0.8)
            blinkOnce(0, at: 0.45, .double)
        case .step:
            // Кивок: тело вниз и обратно, короткое моргание.
            frame.bodyOffset.y = 2 * sin(.pi * p)
            frame.bodyScale = 1 - 0.03 * sin(.pi * p)
            blinkOnce(0, at: 0.3, .single)
        case .done:
            // Дуги «^ ^», два подпрыгивания, вспышка свечения.
            frame.happy = 1
            frame.bodyOffset.y = -tuning.hopHeight * abs(sin(2 * .pi * p))
            frame.glowOpacity = min(1, frame.glowOpacity + 0.4 * (1 - p))
            frame.glowRadiusScale = 1 + 0.5 * (1 - p)
        case .error:
            // Глаза сжимаются, тело трясётся по X три цикла, свечение гаснет до 40%.
            frame.eyeScale = tuning.errorEyeScale
            frame.bodyOffset.x = 2 * sin(2 * .pi * 3 * p) * (1 - p)
            frame.glowOpacity *= 0.4

        case .startle:
            frame.bodyScale = 1 - 0.07 * sin(.pi * p)
            frame.eyeScale = 1.2
            frame.gaze = .zero
            blinkOnce(0, at: 0.6, .single)
        case .relax:
            // Вдох — и выдох: расширение, сжатие, глаза мягчеют.
            frame.bodyScale = 1 + 0.05 * sin(2 * .pi * p) * (1 - 0.4 * p)
            frame.eyeScale = p > 0.5 ? 0.75 : 1
            frame.bodyOffset.y = 0.8 * sin(2 * .pi * p)
        case .contentSquint:
            frame.eyeScale = 1 - 0.5 * e
            frame.gaze = SIMD2(0, -0.15)
            frame.glowOpacity = min(1, frame.glowOpacity + 0.2 * e)
        case .lookAround:
            let points: [Double] = [-0.9, 0.9, -0.6, 0]
            frame.gaze = SIMD2(points[min(points.count - 1, Int(p * Double(points.count)))], -0.1)
            frame.eyeScale = 1.08
        case .lookLeft, .lookRight:
            frame.gaze = SIMD2((reaction.kind == .lookLeft ? -0.95 : 0.95) * e, -0.05)
            frame.eyeScale = p < 0.3 ? 1.15 : 1
        case .stretch:
            // Потягивается: зажмурился и вытянулся, потом сонно открывает глаза.
            frame.bodyScale = 1 + 0.06 * sin(.pi * p)
            frame.bodyOffset.y = -2 * sin(.pi * p)
            frame.eyeScale = p < 0.7 ? 0.08 : 0.08 + (p - 0.7) / 0.3 * 0.8
            frame.blinkInterval = nil
        case .slowClose:
            frame.eyeScale = p < 0.6 ? 1 - 0.92 * (p / 0.6) : (p < 0.85 ? 0.08 : 0.08 + (p - 0.85) / 0.15 * 0.92)
            frame.gaze = SIMD2(0, 0.3)
            frame.blinkInterval = nil
        case .puff:
            frame.bodyScale = 1 + 0.08 * envelope(p, attack: 0.2, release: 0.25)
            frame.eyeScale = 1.1
        case .wideEyes:
            frame.eyeScale = 1 + 0.2 * e
            frame.gaze = .zero
        case .squint:
            frame.eyeScale = 1 - 0.45 * e
        case .fastBlink:
            blinkOnce(0, at: 0.05, .single)
            blinkOnce(1, at: 0.35, .single)
            blinkOnce(2, at: 0.65, .single)
        case .wobble:
            frame.tilt = 0.12 * sin(2 * .pi * 2 * p) * e
            frame.bodyOffset.x = 1.5 * sin(2 * .pi * 2 * p) * e
        case .yawn:
            if p < 0.15 {
                frame.eyeScale = 1 - 0.7 * p / 0.15
            } else if p < 0.6 {
                frame.eyeScale = 0.08
                frame.bodyScale = 1 + 0.06 * sin(.pi * (p - 0.15) / 0.45)
                frame.bodyOffset.y = -1.5 * sin(.pi * (p - 0.15) / 0.45)
            } else {
                frame.eyeScale = 0.08 + 0.8 * (p - 0.6) / 0.4
            }
            frame.blinkInterval = nil
        case .purr:
            frame.happy = e
            frame.glowOpacity = min(1, frame.glowOpacity + 0.3 * e)
            frame.bodyScale = 1 + 0.02 * e
            frame.tilt = 0.06 * sin(2 * .pi * p)
        case .flinch:
            frame.bodyScale = 1 - 0.08 * sin(.pi * p)
            frame.eyeScale = p < 0.5 ? 0.35 : 1.1
            frame.bodyOffset.x = -side * 1.5 * sin(.pi * p)
        case .turnAway, .turnAwayLong:
            frame.gaze = SIMD2(-side * 0.95 * e, -0.05)
            frame.restGaze = frame.gaze
            frame.eyeScale = 0.9
            frame.tilt = -side * 0.08 * e
        case .dizzy:
            let decay = 1 - p * 0.6
            frame.gaze = SIMD2(cos(2 * .pi * 3 * p) * 0.75 * decay, sin(2 * .pi * 3 * p) * 0.55 * decay)
            frame.tilt = 0.1 * sin(2 * .pi * 2 * p) * decay
            frame.blinkInterval = nil
        case .lookDown:
            frame.gaze = SIMD2(0, 0.85 * e)
            frame.eyeScale = 0.85
        case .sideEye:
            frame.gaze = SIMD2(-side * 0.9 * e, 0)
            frame.eyeScale = 1 - 0.3 * e
        case .eyeSwap:
            frame.eyeSwap = 0.5 - 0.5 * cos(2 * .pi * p)
            frame.blinkInterval = nil

        case .sneeze:
            if p < 0.45 {
                frame.eyeScale = 0.08
                frame.bodyScale = 1 - 0.06 * p / 0.45
            } else if p < 0.58 {
                frame.eyeScale = 0.08
                frame.bodyScale = 1.08
                frame.bodyOffset.y = -2
            } else {
                frame.eyeScale = 0.08 + 0.92 * (p - 0.58) / 0.42
            }
            frame.blinkInterval = nil
        case .hiccup:
            // Три «ик» с интервалом ~2 s: глаза подпрыгивают.
            let since = elapsed.truncatingRemainder(dividingBy: 2)
            if since < 0.18 {
                frame.gaze.y -= 0.6 * sin(.pi * since / 0.18)
                frame.bodyOffset.y = -1.5 * sin(.pi * since / 0.18)
                frame.eyeScale = 1.15
            }
        case .fly:
            // Следит за невидимой мухой, моргает ей вслед.
            frame.gaze = SIMD2(0.8 * sin(2 * .pi * 0.9 * elapsed), 0.5 * sin(2 * .pi * 1.3 * elapsed + 1) - 0.2)
            frame.eyeScale = 1.05
            blinkOnce(0, at: 0.92, .single)
        case .nap:
            if p < 0.12 {
                frame.eyeScale = 1 - 0.92 * p / 0.12
            } else if p < 0.82 {
                frame.eyeScale = 0.08
            } else {
                frame.eyeScale = 1.15
                blinkOnce(0, at: 0.82, .double)
            }
            frame.blinkInterval = nil
        case .hop:
            // Присел — подскок — приземлился (сплющивание добавит физика тела).
            frame.bodyOffset.y = p < 0.25
                ? tuning.anticipation * 0.8 * sin(.pi * p / 0.25)
                : -tuning.hopHeight * 0.8 * sin(.pi * (p - 0.25) / 0.75)
        case .doze:
            // Клюёт носом: веки слипаются, тело оседает — и вздрагивает, просыпаясь.
            if p < 0.7 {
                frame.eyeScale = 1 - 0.75 * (p / 0.7)
                frame.bodyOffset.y = 1.5 * (p / 0.7)
                frame.gaze = SIMD2(0, 0.4 * p / 0.7)
            } else {
                frame.eyeScale = 1.15
                frame.bodyScale = 1 - 0.05 * sin(.pi * (p - 0.7) / 0.3)
                blinkOnce(0, at: 0.72, .double)
            }
            frame.blinkInterval = nil
        case .stare:
            // Засмотрелся в одну точку — и вздрогнул, будто вспомнил что-то.
            if p < 0.85 {
                frame.gaze = SIMD2(0.45, -0.25)
                frame.blinkInterval = nil
                frame.saccade = nil
            } else {
                frame.bodyScale = 1 - 0.06 * sin(.pi * (p - 0.85) / 0.15)
                frame.eyeScale = 1.2
                blinkOnce(0, at: 0.86, .single)
            }
        }
    }
}
