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

    public var tuning: BubbleTuning
    public private(set) var current: Bubble?
    public private(set) var lastText: String?
    private var queue: [BubbleTrigger] = []
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
            show(trigger, now: now)
            return
        }
        // Пока агент ждёт пользователя, остальные реплики не нужны.
        if let current, current.trigger.isWait, current.duration == nil { return }
        queue.append(trigger)
        if queue.count > Self.queueLimit { queue.removeFirst() }
        tick(now: now)
    }

    public mutating func ambient(_ trigger: BubbleTrigger?, heldSince: Date, now: Date) {
        guard
            let trigger,
            current == nil,
            queue.isEmpty,
            now.timeIntervalSince(heldSince) >= tuning.ambientMinHold,
            now.timeIntervalSince(lastAmbientAt) >= tuning.ambientInterval
        else { return }
        lastAmbientAt = now
        show(trigger, now: now)
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
            let preempted = bubble.trigger.isAmbient && !queue.isEmpty && elapsed >= tuning.minShow
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

    private mutating func show(_ trigger: BubbleTrigger, now: Date) {
        let text = picker.pick(trigger, using: &rng)
        nextId += 1
        current = Bubble(id: nextId, trigger: trigger, text: text, shownAt: now, duration: tuning.duration(for: trigger))
        lastText = text
    }
}
