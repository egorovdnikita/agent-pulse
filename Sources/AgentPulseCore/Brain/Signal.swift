import Foundation

/// Орган чувств. Каждый — один файл в `Senses/` и одна регистрация.
public enum SenseID: String, Sendable, Codable, CaseIterable {
    case agents, power, thermal, memory, disk, network, display, sleepWake, presence, space, clock
    case appearance, audio, quiet, keyboard, interaction, lidAngle
}

/// Что заметил орган чувств. Только системные сигналы: ни окон, ни приложений, ни содержимого.
public enum SignalKind: String, Sendable, Codable, CaseIterable {
    // Питание
    case batteryLow, batteryCritical, batteryRecovered, chargerConnected, chargerDisconnected, fullyCharged
    case lowPowerOn, lowPowerOff
    // Тепло, память, диск
    case thermalHigh, thermalNormal, memoryPressure, memoryNormal, diskLow, diskOK
    // Сеть и мониторы (value — направление нового/ушедшего монитора: −1 слева, 1 справа)
    case networkLost, networkBack, displayAdded, displayRemoved
    // Сон, блокировка (value у screenUnlocked — сколько был заблокирован, s)
    case systemWake, systemSleep, screenLocked, screenUnlocked
    // Присутствие (value у userBack — сколько отсутствовал, s)
    case userAway, userBack, longWork
    // Часы: раз в минуту; uptime > 7 дней
    case minute, uptimeLong
    // Тема, звук, клавиатура
    case darkMode, lightMode, headphonesOn, headphonesOff, volumeMax, capsLockOn, capsLockOff
    // Тишина: микрофон/камера заняты, полный экран, тихие часы
    case quietOn, quietOff
    // Рабочие столы
    case spaceChanged
    // Взаимодействие (value у dragged — скорость, pt/s)
    case stroke, poke, dragged, thrown, dropped
    // Агенты — сверх основного конвейера состояний
    case agentWaitingLong, agentErrorStreak, agentStep, agentDone, agentError
    // Эксперимент: угол крышки, градусы
    case lidAngle
}

public struct Signal: Sendable, Equatable {
    public let sense: SenseID
    public let kind: SignalKind
    public let value: Double?
    public let ts: Date

    public init(_ sense: SenseID, _ kind: SignalKind, value: Double? = nil, ts: Date = Date()) {
        self.sense = sense
        self.kind = kind
        self.value = value
        self.ts = ts
    }
}

/// Порог с гистерезисом: «голодный» ниже `enter`, «сытый» снова только выше `exit` — иначе реакция мигает.
public struct Hysteresis: Sendable {
    public enum Edge: Sendable, Equatable { case entered, exited }

    public let enter: Double
    public let exit: Double
    /// `true` — срабатывает при падении ниже порога (батарея), `false` — при росте выше (температура).
    public let falling: Bool
    public private(set) var active = false

    public init(enter: Double, exit: Double, falling: Bool = true) {
        self.enter = enter
        self.exit = exit
        self.falling = falling
    }

    public mutating func update(_ value: Double) -> Edge? {
        if !active, falling ? value < enter : value > enter {
            active = true
            return .entered
        }
        if active, falling ? value > exit : value < exit {
            active = false
            return .exited
        }
        return nil
    }
}
