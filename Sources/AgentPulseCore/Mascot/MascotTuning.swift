import Foundation

/// Все тайминги и амплитуды маскота в одном месте. Крутятся вживую в MascotLab;
/// финальная настройка движения делается глазами, а не в коде.
public struct MascotTuning: Codable, Sendable, Equatable {
    // Геометрия
    public var diameter: Double = 48

    // Моргание
    public var blinkClose: Double = 0.07
    public var blinkOpen: Double = 0.11
    public var doubleBlinkGap: Double = 0.06
    public var blinkInterval: ClosedRange<Double> = 2.5...6
    public var workBlinkInterval: ClosedRange<Double> = 2...4
    public var editBlinkInterval: ClosedRange<Double> = 4...7
    public var doubleBlinkChance: Double = 0.15

    // Взгляд
    /// Жёсткость критически задемпфированной пружины взгляда: ~4/ω ≈ 130 ms на переход без перелёта.
    public var saccadeOmega: Double = 30
    public var bigSaccade: Double = 0.6
    public var bigSaccadeBlinkChance: Double = 0.3
    public var hoverRadius: Double = 120
    public var modeSwitchDelay: Double = 0.25
    public var bubbleGlance: Double = 0.3

    // Фиксации по состояниям
    public var idleFixation: ClosedRange<Double> = 2...4
    public var thinkFixation: ClosedRange<Double> = 1.5...3
    public var workFixation: ClosedRange<Double> = 0.4...1.2
    public var editFixation: ClosedRange<Double> = 0.4...1.0
    public var searchFixation: ClosedRange<Double> = 1.5...2.5
    public var readLineDuration: Double = 1.4
    public var runAngularSpeed: Double = 1.6

    // Форма глаз
    public var thinkSquint: Double = 0.85
    public var editSquint: Double = 0.75
    public var searchEyeScale: Double = 1.05
    public var waitEyeScale: Double = 1.15
    public var noticeEyeScale: Double = 1.2
    public var errorEyeScale: Double = 0.7

    // Тело
    public var hopHeight: Double = 3
    public var waitPeriod: Double = 3
    /// Растяжение по вертикали на 1 pt/s скорости тела — живой прыжок без ручных ключей.
    public var stretchPerSpeed: Double = 0.0022
    public var maxStretch: Double = 0.07
    /// Сплющивание при приземлении.
    public var landingSquash: Double = 0.07
    /// Приседание перед прыжком, pt.
    public var anticipation: Double = 1.2
    /// Дыхание тела: доля масштаба и период.
    public var breathAmount: Double = 0.012
    public var breathPeriod: Double = 3.6
    /// Микродвижения взгляда во время фиксации — глаза не застывают.
    public var microSaccade: Double = 0.035
    /// Наклон пары глаз, рад: когда думает и когда рядом курсор.
    public var thinkTilt: Double = 0.12
    public var hoverTilt: Double = 0.07

    // Замечает тебя
    /// Раз в столько секунд находит курсор где угодно на экране и коротко на него смотрит.
    public var farGlanceInterval: ClosedRange<Double> = 120...360
    public var farGlanceDuration: Double = 1.4
    /// Курсор быстрее этого (pt/s) прошёл сквозь маскота — вздрагивает.
    public var flybySpeed: Double = 1800

    // Гравитация (если включена): ускорение, pt/s², и упругость отскока от пола.
    public var gravity: Double = 2600
    public var floorBounce: Double = 0.35

    // Сон
    public var sleepAfter: Double = 60
    public var fallAsleepDuration: Double = 1.2
    public var sleepLid: Double = 0.08
    public var sleepGlowPeriod: Double = 5
    public var sleepGlow: ClosedRange<Double> = 0.4...0.6

    // Свечение
    public var glowRadius: Double = 10
    public var glowOpacity: Double = 0.55

    // Реакции
    public var noticeDuration: Double = 0.6
    public var stepDuration: Double = 0.3
    public var doneDuration: Double = 1.2
    public var errorDuration: Double = 0.7
    public var doneHappyHold: Double = 3
    public var errorLookDown: Double = 2

    /// Длительности реакций каталога, s. Агентные — выше, отдельными полями.
    public var reactionDurations: [String: Double] = [
        "startle": 0.5, "relax": 1.4, "contentSquint": 1.6, "lookAround": 1.8, "lookLeft": 2, "lookRight": 2,
        "stretch": 1.8, "slowClose": 2.4, "puff": 2, "wideEyes": 1.2, "squint": 1.2, "fastBlink": 1.2,
        "wobble": 2.4, "yawn": 2.4, "purr": 1.8, "flinch": 0.45, "turnAway": 2, "turnAwayLong": 10,
        "dizzy": 2.4, "lookDown": 2, "sideEye": 2.2, "eyeSwap": 1.4,
        "sneeze": 1.4, "hiccup": 4.6, "fly": 5, "nap": 4.5, "stare": 5, "doze": 3.2, "hop": 0.55,
        "stars": 2.2, "dreamSmile": 2.4, "sleepPeek": 1.6, "sleepRoll": 1.8, "curious": 2.2,
    ]

    // Мелкие живые движения без облачка: в покое и во сне маскот не застывает.
    public var idleActInterval: ClosedRange<Double> = 8...22
    public var sleepActInterval: ClosedRange<Double> = 25...70

    // Анти-дребезг: состояние держится минимум столько.
    public var minStateHold: Double = 0.4

    public var bubble = BubbleTuning()

    public init() {}
}
