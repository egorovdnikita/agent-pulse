import Foundation

public enum WorkMode: String, Sendable, Hashable, CaseIterable, Codable {
    case read, edit, run, search, general
}

public enum MascotState: Sendable, Hashable {
    case sleep
    case idle
    case think
    case work(WorkMode)
    case waitYou(AgentEvent.AwaitReason)

    public var isWaiting: Bool {
        if case .waitYou = self { true } else { false }
    }
}

/// One-shot анимации поверх состояния. Используют только параметры тела — без новых элементов.
public enum MascotReaction: String, Sendable, CaseIterable, Codable {
    // Агенты
    case notice, step, done, error
    // Тело ноутбука
    case startle        // вздрагивает
    case relax          // выдох: сжатие-расширение
    case contentSquint  // довольный прищур
    case lookAround     // озирается
    case lookLeft, lookRight
    case stretch        // потягивается
    case slowClose      // глаза медленно закрываются
    case puff           // надувается
    case wideEyes       // глаза 1.2
    case squint         // прищур
    case fastBlink      // частое моргание
    case wobble         // покачивание
    case yawn           // зевок — глазами и телом
    // Взаимодействие и характер
    case purr           // жмурится от поглаживания
    case flinch         // тычок
    case turnAway       // отворачивается
    case turnAwayLong   // отворачивается на 10 s
    case dizzy          // глаза кружатся
    case lookDown
    case sideEye        // косится
    case eyeSwap        // 1 апреля: глаза меняются местами
    // Приколы
    case sneeze, hiccup, fly, nap, stare
    // Ритм суток
    case doze           // клюёт носом: глаза слипаются — вздрагивает
    case hop            // довольный подскок на месте
    // Пиксельные выражения и мелкие живые движения
    case stars          // звёзды в глазах: новость, праздник
    case dreamSmile     // во сне улыбается: «^ ^» на пару секунд
    case sleepPeek      // во сне приоткрывает глаза и снова засыпает
    case sleepRoll      // во сне ворочается
    case curious        // в покое: присматривается, наклоняет голову

    /// Реплика агентного конвейера; у остальных реакций реплики задаёт каталог.
    public var bubbleTrigger: BubbleTrigger? {
        switch self {
        case .notice: .notice
        case .step: .step
        case .done: .done
        case .error: .error
        default: nil
        }
    }
}
