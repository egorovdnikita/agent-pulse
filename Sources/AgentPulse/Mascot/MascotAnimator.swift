import AgentPulseCore
import AppKit

/// Сводит поведение состояния, реакции, моргание, hover и Reduce Motion в одну позу на кадр.
@MainActor
final class MascotAnimator {
    var tuning = MascotTuning()
    /// Настроение и самочувствие ноутбука окрашивают движение.
    var baseline = Baseline()
    /// Эксперимент: угол крышки сдвигает взгляд по вертикали.
    var lidGaze = 0.0
    /// Пока маскота тащат — глаза смотрят в сторону движения.
    var dragLook: SIMD2<Double>?
    /// Агент закончил, пока тебя не было: спит довольным — глаза «^ ^».
    var contented = false

    // Взгляд на курсор издалека.
    private var nextFarGlance: Double?
    private var farLookUntil = 0.0
    private var farLook = SIMD2<Double>.zero
    private var lastCursor: CGPoint?
    private var cursorMovedAt = 0.0
    // Довольный изредка подпрыгивает на месте.
    private var nextBounce: Double?
    // Мелкие живые движения в покое и во сне.
    private var nextAct: Double?
    var reduceMotion = false
    /// Центр маскота в экранных координатах — для слежения за курсором.
    var screenCenter: CGPoint?
    /// Курсор над маскотом: во сне он плавно просыпается и смотрит на курсор.
    var hovered = false
    /// Куда всплывают «Zzz» — от края экрана внутрь.
    var zzzSide = -1.0

    private(set) var state: MascotState = .sleep
    private var behavior: any MascotBehavior = SleepBehavior(start: 0)
    private var queue: [MascotReaction] = []
    private var active: ActiveReaction?
    private var stateStart = 0.0
    private var blink = BlinkEngine()
    private var rng = SystemRandomNumberGenerator()
    private var lastT: Double?

    private var happyUntil = 0.0
    private var lookDownUntil = 0.0
    private var glanceUntil = 0.0
    private var glanceX = 0.0

    private var gaze = Spring2()
    private var eyeScale = Spring(1)
    private var happy = Spring(0)
    private var body = Spring2()
    private var bodyScale = Spring(1)
    private var glowOpacity = Spring(0.5)
    private var glowRadius = Spring(1)
    private var wake = Spring(0)
    private var zzz = Spring(0)
    private var impact = Spring(0)
    private var tilt = Spring(0)
    private var lastVelocityY = 0.0
    private var swap = Spring(0)

    /// Медленнее движется — дольше смотрит в одну точку.
    private var effectiveTuning: MascotTuning {
        guard baseline.motionSpeed != 1 else { return tuning }
        var scaled = tuning
        let slow = 1 / baseline.motionSpeed
        func stretch(_ range: ClosedRange<Double>) -> ClosedRange<Double> { (range.lowerBound * slow)...(range.upperBound * slow) }
        scaled.idleFixation = stretch(tuning.idleFixation)
        scaled.thinkFixation = stretch(tuning.thinkFixation)
        scaled.workFixation = stretch(tuning.workFixation)
        scaled.readLineDuration *= slow
        return scaled
    }

    func setState(_ newState: MascotState, at t: Double) {
        state = newState
        stateStart = t
        nextAct = nil
        behavior = BehaviorFactory.make(newState, at: t, gaze: gaze.value, tuning: tuning)
        if newState.isWaiting {
            // wait_you прерывает всё.
            queue.removeAll()
            active = nil
            happyUntil = 0
            lookDownUntil = 0
        }
    }

    /// Реакции не прерывают друг друга, а встают в очередь.
    func enqueue(_ reaction: MascotReaction) {
        guard !state.isWaiting else { return }
        queue.append(reaction)
        if queue.count > 4 { queue.removeFirst() }
    }

