import Foundation

/// Разбор горизонтального свайпа: одно движение — одна страница.
/// Считается весь жест, а не отдельные события: косые события не выпадают, короткий взмах
/// добирается инерцией, длинный не листает дважды, вертикальная прокрутка списка страницу не трогает.
public struct PageSwipe: Sendable, Equatable {
    public enum Phase: Sendable {
        /// Пальцы легли на трекпад.
        case began
        case moved
        case ended
        /// Инерция после отрыва пальцев.
        case momentum
        /// Мышь с горизонтальным колесом: фаз у неё нет.
        case wheel
    }

    public static let distance = 30.0
    /// Во сколько раз движение вбок должно быть больше движения вверх-вниз.
    public static let dominance = 1.2
    /// Настолько явная прокрутка вверх-вниз закрепляет жест за списком.
    public static let verticalLock = 20.0
    /// Пауза колеса, после которой начинается новый жест.
    public static let wheelGap: TimeInterval = 0.35

    private var x = 0.0
    private var y = 0.0
    private var finished = false
    private var lastWheel = Date.distantPast

    public init() {}

    private mutating func reset() {
        x = 0
        y = 0
        finished = false
    }

    /// `dx` положителен, когда страница должна идти вперёд. Возвращает шаг: 1, −1 или nil.
    public mutating func feed(dx: Double, dy: Double, phase: Phase, at date: Date) -> Int? {
        switch phase {
        case .began:
            reset()
        case .ended:
            return nil
        case .wheel:
            if date.timeIntervalSince(lastWheel) > Self.wheelGap { reset() }
            lastWheel = date
        case .moved, .momentum:
            break
        }
        guard !finished else { return nil }
        x += dx
        y += dy
        if abs(y) >= Self.verticalLock, abs(y) > abs(x) * Self.dominance {
            finished = true
            return nil
        }
        guard abs(x) >= Self.distance, abs(x) > abs(y) * Self.dominance else { return nil }
        finished = true
        return x > 0 ? 1 : -1
    }
}

/// Чей жест: страниц или списка под курсором. Решается один раз за жест, по первым пунктам движения.
/// Решать надо до того, как событие дойдёт до поля или списка: они забирают жест себе целиком.
public struct ScrollAxis: Sendable, Equatable {
    public enum Owner: Sendable, Equatable {
        case pages, list
    }

    /// Столько пунктов движения хватает, чтобы понять направление.
    public static let decisionDistance = 4.0

    public private(set) var owner: Owner?
    private var x = 0.0
    private var y = 0.0

    public init() {}

    public mutating func begin() {
        self = ScrollAxis()
    }

    public mutating func feed(dx: Double, dy: Double) -> Owner? {
        if let owner { return owner }
        x += dx
        y += dy
        guard abs(x) + abs(y) >= Self.decisionDistance else { return nil }
        owner = abs(x) > abs(y) ? .pages : .list
        return owner
    }
}
