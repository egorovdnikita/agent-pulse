import AgentPulseCore
import AppKit
import Foundation

/// Раскрывает Пульт двойным касанием двумя пальцами. Эксперимент: касания идут из приватного MultitouchSupport.
/// Фреймворк открывается на ходу: нет его или он изменился — отпадает только жест, ⌃⌥X работает как всегда.
/// Способ чтения кадров — как в CapaTheNotch (MIT).
@MainActor
@Observable
final class TrackpadGesture {
    enum Status: Equatable {
        case off, listening, noTrackpad, unavailable

        var title: String {
            switch self {
            case .off: "Выключен"
            case .listening: "Работает"
            case .noTrackpad: "Трекпад не найден"
            case .unavailable: "Недоступен на этой системе"
            }
        }
    }

    private(set) var status = Status.off
    @ObservationIgnored var onDoubleTap: (() -> Void)?
    @ObservationIgnored private var reader: MultitouchReader?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    /// Руки на клавиатуре: касание сейчас случайно.
    private static var typing: Bool {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 0.5
    }

    func setEnabled(_ on: Bool) {
        stop()
        guard on else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.pressure, .leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.reader?.press() }
        }
        // После сна трекпад не всегда возвращается сам.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.startReader() }
        }
        startReader()
    }

    private func startReader() {
        reader?.stop()
        let reader = MultitouchReader(longestGap: NSEvent.doubleClickInterval) { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event) } }
        }
        self.reader = reader
        status = switch reader.start() {
        case .started: .listening
        case .noDevices: .noTrackpad
        case .unreadable: .unavailable
        }
    }

    private func handle(_ event: MultitouchReader.Event) {
        switch event {
        case .doubleTap:
            if !Self.typing { onDoubleTap?() }
        case .layoutChanged:
            // Формат кадров изменился: честно выключаемся, а не срабатываем на мусоре.
            reader?.stop()
            reader = nil
            status = .unavailable
        }
    }

    private func stop() {
        reader?.stop()
        reader = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        status = .off
    }
}

/// Кадры идут в потоке фреймворка: там они разбираются, на главный поток выходит только готовое событие.
final class MultitouchReader: @unchecked Sendable {
    enum Event { case doubleTap, layoutChanged }
    enum Outcome { case started, noDevices, unreadable }

    typealias Device = UnsafeMutableRawPointer
    private typealias FrameCallback = @convention(c) (Device?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Void
    private typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias Register = @convention(c) (Device, FrameCallback) -> Void
    private typealias Start = @convention(c) (Device, Int32) -> Int32
    private typealias Stop = @convention(c) (Device) -> Int32
    private typealias Dimensions = @convention(c) (Device, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Void

    private struct Symbols {
        let createList: CreateList
        let register: Register
        let unregister: Register
        let start: Start
        let stop: Stop
        let dimensions: Dimensions?
    }

    private static let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    private static let stride = 96
    private static let insaneFramesTolerated = 10
    /// У функции кадра нет контекста, поэтому работающий читатель один и лежит здесь.
    nonisolated(unsafe) private static var current: MultitouchReader?
    private static let currentLock = NSLock()

    private let lock = NSLock()
    private var gesture: TwoFingerTap
    private var surfaces: [Device: (width: Double, height: Double)] = [:]
    private var list: CFMutableArray?
    private var symbols: Symbols?
    private var insaneFrames = 0
    private let report: @Sendable (Event) -> Void

    init(longestGap: TimeInterval, report: @escaping @Sendable (Event) -> Void) {
        gesture = TwoFingerTap(longestGap: longestGap)
        self.report = report
    }

    func start() -> Outcome {
        guard let symbols = Self.open() else { return .unreadable }
        guard let list = symbols.createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else { return .noDevices }
        self.symbols = symbols
        self.list = list
        Self.currentLock.withLock { Self.current = self }
        var started = 0
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            var width: Int32 = 0, height: Int32 = 0
            _ = symbols.dimensions?(device, &width, &height)
            lock.withLock {
                surfaces[device] = width > 0 && height > 0 ? (Double(width) / 100, Double(height) / 100) : (160, 100)
            }
            symbols.register(device, Self.callback)
            if symbols.start(device, 0) == 0 { started += 1 }
        }
        return started > 0 ? .started : .unreadable
    }

    func stop() {
        Self.currentLock.withLock { if Self.current === self { Self.current = nil } }
        guard let symbols, let list else { return }
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            symbols.unregister(device, Self.callback)
            _ = symbols.stop(device)
        }
        self.list = nil
        lock.withLock { gesture.reset() }
    }

    func press() {
        lock.withLock { gesture.press() }
    }

    private static func open() -> Symbols? {
        guard let handle = dlopen(path, RTLD_NOW) else { return nil }
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let createList = symbol("MTDeviceCreateList", CreateList.self),
              let register = symbol("MTRegisterContactFrameCallback", Register.self),
              let unregister = symbol("MTUnregisterContactFrameCallback", Register.self),
              let start = symbol("MTDeviceStart", Start.self),
              let stop = symbol("MTDeviceStop", Stop.self) else { return nil }
        return Symbols(
            createList: createList, register: register, unregister: unregister, start: start, stop: stop,
            dimensions: symbol("MTDeviceGetSensorSurfaceDimensions", Dimensions.self)
        )
    }

    private static let callback: FrameCallback = { device, touches, count, _, _ in
        let reader = currentLock.withLock { current }
        reader?.receive(device: device, touches: touches, count: Int(count))
    }

    private func receive(device: Device?, touches: UnsafeMutableRawPointer?, count: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        var sane = (0..<64).contains(count) && (count == 0 || touches != nil)
        var contacts: [TouchContact] = []
        let surface: (width: Double, height: Double) = lock.withLock { device.flatMap { surfaces[$0] } } ?? (160, 100)
        if sane, let touches {
            for index in 0..<count {
                let contact = touches + index * Self.stride
                let state = contact.load(fromByteOffset: 20, as: Int32.self)
                let x = contact.load(fromByteOffset: 32, as: Float.self)
                let y = contact.load(fromByteOffset: 36, as: Float.self)
                guard (0...7).contains(state), (-0.2...1.2).contains(x), (-0.2...1.2).contains(y) else {
                    sane = false
                    break
                }
                // 3 и 4 — палец на стекле, а не над ним.
                guard state == 3 || state == 4 else { continue }
                contacts.append(TouchContact(
                    id: Int(contact.load(fromByteOffset: 16, as: Int32.self)), x: Double(x) * surface.width,
                    y: Double(y) * surface.height, size: Double(contact.load(fromByteOffset: 60, as: Float.self))
                ))
            }
        }
        let event: Event? = lock.withLock {
            guard sane else {
                insaneFrames += 1
                return insaneFrames == Self.insaneFramesTolerated ? .layoutChanged : nil
            }
            return gesture.observe(TouchFrame(time: now, contacts: contacts)) ? .doubleTap : nil
        }
        if let event { report(event) }
    }
}