    /// Глубокий сон: ничего процедурного не происходит — можно остановить кадры и отдать дыхание и «Zzz»
    /// повторяющимся анимациям Core Animation. Будит наведение, событие, реакция, перетаскивание.
    func isCalm(at t: Double) -> Bool {
        state == .sleep && !hovered && active == nil && queue.isEmpty && dragLook == nil
            && wake.value < 0.01 && t - stateStart > tuning.fallAsleepDuration + 1.5
            // Поза устоялась: веки и «^ ^» дошли до конца — иначе застынет полузакрытой.
            && abs(happy.value - (contented ? 1 : 0)) < 0.02
            && abs(eyeScale.value - tuning.sleepLid) < 0.02 && abs(eyeScale.velocity) < 0.05
    }

    /// Маскот не застывает: в покое раз в 8–22 s присматривается, косится, подпрыгивает;
    /// во сне раз в 25–70 s улыбается во сне, приоткрывает глаза или ворочается. Без облачка и без бюджета.
    /// Вызывается и из кадра, и из таймера глубокого сна — тогда кадры на время движения возвращаются.
    func ambientAct(at t: Double) {
        guard !reduceMotion, active == nil, queue.isEmpty, !hovered, dragLook == nil else { return }
        let interval: ClosedRange<Double>
        let pool: [MascotReaction]
        switch state {
        case .idle:
            interval = tuning.idleActInterval
            pool = [.lookAround, .curious, .curious, .hop, .squint, .sideEye, .wideEyes, .fastBlink]
        case .sleep where t - stateStart > tuning.fallAsleepDuration + 3:
            interval = tuning.sleepActInterval
            pool = contented ? [.sleepRoll, .sleepPeek] : [.dreamSmile, .sleepPeek, .sleepRoll, .sleepRoll]
        default:
            nextAct = nil
            return
        }
        guard let due = nextAct else {
            nextAct = t + Double.random(in: interval, using: &rng)
            return
        }
        guard t >= due, let act = pool.randomElement(using: &rng) else { return }
        nextAct = t + Double.random(in: interval, using: &rng)
        queue.append(act)
    }

    func glance(towardX x: Double, at t: Double) {
        glanceX = x
        glanceUntil = t + tuning.bubbleGlance
    }

