import Foundation

/// Длящееся самочувствие ноутбука — то, что держится, пока держится сигнал.
public struct BodyCondition: Sendable, Equatable {
    public var batteryLow = false
    public var batteryCritical = false
    public var lowPower = false
    public var hot = false
    public var memoryTight = false
    public var diskFull = false
    public var darkTheme = false
    public var night = false

    public init() {}

    /// Длящиеся флаги из сигналов. Возвращает `true`, если что-то изменилось.
    @discardableResult
    public mutating func apply(_ signal: Signal) -> Bool {
        let before = self
        switch signal.kind {
        case .batteryLow: batteryLow = true
        case .batteryCritical: batteryCritical = true; batteryLow = true
        case .batteryRecovered, .chargerConnected: batteryLow = false; batteryCritical = false
        case .lowPowerOn: lowPower = true
        case .lowPowerOff: lowPower = false
        case .thermalHigh: hot = true
        case .thermalNormal: hot = false
        case .memoryPressure: memoryTight = true
        case .memoryNormal: memoryTight = false
        case .diskLow: diskFull = true
        case .diskOK: diskFull = false
        case .darkMode: darkTheme = true
        case .lightMode: darkTheme = false
        default: break
        }
        return before != self
    }
}

/// Настроение + самочувствие → базовые параметры движения. Поведения не знают, откуда эти множители.
public struct Baseline: Sendable, Equatable {
    /// Множитель интервала моргания: > 1 — моргает реже и медленнее.
    public var blinkInterval = 1.0
    /// Множитель скорости взгляда и длительности фиксаций.
    public var motionSpeed = 1.0
    /// Множитель раскрытия глаз (тяжёлые веки < 1).
    public var eyeOpen = 1.0
    public var glowOpacity = 1.0
    /// 0 — холодный белый, 1 — тёплый белый (ночью).
    public var glowWarmth = 0.0
    /// Подрагивание свечения (перегрев), 0…1.
    public var glowFlicker = 0.0
    /// Покачивание тела (нехватка памяти), радианы амплитуды.
    public var sway = 0.0
    /// Глаза расходятся, pt.
    public var eyeSpread = 0.0
    /// Постоянное надувание (мало места).
    public var bodyScale = 1.0

    public init() {}

    public static func from(mood: Mood, body: BodyCondition) -> Baseline {
        var base = Baseline()
        // Энергия: сонный — моргает реже, движется медленнее, веки тяжелее.
        let tired = max(0, 0.5 - mood.energy) * 2
        base.blinkInterval += tired * 0.5
        base.motionSpeed -= tired * 0.35
        base.eyeOpen -= tired * 0.15
        base.glowOpacity -= tired * 0.15
        // Стресс: моргает чаще.
        let stressed = max(0, mood.stress - 0.5) * 2
        base.blinkInterval -= stressed * 0.3
        // Радость: свечение ярче.
        base.glowOpacity += max(0, mood.joy - 0.5) * 0.3

        if body.batteryLow { base.eyeOpen -= 0.25; base.blinkInterval += 0.4; base.motionSpeed -= 0.2 }
        if body.batteryCritical { base.eyeOpen -= 0.3; base.motionSpeed -= 0.2 }
        if body.lowPower { base.motionSpeed -= 0.3 }
        if body.hot { base.blinkInterval *= 0.5; base.glowFlicker = 0.6 }
        if body.memoryTight { base.sway = 0.05; base.eyeSpread = 1.2 }
        if body.diskFull { base.bodyScale = 1.03 }
        if body.darkTheme { base.glowOpacity -= 0.1 }
        if body.night { base.glowWarmth = 1 }

        base.blinkInterval = min(2.5, max(0.35, base.blinkInterval))
        base.motionSpeed = min(1.3, max(0.35, base.motionSpeed))
        base.eyeOpen = min(1.1, max(0.35, base.eyeOpen))
        base.glowOpacity = min(1.3, max(0.5, base.glowOpacity))
        return base
    }
}
