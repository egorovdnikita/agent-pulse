import AgentPulseCore
import Foundation

/// Глаза закрыты тонкими линиями, свечение медленно дышит. Ничего не двигается.
struct SleepBehavior: MascotBehavior {
    let start: Double

    mutating func step(_ context: inout BehaviorContext) -> BehaviorFrame {
        let tuning = context.tuning
        let progress = min(1, max(0, (context.t - start) / tuning.fallAsleepDuration))
        let eased = progress * progress * (3 - 2 * progress)
        var frame = BehaviorFrame()
        frame.eyeScale = 1 + (tuning.sleepLid - 1) * eased
        let glow = tuning.sleepGlow
        frame.glowOpacity = glow.lowerBound + (glow.upperBound - glow.lowerBound)
            * (0.5 + 0.5 * sin(2 * .pi * context.t / tuning.sleepGlowPeriod))
        frame.motionless = true
        frame.sleepiness = eased
        return frame
    }
}

/// Открытые глаза, редкие ленивые взгляды.
struct IdleBehavior: MascotBehavior {
    var fixation: Fixation

    mutating func step(_ context: inout BehaviorContext) -> BehaviorFrame {
        var frame = BehaviorFrame()
        if fixation.isDue(context.t) {
            let point: SIMD2<Double> = context.chance(0.4)
                ? .zero
                : SIMD2(context.random(-0.6...0.6), context.random(-0.4...0.4))
            frame.saccade = fixation.move(to: point, until: context.t + context.random(context.tuning.idleFixation))
        }
        frame.gaze = fixation.target
        frame.blinkInterval = context.tuning.blinkInterval
        frame.glowOpacity = breathing(context.t, base: context.tuning.glowOpacity, amplitude: 0.05, period: 4)
        return frame
    }
}

/// Взгляд вверх-в сторону, смена стороны, лёгкий прищур, медленная пульсация.
struct ThinkBehavior: MascotBehavior {
    var fixation: Fixation
    var side: Double = 1

    mutating func step(_ context: inout BehaviorContext) -> BehaviorFrame {
        var frame = BehaviorFrame()
        if fixation.isDue(context.t) {
            side = -side
            let point = SIMD2(0.5 * side + context.random(-0.1...0.1), -0.7 + context.random(-0.08...0.08))
            frame.saccade = fixation.move(to: point, until: context.t + context.random(context.tuning.thinkFixation))
        }
        frame.gaze = fixation.target
        frame.restGaze = SIMD2(0.5, -0.7)
        frame.eyeScale = context.tuning.thinkSquint
        frame.blinkInterval = context.tuning.blinkInterval
        frame.glowOpacity = breathing(context.t, base: context.tuning.glowOpacity, amplitude: 0.1, period: 5)
        return frame
    }
}

/// Работа: паттерн взгляда зависит от модуса; тело и свечение общие.
struct WorkBehavior: MascotBehavior {
    let mode: WorkMode
    var fixation: Fixation
    // read: построчное чтение
    var lineStart: Double?
    var lineY = -0.5
    // run: слежение за невидимой точкой
    var angle = 0.0
    var lastT: Double?
    var nextJump: Double?
    // search
    var side = 1.0

    init(mode: WorkMode, fixation: Fixation) {
        self.mode = mode
        self.fixation = fixation
    }

    mutating func step(_ context: inout BehaviorContext) -> BehaviorFrame {
        let tuning = context.tuning
        let t = context.t
        var frame = BehaviorFrame()
        frame.blinkInterval = tuning.workBlinkInterval
        frame.glowOpacity = breathing(t, base: tuning.glowOpacity, amplitude: 0.08, period: 2.5)

        switch mode {
        case .general:
            if fixation.isDue(t) {
                let point = SIMD2(context.random(-0.8...0.8), context.random(-0.6...0.6))
                frame.saccade = fixation.move(to: point, until: t + context.random(tuning.workFixation))
            }
            frame.gaze = fixation.target

        case .read:
            // Медленный проход слева направо, быстрый возврат, строка ниже.
            let start = lineStart ?? t
            var progress = (t - start) / tuning.readLineDuration
            lineStart = start
            if progress >= 1 {
                lineStart = t
                lineY = lineY >= 0.4 ? -0.5 : lineY + 0.3
                progress = 0
                frame.saccade = 1.4
            }
            frame.gaze = SIMD2(-0.7 + 1.4 * progress, lineY)
            frame.restGaze = SIMD2(0, 0.2)

        case .edit:
            // Взгляд вниз, короткие сдвиги, прищур, моргает реже — сосредоточен.
            if fixation.isDue(t) {
                let point = SIMD2(context.random(-0.35...0.35), 0.6)
                frame.saccade = fixation.move(to: point, until: t + context.random(tuning.editFixation))
            }
            frame.gaze = fixation.target
            frame.restGaze = SIMD2(0, 0.6)
            frame.eyeScale = tuning.editSquint
            frame.blinkInterval = tuning.editBlinkInterval

        case .run:
            // Плавное ведение по дуге, иногда резкий переброс.
            let dt = lastT.map { min(max(t - $0, 0), 0.1) } ?? 0
            lastT = t
            angle += dt * tuning.runAngularSpeed
            if let jumpAt = nextJump {
                if t >= jumpAt {
                    angle += .pi * context.random(0.6...1.0)
                    frame.saccade = 1
                    nextJump = t + context.random(2...4)
                }
            } else {
                nextJump = t + context.random(2...4)
            }
            frame.gaze = SIMD2(0.7 * cos(angle), 0.35 * sin(angle) - 0.1)
            frame.restGaze = SIMD2(0.4, 0)

        case .search:
            // Далеко в стороны, долгие фиксации, глаза чуть шире — высматривает.
            if fixation.isDue(t) {
                side = -side
                let point = SIMD2(0.9 * side, context.random(-0.2...0.1))
                frame.saccade = fixation.move(to: point, until: t + context.random(tuning.searchFixation))
            }
            frame.gaze = fixation.target
            frame.restGaze = SIMD2(0.9, 0)
            frame.eyeScale = tuning.searchEyeScale
        }
        return frame
    }
}

/// Смотрит прямо на пользователя. Каждые 3 s: подпрыгивание, двойное моргание, вспышка. Не затухает.
struct WaitBehavior: MascotBehavior {
    let start: Double
    var lastCycle = -1

    mutating func step(_ context: inout BehaviorContext) -> BehaviorFrame {
        let tuning = context.tuning
        let elapsed = context.t - start
        let cycle = Int(elapsed / tuning.waitPeriod)
        let phase = elapsed - Double(cycle) * tuning.waitPeriod

        var frame = BehaviorFrame()
        frame.gaze = .zero
        frame.eyeScale = tuning.waitEyeScale
        frame.blinkInterval = tuning.blinkInterval
        frame.glowOpacity = tuning.glowOpacity
        if cycle != lastCycle {
            lastCycle = cycle
            frame.blink = .double
        }
        let crouch = 0.12
        let pulse = 0.45
        if phase < crouch {
            // Присел перед прыжком.
            frame.bodyOffset.y = tuning.anticipation * sin(.pi * phase / crouch)
        } else if phase < crouch + pulse {
            let progress = (phase - crouch) / pulse
            frame.bodyOffset.y = -tuning.hopHeight * sin(.pi * progress)
            frame.glowOpacity = min(1, tuning.glowOpacity + 0.4 * (1 - progress))
            frame.glowRadiusScale = 1 + 0.4 * (1 - progress)
        }
        return frame
    }
}