    func pose(at t: Double, cursor: CGPoint?) -> MascotPose {
        let dt = lastT.map { min(max(t - $0, 0), 0.1) } ?? 0
        lastT = t

        ambientAct(at: t)
        var context = BehaviorContext(t: t, tuning: effectiveTuning, rng: rng)
        var frame = behavior.step(&context)

        if active == nil, !queue.isEmpty {
            active = ActiveReaction(kind: queue.removeFirst(), start: t)
        }
        if var reaction = active {
            let progress = (t - reaction.start) / ReactionPlayer.duration(reaction.kind, tuning: tuning)
            if progress >= 1 {
                finish(reaction.kind, at: t)
                active = nil
            } else {
                ReactionPlayer.apply(&reaction, progress: progress, elapsed: t - reaction.start, side: zzzSide < 0 ? 1 : -1, tuning: tuning, to: &frame)
                active = reaction
            }
        }
        if active == nil {
            if t < happyUntil { frame.happy = 1 }
            if t < lookDownUntil {
                frame.gaze = SIMD2(0, 0.8)
                frame.restGaze = frame.gaze
            }
        }

        // Наведение во сне: веки плавно поднимаются, «Zzz» тают, взгляд — на курсор.
        wake.update(toward: hovered && state == .sleep ? 1 : 0, omega: hovered ? 9 : 5, dt: dt)
        let awake = min(max(wake.value, 0), 1)
        if awake > 0.01 {
            frame.eyeScale += (1.05 - frame.eyeScale) * awake
            if awake > 0.3 { frame.motionless = false }
        }

        // Замечает тебя: раз в несколько минут находит курсор где угодно (хоть на другом мониторе)
        // и коротко смотрит в его сторону. Только когда ты двигал мышь недавно — смотрит на живого.
        if let cursor {
            if let last = lastCursor, hypot(cursor.x - last.x, cursor.y - last.y) > 2 { cursorMovedAt = t }
            lastCursor = cursor
        }
        let calmState = state == .idle || state == .think
        if nextFarGlance == nil { nextFarGlance = t + Double.random(in: tuning.farGlanceInterval, using: &context.rng) }
        if calmState, active == nil, !hovered, let due = nextFarGlance, t >= due {
            nextFarGlance = t + Double.random(in: tuning.farGlanceInterval, using: &context.rng)
            if t - cursorMovedAt < 3, let offset = cursorOffset(cursor), offset.length > tuning.hoverRadius {
                farLook = offset / offset.length * 0.95
                farLookUntil = t + tuning.farGlanceDuration
                frame.saccade = 1.2
            }
        }
        if t < farLookUntil && calmState && active == nil {
            frame.gaze = farLook
            frame.eyeScale = max(frame.eyeScale, 1.08)
        }

        // Ждёт с новостями: спит довольным — «^ ^» вместо закрытых век.
        if contented && state == .sleep && active == nil {
            frame.happy = 1
        }

        var followingCursor = false
        if !state.isWaiting && !frame.motionless {
            if t < glanceUntil {
                frame.gaze = SIMD2(glanceX, -0.1)
            }
            if let offset = cursorOffset(cursor), let follow = CursorGaze.gaze(offset: offset, radius: tuning.hoverRadius) {
                frame.gaze = follow
                followingCursor = true
            }
        }

        if let dragLook {
            frame.gaze = dragLook
            frame.eyeScale = max(frame.eyeScale, 1.1)
        }
        if lidGaze != 0 && !frame.motionless && !state.isWaiting {
            frame.gaze.y += lidGaze
        }

        // Микродвижения: живые глаза не застывают даже в фиксации. Не во сне и не когда смотрит на пользователя.
        if !frame.motionless && !state.isWaiting && !followingCursor {
            let drift = SIMD2(
                sin(t * 1.9) * 0.6 + sin(t * 3.7 + 1) * 0.4,
                sin(t * 2.3 + 2) * 0.6 + sin(t * 4.1) * 0.4
            )
            frame.gaze += drift * tuning.microSaccade
        }

        // Наклон: задумался — пара глаз чуть поворачивается к взгляду; курсор рядом — с любопытством к нему.
        var tiltTarget = frame.tilt ?? 0
        if frame.tilt != nil {
            // Наклон задало поведение.
        } else if state == .think {
            tiltTarget = tuning.thinkTilt * (frame.gaze.x >= 0 ? 1 : -1)
        } else if followingCursor {
            tiltTarget = tuning.hoverTilt * max(-1, min(1, frame.gaze.x))
        }

        if reduceMotion {
            // Никаких саккад и подпрыгиваний: только форма глаз, статичный взгляд и свечение.
            frame.gaze = frame.restGaze
            frame.bodyOffset = .zero
            frame.bodyScale = 1
            frame.saccade = nil
            tiltTarget = 0
        } else {
            // Дыхание тела; во сне — медленнее, в ритм свечения.
            let period = state == .sleep ? tuning.sleepGlowPeriod : tuning.breathPeriod
            frame.bodyScale *= 1 + tuning.breathAmount * sin(2 * .pi * t / period)
            tiltTarget += baseline.sway * sin(2 * .pi * t / 2.5)
        }

        // Самочувствие: тяжёлые веки, надутость, тусклое или подрагивающее свечение.
        if frame.happy < 0.5 && state != .sleep {
            frame.eyeScale *= baseline.eyeOpen
        }
        frame.bodyScale *= baseline.bodyScale
        // Устал или поздно — тело оседает.
        if state != .sleep && active == nil { frame.bodyOffset.y += baseline.droop }
        // Довольный в покое изредка подпрыгивает: чем радостнее, тем чаще.
        if baseline.bounce > 0, state == .idle, active == nil, !reduceMotion {
            let due = nextBounce ?? (t + 20 / baseline.bounce)
            nextBounce = due
            if t >= due {
                nextBounce = t + Double.random(in: 15...40, using: &context.rng) / baseline.bounce
                queue.append(.hop)
            }
        } else {
            nextBounce = nil
        }
        frame.glowOpacity *= baseline.glowOpacity
        if baseline.glowFlicker > 0 && !reduceMotion {
            frame.glowOpacity += baseline.glowFlicker * 0.12 * (sin(t * 23) * 0.6 + sin(t * 37) * 0.4)
        }

        // Большая саккада в 30% случаев сопровождается морганием — так делают живые глаза.
        if let jump = frame.saccade, jump > tuning.bigSaccade, context.chance(tuning.bigSaccadeBlinkChance) {
            blink.trigger(at: t, double: false, tuning: tuning)
        }
        if let request = frame.blink {
            blink.trigger(at: t, double: request == .double, tuning: tuning)
        }
        let blinkScale = baseline.blinkInterval
        blink.update(
            t: t,
            interval: frame.blinkInterval.map { ($0.lowerBound * blinkScale)...($0.upperBound * blinkScale) },
            context: &context
        )
        let lid = blink.openness(at: t, tuning: tuning)
        rng = context.rng

        if dt == 0 {
            gaze = Spring2(frame.gaze)
            eyeScale = Spring(frame.eyeScale)
            glowOpacity = Spring(frame.glowOpacity)
        }
        // За курсором — мягкое ведение, а не резкая саккада.
        gaze.update(toward: frame.gaze, omega: followingCursor ? 12 : tuning.saccadeOmega * baseline.motionSpeed, dt: dt)
        swap.update(toward: frame.eyeSwap, omega: 14, dt: dt)
        zzz.update(toward: frame.sleepiness * (1 - awake), omega: 6, dt: dt)
        eyeScale.update(toward: frame.eyeScale, omega: 18, dt: dt)
        happy.update(toward: frame.happy, omega: 20, dt: dt)
        body.update(toward: frame.bodyOffset, omega: 60, dt: dt)
        bodyScale.update(toward: frame.bodyScale, omega: 40, dt: dt)
        glowOpacity.update(toward: frame.glowOpacity, omega: 10, dt: dt)
        glowRadius.update(toward: frame.glowRadiusScale, omega: 12, dt: dt)
        tilt.update(toward: tiltTarget, omega: 8, dt: dt)

        // Растяжение и сжатие из скорости тела: летит — вытянут, приземлился — сплющился.
        let velocityY = body.y.velocity
        if lastVelocityY > 12, velocityY <= 2, !reduceMotion {
            impact.value = -tuning.landingSquash * min(1, lastVelocityY / 40)
            impact.velocity = 0
        }
        lastVelocityY = velocityY
        impact.update(toward: 0, omega: 16, dt: dt)
        let stretch = reduceMotion ? 0 : min(tuning.maxStretch, abs(velocityY) * tuning.stretchPerSpeed)

        return MascotPose(
            gaze: gaze.value.clamped(1),
            eyeScale: max(0, eyeScale.value) * lid,
            happy: min(max(happy.value, 0), 1),
            bodyOffset: body.value,
            bodyScale: bodyScale.value,
            squash: stretch + impact.value,
            tilt: tilt.value,
            glowRadius: tuning.glowRadius * glowRadius.value,
            glowOpacity: min(max(glowOpacity.value, 0), 1),
            zzz: reduceMotion ? frame.sleepiness * (1 - awake) : min(max(zzz.value, 0), 1),
            zzzSide: zzzSide,
            time: reduceMotion ? 0 : t,
            eyeSwap: swap.value,
            eyeSpread: baseline.eyeSpread,
            glowWarmth: baseline.glowWarmth,
            glyph: frame.glyph
        )
    }

    private func finish(_ reaction: MascotReaction, at t: Double) {
        switch reaction {
        case .done: happyUntil = t + tuning.doneHappyHold
        case .error: lookDownUntil = t + tuning.errorLookDown
        default: break
        }
    }

    /// Смещение курсора от центра маскота в pt, y вниз.
    private func cursorOffset(_ cursor: CGPoint?) -> SIMD2<Double>? {
        guard let cursor, let center = screenCenter else { return nil }
        return SIMD2(cursor.x - center.x, -(cursor.y - center.y))
    }
}
