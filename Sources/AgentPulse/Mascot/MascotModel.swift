import Foundation

/// Текущая поза маскота — весь контракт между анимацией и отрисовкой.
struct MascotPose: Equatable {
    /// −1…1; y вниз положительный.
    var gaze: SIMD2<Double> = .zero
    /// 0 — закрыты, 0.6 — прищур, 1.2 — удивление.
    var eyeScale: Double = 1
    /// 0 — овалы, 1 — дуги «^ ^».
    var happy: Double = 0
    /// В pt при диаметре 48.
    var bodyOffset: SIMD2<Double> = .zero
    var bodyScale: Double = 1
    var glowRadius: Double = 10
    var glowOpacity: Double = 0.55
}

/// Критически задемпфированная пружина: быстрый переход без перелёта. Точное решение, не зависит от fps.
struct Spring {
    var value: Double
    var velocity: Double = 0

    init(_ value: Double) {
        self.value = value
    }

    mutating func update(toward target: Double, omega: Double, dt: Double) {
        guard dt > 0 else { return }
        let offset = value - target
        let decay = exp(-omega * dt)
        let drift = (velocity + omega * offset) * dt
        velocity = (velocity - omega * drift) * decay
        value = target + (offset + drift) * decay
    }
}

struct Spring2 {
    var x: Spring
    var y: Spring

    init(_ value: SIMD2<Double> = .zero) {
        x = Spring(value.x)
        y = Spring(value.y)
    }

    var value: SIMD2<Double> { SIMD2(x.value, y.value) }

    mutating func update(toward target: SIMD2<Double>, omega: Double, dt: Double) {
        x.update(toward: target.x, omega: omega, dt: dt)
        y.update(toward: target.y, omega: omega, dt: dt)
    }
}

extension SIMD2 where Scalar == Double {
    var length: Double { (x * x + y * y).squareRoot() }

    func clamped(_ limit: Double) -> SIMD2<Double> {
        SIMD2(Swift.min(Swift.max(x, -limit), limit), Swift.min(Swift.max(y, -limit), limit))
    }
}
