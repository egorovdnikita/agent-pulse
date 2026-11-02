import Foundation

/// Клип облика Agent Pals: одна петля Lottie на состояние. Имя = имя файла в паке.
public enum PalClip: String, Sendable, CaseIterable, Codable {
    case idle = "Idle", working = "Working", typing = "Typing", thinking = "Thinking"
    case reading = "Reading", writing = "Writing", designing = "Designing", coding = "Coding"
    case searching = "Searching", listening = "Listening", sleeping = "Sleeping", done = "Done", error = "Error"

    /// Длина одной петли: 2.4 s, у Working — 3.2 s.
    public var loop: Double { self == .working ? 3.2 : 2.4 }

    /// Клип про работу агента: между ними маскот переключается реже, чтобы не мельтешить.
    public var isWork: Bool {
        switch self {
        case .working, .typing, .reading, .writing, .designing, .coding, .searching: true
        default: false
        }
    }
}

/// Решает, какой клип сейчас играет и когда его сменить. Единственное место с правилами смены.
///
/// Правила **[решение]**:
/// 1. Состояние → клип: сон — Sleeping, покой — Idle, думает — Thinking, ждёт тебя — Listening («слушаю тебя»),
///    работа по инструменту: читает — Reading, правит код — Coding, рисует в Figma — Designing, запускает — Typing,
///    ищет — Searching, прочее — Working.
/// 2. «Ждёт тебя» вытесняет всё сразу, даже итог, — как и везде в Director.
/// 3. Итог — разовый клип поверх состояния: «готово» — Done две петли, «ошибка» — Error две петли;
///    потом маскот возвращается к текущему состоянию. Новый итог перезапускает разовый клип.
/// 4. Клип держится не меньше одной своей петли — иначе быстрые шаги агента (прочитал → поправил → запустил
///    за секунду) превращаются в мельтешение. Между двумя рабочими клипами — не меньше двух петель:
///    маскот показывает характер работы, а не каждый инструмент. Последнее желание ждёт и применяется,
///    как только срок вышел.
/// 5. Ты рядом — без задержек: наведение или облачко будят спящего сразу (Idle), «Пока» — засыпает сразу.
/// 6. Смена — мягкий кроссфейд `crossfade`: у всех клипов один кадр и одна посадка, тело не прыгает.
public struct PalChoreographer: Sendable {
    public static let crossfade = 0.22
    /// Разовые клипы итога, в петлях.
    public static let outcomeLoops = 2.0

    public private(set) var clip: PalClip = .sleeping
    public private(set) var since: Double = -.infinity
    /// Чего хочет текущее состояние; применяется, когда выйдет срок клипа.
    public private(set) var wanted: PalClip = .sleeping
    private var oneShotUntil: Double?

    public init() {}

    public static func clip(for state: MascotState, target: WorkTarget?) -> PalClip {
        switch state {
        case .sleep: .sleeping
        case .idle: .idle
        case .think: .thinking
        case .waitYou: .listening
        case .work(let mode):
            switch mode {
            case .read: .reading
            case .edit: target == .figma ? .designing : .coding
            case .run: .typing
            case .search: .searching
            case .general: .working
            }
        }
    }

    /// Разовый клип на реакцию; nil — реакция играет только телом поверх текущего клипа.
    public static func oneShot(for reaction: MascotReaction) -> PalClip? {
        switch reaction {
        case .done: .done
        case .error: .error
        default: nil
        }
    }

    /// Новое состояние маскота. `awake` — ты рядом (наведение, облачко): сон уступает покою сразу.
    public mutating func setState(_ state: MascotState, target: WorkTarget?, awake: Bool = false, at t: Double) {
        var next = Self.clip(for: state, target: target)
        if next == .sleeping && awake { next = .idle }
        wanted = next
        if next == .listening {
            // Ждёт тебя — громче всего, без ожидания.
            oneShotUntil = nil
            show(next, at: t)
            return
        }
        guard oneShotUntil == nil else { return }
        let userDriven = (clip == .sleeping) != (next == .sleeping)
        if userDriven || clip == .listening || t >= earliestSwitch {
            show(next, at: t)
        }
    }

    public mutating func react(_ reaction: MascotReaction, at t: Double) {
        // Пока ждёт тебя, итог другой сессии не перебивает ожидание.
        guard let shot = Self.oneShot(for: reaction), wanted != .listening else { return }
        oneShotUntil = t + shot.loop * Self.outcomeLoops
        show(shot, at: t)
    }

    /// Вызывается с каждым кадром или по таймеру. Возвращает true, если клип сменился.
    @discardableResult
    public mutating func tick(at t: Double) -> Bool {
        if let until = oneShotUntil {
            guard t >= until else { return false }
            oneShotUntil = nil
            show(wanted, at: t)
            return true
        }
        guard wanted != clip, t >= earliestSwitch else { return false }
        show(wanted, at: t)
        return true
    }

    /// Когда текущий клип можно сменить без мельтешения.
    public var earliestSwitch: Double {
        let loops = clip.isWork && wanted.isWork ? 2.0 : 1.0
        return since + clip.loop * loops
    }

    /// Ближайший момент, когда `tick` может что-то поменять; nil — ждать нечего.
    public var nextDeadline: Double? {
        if let until = oneShotUntil { return until }
        return wanted != clip ? earliestSwitch : nil
    }

    private mutating func show(_ next: PalClip, at t: Double) {
        guard next != clip || oneShotUntil != nil else { return }
        clip = next
        since = t
    }
}
