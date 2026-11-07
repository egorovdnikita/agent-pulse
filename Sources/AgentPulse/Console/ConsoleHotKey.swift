import Carbon.HIToolbox
import Foundation

/// Глобальная клавиша через `RegisterEventHotKey`: Input Monitoring не нужен.
@MainActor
final class ConsoleHotKey {
    private static let keyCodes: [String: Int] = [
        "x": kVK_ANSI_X, "z": kVK_ANSI_Z, "c": kVK_ANSI_C, "b": kVK_ANSI_B, "n": kVK_ANSI_N,
    ]
    /// Что можно выбрать в настройках.
    static let letters = ["x", "z", "c", "b", "n"]
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var releaseHandlers: [UInt32: () -> Void] = [:]
    private static var installed = false

    private var reference: EventHotKeyRef?
    private let id: UInt32

    init(id: UInt32) {
        self.id = id
    }

    /// Ставит клавишу ⌃⌥ + буква; пусто — снимает. false — комбинацию занял кто-то другой.
    @discardableResult
    func set(letter: String, action: @escaping () -> Void) -> Bool {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.handlers[id] = nil
        guard let code = Self.keyCodes[letter] else { return letter.isEmpty }
        return register(code: code, action: action)
    }

    /// Ставит клавишу ⌃⌥ + код; nil — снимает. `released` — для удержания: отпускание Input Monitoring тоже не нужно.
    @discardableResult
    func set(code: Int?, released: (() -> Void)? = nil, action: @escaping () -> Void) -> Bool {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.handlers[id] = nil
        Self.releaseHandlers[id] = nil
        guard let code else { return true }
        Self.releaseHandlers[id] = released
        return register(code: code, action: action)
    }

    private func register(code: Int, action: @escaping () -> Void) -> Bool {
        Self.installHandler()
        Self.handlers[id] = action
        let hotKeyID = EventHotKeyID(signature: OSType(0x50554C53), id: id) // 'PULS'
        return RegisterEventHotKey(
            UInt32(code), UInt32(controlKey | optionKey), hotKeyID, GetEventDispatcherTarget(), 0, &reference
        ) == noErr
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var specs = [UInt32(kEventHotKeyPressed), UInt32(kEventHotKeyReleased)].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: $0)
        }
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &hotKey
            )
            let id = hotKey.id
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { (released ? ConsoleHotKey.releaseHandlers[id] : ConsoleHotKey.handlers[id])?() }
            }
            return noErr
        }, specs.count, &specs, nil, nil)
    }
}
