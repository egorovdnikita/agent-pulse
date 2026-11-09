import AgentPulseCore
import AppKit
import ApplicationServices

/// Shift: только модификаторы и общий счётчик активности, без чтения текста.
@MainActor
final class ConsoleShiftKey {
    private var local: Any?
    private var global: Any?
    private var tap = ShiftTap()
    private var action: (() -> Void)?

    func set(_ action: (() -> Void)?) {
        [local, global].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        local = nil
        global = nil
        tap = ShiftTap()
        self.action = action
        guard action != nil else { return }
        local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
            return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
    }

    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func receive(_ event: NSEvent) {
        let flags = event.modifierFlags
        let activity = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].reduce(UInt64(0)) {
            $0 &+ UInt64(CGEventSource.counterForEventType(.combinedSessionState, eventType: $1))
        }
        if tap.observe(shift: flags.contains(.shift),
                       otherModifier: !flags.intersection([.command, .control, .option, .function]).isEmpty,
                       activity: activity, time: event.timestamp) { action?() }
    }
}
