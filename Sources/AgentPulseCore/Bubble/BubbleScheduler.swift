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

    public init() {}

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
        /// Агентные реплики встают впереди реплик тела и ритма.
        var agent: Bool
    }

    public var tuning: BubbleTuning
    /// Тишина: облачко молчит, кроме ожидания пользователя.
    public var quiet = false
    /// Настроение окрашивает реплики.
    public var mood: Mood?
    public private(set) var current: Bubble?
    public private(set) var lastText: String?
    private var queue: [Item] = []
    private var lastAmbientAt: Date = .distantPast
    private var picker = PhrasePicker()
    private var rng = SystemRandomNumberGenerator()
    private var nextId = 0

    public init(tuning: BubbleTuning = BubbleTuning()) {
        self.tuning = tuning
    }

    public mutating func react(_ trigger: BubbleTrigger, now: Date) {
        if trigger.isWait {
            queue.removeAll()
            show(Item(trigger: trigger, text: nil, duration: nil, agent: true), now: now)
            return
        }
        enqueue(Item(trigger: trigger, text: nil, duration: tuning.duration(for: trigger), agent: true), now: now)
    }

    /// Реплика каталога реакций (тело, ритм, взаимодействие, приколы, агентные сверх конвейера).
    public mutating func say(_ text: String, duration: TimeInterval, agent: Bool = false, now: Date) {
        enqueue(Item(trigger: .line, text: text, duration: duration, agent: agent), now: now)
    }

    private mutating func enqueue(_ item: Item, now: Date) {
        if quiet && !item.agent { return }
        if quiet && item.trigger != .line { return }
        // Пока агент ждёт пользователя, остальные реплики не нужны.
        if let current, current.trigger.isWait, current.duration == nil { return }
        if item.agent, let firstLine = queue.firstIndex(where: { !$0.agent }) {
            queue.insert(item, at: firstLine)
        } else {
            queue.append(item)
        }
        if queue.count > Self.queueLimit { queue.removeLast() }
        tick(now: now)
    }

    public mutating func ambient(_ trigger: BubbleTrigger?, heldSince: Date, now: Date) {
        guard
            let trigger,
            !quiet,
            current == nil,
            queue.isEmpty,
            now.timeIntervalSince(heldSince) >= tuning.ambientMinHold,
            now.timeIntervalSince(lastAmbientAt) >= tuning.ambientInterval
        else { return }
        lastAmbientAt = now
        show(Item(trigger: trigger, text: nil, duration: tuning.duration(for: trigger), agent: true), now: now)
    }

    /// Пользователь отреагировал: облачко ожидания уходит, но не раньше минимального времени показа.
    public mutating func endWait(now: Date) {
        guard var bubble = current, bubble.trigger.isWait else { return }
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
        current = Bubble(id: nextId, trigger: item.trigger, text: text, shownAt: now, duration: item.duration)
        lastText = text
    }
}
