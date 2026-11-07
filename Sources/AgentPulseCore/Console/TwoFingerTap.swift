import Foundation

/// Один палец на трекпаде. Содержимое не читается: только где он и какого размера пятно.
public struct TouchContact: Equatable, Sendable {
    /// Палец сохраняет номер от касания до отрыва.
    public var id: Int
    /// Миллиметры от угла трекпада.
    public var x: Double
    public var y: Double
    /// Длина пятна: у пальца маленькая, у ладони нет.
    public var size: Double

    public init(id: Int, x: Double, y: Double, size: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.size = size
    }
}

public struct TouchFrame: Equatable, Sendable {
    public var time: TimeInterval
    public var contacts: [TouchContact]

    public init(time: TimeInterval, contacts: [TouchContact]) {
        self.time = time
        self.contacts = contacts
    }
}

/// Двойное касание двумя пальцами. Только смотрит: события трекпада идут дальше как обычно.
public struct TwoFingerTap: Sendable {
    public var longestTap: TimeInterval = 0.3
    public var longestGap: TimeInterval
    /// Дальше этого касание уже не касание, а движение, мм.
    public var furthestDrift = 2.5
    /// Настолько могут разойтись два касания, мм.
    public var furthestApart = 15.0
    /// Больше этого — ладонь.
    public var largestContact = 20.0

    private struct Touch {
        let start: TimeInterval
        var center: (x: Double, y: Double)?
        var drift = 0.0
        var fingers = 0
        var spoiled = false
    }

    private var touch: Touch?
    private var first: (lifted: TimeInterval, x: Double, y: Double)?

    public init(longestGap: TimeInterval = 0.5) {
        self.longestGap = longestGap
    }

    /// Следующий кадр; true — на кадре, который завершил двойное касание.
    public mutating func observe(_ frame: TouchFrame) -> Bool {
        let count = frame.contacts.count
        if count == 0 { return lift(at: frame.time) }
        var current = touch ?? Touch(start: frame.time)
        current.fingers = max(current.fingers, count)
        if count > 2 || frame.contacts.contains(where: { $0.size > largestContact }) {
            current.spoiled = true
            first = nil
        }
        if count == 2 {
            let x = (frame.contacts[0].x + frame.contacts[1].x) / 2
            let y = (frame.contacts[0].y + frame.contacts[1].y) / 2
            if let center = current.center {
                current.drift = max(current.drift, hypot(x - center.x, y - center.y))
            } else {
                current.center = (x, y)
            }
        }
        touch = current
        return false
    }

    /// Нажатие на трекпад: это клик, а не касание.
    public mutating func press() {
        touch?.spoiled = true
        first = nil
    }

    public mutating func reset() {
        touch = nil
        first = nil
    }

    private mutating func lift(at time: TimeInterval) -> Bool {
        guard let ended = touch else { return false }
        touch = nil
        guard !ended.spoiled, ended.fingers == 2, let center = ended.center,
              time - ended.start <= longestTap, ended.drift <= furthestDrift else {
            first = nil
            return false
        }
        if let first, ended.start - first.lifted <= longestGap, hypot(center.x - first.x, center.y - first.y) <= furthestApart {
            self.first = nil
            return true
        }
        first = (time, center.x, center.y)
        return false
    }
}
