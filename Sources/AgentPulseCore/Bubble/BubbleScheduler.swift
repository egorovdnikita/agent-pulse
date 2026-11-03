import Foundation

public struct BubbleTuning: Codable, Sendable, Equatable {
    /// Фоновая реплика `think`/`work` — не чаще.
    public var ambientInterval: TimeInterval = 12
    /// …и только если модус продержался столько.
    public var ambientMinHold: TimeInterval = 2
    /// Минимальное время показа любого облачка.
    public var minShow: TimeInterval = 1

    public var notice: TimeInterval = 1.5
    public var ambient: TimeInterval = 2.5
    public var step: TimeInterval = 1.2
    public var result: TimeInterval = 4
    public var fallAsleep: TimeInterval = 1.5
    /// Облачко ожидания сворачивается, когда ты столько секунд за компьютером при нём: значит, видел.
    /// Ожидание остаётся в позе и глазах, текст — по наведению.
    public var waitSeen: TimeInterval = 8

    public init() {}

    /// Сколько нужно, чтобы заметить облачко краем глаза и дочитать: ~1 s перевести взгляд
    /// и ~15 знаков в секунду — спокойное чтение с экрана, не скорочтение.
    public static func readingTime(_ text: String) -> TimeInterval {
        min(12, 1 + Double(text.count) / 15)
    }

    /// `nil` — держится до реакции пользователя.
    public func duration(for trigger: BubbleTrigger) -> TimeInterval? {
        switch trigger {
        case .notice: notice
        case .think, .workRead, .workEditCode, .workEditFigma, .workRun, .workSearch: ambient
        case .step: step
        case .done, .error: result
        case .fallAsleep: fallAsleep
        case .waitPermission, .waitInput, .hoverSleep: nil
        case .line: ambient
        }
    }
}

public struct Bubble: Sendable, Equatable {
    public let id: Int
    public let trigger: BubbleTrigger
    /// К чему относится: иконка и цвет заголовка.
    public let category: BubbleCategory
    /// Заголовок: название категории или приложения агента («Claude Code»).
    public let title: String
    /// Светлая пометка рядом с заголовком: источник новости.
    public var note: String? = nil
    public let text: String
    public let shownAt: Date
    public var duration: TimeInterval?
}

/// Одно облачко за раз. Реакции — всегда, в очереди; ожидание вытесняет всё; фон — редко.
public struct BubbleScheduler: Sendable {
    public static let queueLimit = 3

    private struct Item: Sendable {
        var trigger: BubbleTrigger
        var text: String?
        var duration: TimeInterval?
        var category: BubbleCategory
        var title: String
        var note: String? = nil
        /// Агентные реплики встают впереди реплик тела и ритма.
        var agent: Bool
        /// Ответ на твоё действие (кабель, тычок): вклинивается даже в ожидание и в тихие часы.
        var answersUser = false
    }

    public var tuning: BubbleTuning
    /// Тишина: облачко молчит, кроме ожидания пользователя.
    public var quiet = false
    /// Настроение окрашивает реплики.
    public var mood: Mood?
    public private(set) var current: Bubble?
    public private(set) var lastText: String?
    private var queue: [Item] = []
    /// Облачко ожидания, отложенное на время короткого ответа на твоё действие, — потом возвращается.
    private var pausedWait: Bubble?
    /// Агент ждёт тебя — даже когда облачко уже свернулось, фон молчит.
    public private(set) var waiting = false
    private var waitSeenTime: TimeInterval = 0
    private var lastActivityAt: Date?
    private var lastAmbientAt: Date = .distantPast
    private var picker = PhrasePicker()
    private var rng = SystemRandomNumberGenerator()
    private var nextId = 0

    public init(tuning: BubbleTuning = BubbleTuning()) {
        self.tuning = tuning
    }

    /// Реплика агентного конвейера. `title` — приложение агента («Claude Code»).
    public mutating func react(_ trigger: BubbleTrigger, category: BubbleCategory = .claude, title: String? = nil, now: Date) {
        let category = trigger == .fallAsleep || trigger == .hoverSleep ? .rest : category
        let title = category == .rest ? category.title : title ?? category.title
        if trigger.isWait {
            queue.removeAll()
            pausedWait = nil
            waiting = true
            waitSeenTime = 0
            show(Item(trigger: trigger, text: nil, duration: nil, category: category, title: title, agent: true), now: now)
            return
        }
        enqueue(Item(trigger: trigger, text: nil, duration: tuning.duration(for: trigger), category: category, title: title, agent: true), now: now)
    }

