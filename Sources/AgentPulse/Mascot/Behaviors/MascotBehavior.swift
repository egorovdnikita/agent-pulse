import AgentPulseCore
import Foundation

struct BehaviorContext {
    let t: Double
    let tuning: MascotTuning
    var rng: SystemRandomNumberGenerator

    mutating func random(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &rng)
    }

    mutating func chance(_ probability: Double) -> Bool {
        random(0...1) < probability
    }
}

enum BlinkRequest {
    case single, double
}

/// Кадр поведения: что состояние хочет от тела, глаз и свечения прямо сейчас.
struct BehaviorFrame {
    var gaze: SIMD2<Double> = .zero
    /// Статичный взгляд для Reduce Motion.
    var restGaze: SIMD2<Double> = .zero
    var eyeScale: Double = 1
    var happy: Double = 0
    var bodyOffset: SIMD2<Double> = .zero
    var bodyScale: Double = 1
    var glowOpacity: Double = 0.55
    var glowRadiusScale: Double = 1
    var blinkInterval: ClosedRange<Double>?
    var blink: BlinkRequest?
    /// Амплитуда саккады, начавшейся в этом кадре.
    var saccade: Double?
    /// Глаза не следят за курсором (сон).
    var motionless = false
}

/// Одна структура на состояние. Поведения не знают про источники и инструменты.
protocol MascotBehavior {
    mutating func step(_ context: inout BehaviorContext) -> BehaviorFrame
}

func breathing(_ t: Double, base: Double, amplitude: Double, period: Double) -> Double {
    base + amplitude * sin(2 * .pi * t / period)
}

enum BehaviorFactory {
    /// Новое поведение подхватывает текущий взгляд и даёт текущей фиксации доиграть.
    static func make(_ state: MascotState, at t: Double, gaze: SIMD2<Double>, tuning: MascotTuning) -> any MascotBehavior {
        let carried = Fixation(target: gaze, until: t + tuning.modeSwitchDelay)
        return switch state {
        case .sleep: SleepBehavior(start: t)
        case .idle: IdleBehavior(fixation: carried)
        case .think: ThinkBehavior(fixation: carried)
        case .work(let mode): WorkBehavior(mode: mode, fixation: carried)
        case .waitYou: WaitBehavior(start: t)
        }
    }
}
