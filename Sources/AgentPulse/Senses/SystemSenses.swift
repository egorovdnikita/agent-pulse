import AgentPulseCore
import AppKit
import Network

/// Перегрев: `ProcessInfo.thermalState`, по уведомлению.
@MainActor
final class ThermalSense: Sense {
    let id = SenseID.thermal
    private var observer: NSObjectProtocol?
    private var hot = false

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        let check: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            let state = ProcessInfo.processInfo.thermalState
            let nowHot = state == .serious || state == .critical
            // Гистерезис: горячо с serious, остыл — только к nominal/fair.
            if nowHot != self.hot {
                self.hot = nowHot
                emit(Signal(.thermal, nowHot ? .thermalHigh : .thermalNormal))
            }
        }
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { check() } }
        check()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

/// Нехватка памяти: системный источник давления памяти.
@MainActor
final class MemorySense: Sense {
    let id = SenseID.memory
    private var source: DispatchSourceMemoryPressure?

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak source] in
            guard let event = source?.data else { return }
            emit(Signal(.memory, event.contains(.normal) ? .memoryNormal : .memoryPressure))
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
    }
}

/// Свободное место: событий нет — раз в 10 минут, с гистерезисом 10/15 GB.
@MainActor
final class DiskSense: Sense {
    let id = SenseID.disk
    private var timer: Timer?
    private var low = Hysteresis(enter: 10, exit: 15)

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        let check: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            let home = FileManager.default.homeDirectoryForCurrentUser
            guard let bytes = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage else { return }
            let gigabytes = Double(bytes) / 1_000_000_000
            switch self.low.update(gigabytes) {
            case .entered: emit(Signal(.disk, .diskLow, value: gigabytes))
            case .exited: emit(Signal(.disk, .diskOK, value: gigabytes))
            case nil: break
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in MainActor.assumeIsolated { check() } }
        check()
    }

    func stop() {
        timer?.invalidate()
    }
}

/// Сеть: `NWPathMonitor`. Короткие провалы < 5 s не считаются.
@MainActor
final class NetworkSense: Sense {
    let id = SenseID.network
    private let monitor = NWPathMonitor()
    private var online: Bool?
    private var pending: DispatchWorkItem?

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.update(up, emit: emit) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "pulse.network"))
    }

    private func update(_ up: Bool, emit: @escaping @Sendable (Signal) -> Void) {
        guard let online else {
            self.online = up
            return
        }
        pending?.cancel()
        guard up != online else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.online = up
                emit(Signal(.network, up ? .networkBack : .networkLost))
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func stop() {
        monitor.cancel()
    }
}

/// Мониторы: подключение и отключение. value — с какой стороны от главного экрана.
@MainActor
final class DisplaySense: Sense {
    let id = SenseID.display
    private var frames: [CGRect] = []
    private var observer: NSObjectProtocol?

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        frames = NSScreen.screens.map(\.frame)
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = NSScreen.screens.map(\.frame)
                let main = NSScreen.screens.first?.frame ?? .zero
                if let added = now.first(where: { !self.frames.contains($0) }), now.count > self.frames.count {
                    emit(Signal(.display, .displayAdded, value: added.midX < main.midX ? -1 : 1))
                } else if let removed = self.frames.first(where: { !now.contains($0) }), now.count < self.frames.count {
                    emit(Signal(.display, .displayRemoved, value: removed.midX < main.midX ? -1 : 1))
                }
                self.frames = now
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

/// Сон и пробуждение системы, блокировка экрана.
@MainActor
final class SleepWakeSense: Sense {
    let id = SenseID.sleepWake
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var lockedAt: Date?

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            emit(Signal(.sleepWake, .systemSleep))
        }))
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            emit(Signal(.sleepWake, .systemWake))
        }))
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockedAt = Date() }
            emit(Signal(.sleepWake, .screenLocked))
        }))
        observers.append((distributed, distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                let locked = self?.lockedAt.map { Date().timeIntervalSince($0) } ?? 0
                self?.lockedAt = nil
                emit(Signal(.sleepWake, .screenUnlocked, value: locked))
            }
        }))
    }

    func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }
}

