import AgentPulseCore
import AppKit
import ApplicationServices

/// Control: только модификаторы и общий счётчик активности, без чтения текста.
@MainActor
final class ConsoleControlKey {
    private var local: Any?
    private var global: Any?
    private var tap = ControlTap()
    private var action: (() -> Void)?

    func set(_ action: (() -> Void)?) {
        [local, global].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        local = nil
        global = nil
        tap = ControlTap()
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
        if tap.observe(control: flags.contains(.control),
                       otherModifier: !flags.intersection([.command, .shift, .option, .function]).isEmpty,
                       activity: activity, time: event.timestamp) { action?() }
    }
}
