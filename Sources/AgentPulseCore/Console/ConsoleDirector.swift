import Foundation

public struct ConsoleCandidate: Sendable, Equatable {
    public var module: ConsoleModuleID
    public var priority: ConsolePriority

    public init(module: ConsoleModuleID, priority: ConsolePriority) {
        self.module = module
        self.priority = priority
    }
}

/// Разовая тревога: акцент и один мягкий импульс.
public struct ConsoleAlert: Sendable, Equatable {
    public var id: Int
    public var color: UInt32

    public init(id: Int, color: UInt32) {
        self.id = id
        self.color = color
    }
}

/// Решает, кто занимает свёрнутый Пульт. Лидер держится ≥ 8 s, кроме перехода вверх по списку
/// и конца активного режима: кончившейся диктовке и суфлёру нечего показывать.
/// Пока агент ждёт тебя, Пульт меняет лидера без анимации, а новые тревоги откладывает, разовые тоже.
public struct ConsoleDirector: Sendable, Equatable {
    public static let leaderHold: TimeInterval = 8
    /// Сколько секунд ввода при тревоге значат «увидел».
    public static let alertSeenAfter: TimeInterval = 8

    public private(set) var leader: ConsoleCandidate?
    public private(set) var leaderSince = Date.distantPast
    /// Последняя смена лидера шла без анимации.
    public private(set) var quietChange = false
    public private(set) var alert: ConsoleAlert?
    private var pendingAlerts: [ConsoleAlert] = []
    private var alertInput: TimeInterval = 0
    private var alertCounter = 0

    public init() {}

    public mutating func update(candidates: [ConsoleCandidate], now: Date, agentWaiting: Bool, expanded: Bool) {
        let best = candidates.min { $0.priority < $1.priority }
        if best != leader, !expanded {
            let upward = switch (best, leader) {
            case (.some(let new), .some(let old)): new.priority < old.priority
            default: leader == nil
            }
            let activeModeEnded = leader?.priority == .activeMode
            if upward || activeModeEnded || now.timeIntervalSince(leaderSince) >= Self.leaderHold {
                leader = best
                leaderSince = now
                quietChange = agentWaiting
            }
        }
        if alert == nil, !agentWaiting, !expanded, !pendingAlerts.isEmpty {
            alert = pendingAlerts.removeFirst()
            alertInput = 0
        }
    }

    public mutating func raiseAlert(color: UInt32) {
        alertCounter += 1
        pendingAlerts.append(ConsoleAlert(id: alertCounter, color: color))
    }

    /// Ты 8 s за компьютером при тревоге: значит, видел, капсула возвращается в обычный вид.
    public mutating func noteInput(seconds: TimeInterval) {
        guard alert != nil else { return }
        alertInput += seconds
        if alertInput >= Self.alertSeenAfter { alert = nil }
    }
}
