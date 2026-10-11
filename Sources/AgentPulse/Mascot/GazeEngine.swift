import AgentPulseCore
import Foundation

/// Фиксация взгляда: точка + время, до которого на неё смотрим. Переход между фиксациями — саккада;
/// сам переход делает пружина в `MascotAnimator`.
struct Fixation {
    private(set) var target: SIMD2<Double>
    private(set) var until: Double

    init(target: SIMD2<Double> = .zero, until: Double = 0) {
        self.target = target
        self.until = until
    }

    func isDue(_ t: Double) -> Bool {
        t >= until
    }

    /// Возвращает амплитуду скачка — по ней аниматор решает, моргнуть ли в момент перевода.
    mutating func move(to point: SIMD2<Double>, until: Double) -> Double {
        let jump = (point - target).length
        target = point
        self.until = until
        return jump
    }
}

/// Слежение за курсором: смещение курсора от центра маскота (pt, y вниз) → взгляд.
enum CursorGaze {
    static func gaze(offset: SIMD2<Double>, radius: Double) -> SIMD2<Double>? {
        guard offset.length <= radius else { return nil }
        return (offset / 80).clamped(1)
    }
}