/// Присутствие: простой пользователя без разрешений (`secondsSinceLastEventType`), раз в 5 s.
/// Перерыв — простой > 5 мин; 3 часа без перерыва — «пройдёмся?».
@MainActor
final class PresenceSense: Sense {
    let id = SenseID.presence
    static let awayAfter: TimeInterval = 5 * 60
    static let longWork: TimeInterval = 3 * 3600
    /// Столько работы без пауз длиннее `focusGap` — «сосредоточен».
    static let focusAfter: TimeInterval = 2 * 60
    static let focusGap: TimeInterval = 3
    /// Пауза посреди работы, но ещё не перерыв — «замер».
    static let pauseAfter: TimeInterval = 45

    private var timer: Timer?
    private var awaySince: Date?
    private var activeSince = Date()
    private var longWorkSent = false
    private var focusSince: Date?
    private var focused = false
    private var paused = false

    static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(emit) }
        }
    }

    private func check(_ emit: @Sendable (Signal) -> Void) {
        let idle = Self.idleSeconds
        let now = Date()
        checkRhythm(idle: idle, now: now, emit)
        if awaySince == nil, idle >= Self.awayAfter {
            awaySince = now.addingTimeInterval(-idle)
            emit(Signal(.presence, .userAway, value: idle))
        } else if let since = awaySince, idle < 5 {
            awaySince = nil
            activeSince = now
            longWorkSent = false
            emit(Signal(.presence, .userBack, value: now.timeIntervalSince(since)))
        } else if awaySince == nil, !longWorkSent, now.timeIntervalSince(activeSince) >= Self.longWork {
            longWorkSent = true
            emit(Signal(.presence, .longWork))
        }
    }

    /// Ритм: давно работаешь без пауз — «сосредоточен»; замер посреди работы — «замер».
    private func checkRhythm(idle: TimeInterval, now: Date, _ emit: @Sendable (Signal) -> Void) {
        if idle < Self.focusGap {
            paused = false
            let since = focusSince ?? now
            focusSince = since
            if !focused, now.timeIntervalSince(since) >= Self.focusAfter {
                focused = true
                emit(Signal(.presence, .userFocused))
            }
        } else {
            focusSince = nil
            if focused, !paused, idle >= Self.pauseAfter, idle < Self.awayAfter {
                focused = false
                paused = true
                emit(Signal(.presence, .userPaused, value: idle))
            }
        }
    }

    func stop() {
        timer?.invalidate()
    }
}

/// Часы: тик раз в минуту (ровно на границе минуты) и uptime > 7 дней.
@MainActor
final class ClockSense: Sense {
    let id = SenseID.clock
    private var timer: Timer?

    nonisolated static var uptime: TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return 0 }
        return Date().timeIntervalSince1970 - Double(boot.tv_sec)
    }

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        let next = (floor(Date().timeIntervalSinceReferenceDate / 60) + 1) * 60
        let timer = Timer(fire: Date(timeIntervalSinceReferenceDate: next), interval: 60, repeats: true) { _ in
            emit(Signal(.clock, .minute))
            if Self.uptime > 7 * 86_400 { emit(Signal(.clock, .uptimeLong)) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
    }
}

/// Тёмная и светлая тема.
@MainActor
final class AppearanceSense: Sense {
    let id = SenseID.appearance
    private var observer: NSObjectProtocol?

    static var isDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { _ in
            // Настройка обновляется чуть позже уведомления.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                emit(Signal(.appearance, Self.isDark ? .darkMode : .lightMode))
            }
        }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}

/// Переключения рабочих столов (только факт, без содержимого).
@MainActor
final class SpaceSense: Sense {
    let id = SenseID.space
    private var observer: NSObjectProtocol?

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in emit(Signal(.space, .spaceChanged)) }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

/// Caps Lock: без разрешений события нет — опрос флагов раз в 2 s.
@MainActor
final class KeyboardSense: Sense {
    let id = SenseID.keyboard
    private var timer: Timer?
    private var on = false

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        on = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
                guard now != self.on else { return }
                self.on = now
                emit(Signal(.keyboard, now ? .capsLockOn : .capsLockOff))
            }
        }
    }

    func stop() {
        timer?.invalidate()
    }
}