    /// Реплика каталога реакций (тело, ритм, взаимодействие, приколы, агентные сверх конвейера).
    public mutating func say(
        _ text: String, duration: TimeInterval, category: BubbleCategory = .mood, title: String? = nil, note: String? = nil,
        agent: Bool = false, answersUser: Bool = false, now: Date
    ) {
        enqueue(Item(
            trigger: .line, text: text, duration: duration, category: category, title: title ?? category.title, note: note,
            agent: agent, answersUser: answersUser
        ), now: now)
    }

    /// Правила наложения:
    /// - ожидание тебя вытесняет всё фоновое; ответ на твоё действие вклинивается на время чтения, затем ожидание возвращается;
    /// - в тишине молчит всё, кроме агентного и ответа на твоё действие (решение о тихих часах принимает Director);
    /// - агентное встаёт впереди тела и ритма.
    private mutating func enqueue(_ item: Item, now: Date) {
        if quiet && !item.agent && !item.answersUser { return }
        if quiet && item.trigger != .line { return }
        if let current, current.trigger.isWait, current.duration == nil {
            guard item.answersUser else { return }
            pausedWait = current
            self.current = nil
            show(item, now: now)
            return
        }
        // Облачко ожидания свернулось, но агент всё ещё ждёт: фон по-прежнему молчит.
        if waiting && !item.agent && !item.answersUser { return }
        if item.agent, let firstLine = queue.firstIndex(where: { !$0.agent }) {
            queue.insert(item, at: firstLine)
        } else {
            queue.append(item)
        }
        if queue.count > Self.queueLimit { queue.removeLast() }
        tick(now: now)
    }

    public mutating func ambient(
        _ trigger: BubbleTrigger?, category: BubbleCategory = .claude, title: String? = nil, heldSince: Date, now: Date
    ) {
        guard
            let trigger,
            !quiet,
            current == nil,
            queue.isEmpty,
            now.timeIntervalSince(heldSince) >= tuning.ambientMinHold,
            now.timeIntervalSince(lastAmbientAt) >= tuning.ambientInterval
        else { return }
        lastAmbientAt = now
        show(Item(trigger: trigger, text: nil, duration: tuning.duration(for: trigger), category: category, title: title ?? category.title, agent: true), now: now)
    }

    /// Пользователь отреагировал: облачко ожидания уходит, но не раньше минимального времени показа.
    public mutating func endWait(now: Date) {
        pausedWait = nil
        waiting = false
        guard var bubble = current, bubble.trigger.isWait else { return }
        bubble.duration = 0
        current = bubble
        tick(now: now)
    }

    /// Ты за компьютером (`active` — был ввод только что). Набралось `waitSeen` секунд при облачке ожидания —
    /// значит, видел: облачко сворачивается, ожидание остаётся в позе.
    public mutating func noteActivity(active: Bool, now: Date) {
        defer { lastActivityAt = now }
        guard var bubble = current, bubble.trigger.isWait, bubble.duration == nil else {
            waitSeenTime = 0
            return
        }
        if active, let last = lastActivityAt { waitSeenTime += min(max(now.timeIntervalSince(last), 0), 1) }
        guard waitSeenTime >= tuning.waitSeen else { return }
        waitSeenTime = 0
        bubble.duration = 0
        current = bubble
        tick(now: now)
    }

    public mutating func tick(now: Date) {
        if let bubble = current {
            let elapsed = now.timeIntervalSince(bubble.shownAt)
            let preempted = (bubble.trigger.isAmbient || (bubble.trigger == .line && queue.first?.agent == true))
                && !queue.isEmpty && elapsed >= tuning.minShow
            let expired = bubble.duration.map { elapsed >= max($0, tuning.minShow) } ?? false
            guard preempted || expired else { return }
            current = nil
            // Ответ на действие сказан — ожидание возвращается тем же облачком.
            if let wait = pausedWait {
                pausedWait = nil
                current = wait
                return
            }
        }
        if !queue.isEmpty {
            show(queue.removeFirst(), now: now)
        }
    }

    public mutating func phrase(for trigger: BubbleTrigger) -> String {
        picker.pick(trigger, using: &rng)
    }

    private mutating func show(_ item: Item, now: Date) {
        let picked = item.text ?? picker.pick(item.trigger, mood: mood, using: &rng)
        // Ожидание пользователя — всегда ясно и без окраски.
        let text = item.trigger.isWait ? picked : MoodVoice.color(picked, mood: mood)
        nextId += 1
        // Длинное успевает прочитаться: облачко держится не меньше времени чтения.
        let duration = item.duration.map { max($0, BubbleTuning.readingTime(text)) }
        current = Bubble(
            id: nextId, trigger: item.trigger, category: item.category, title: item.title, note: item.note, text: text,
            shownAt: now, duration: duration
        )
        lastText = text
    }
}
