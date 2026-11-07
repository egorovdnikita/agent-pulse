import AgentPulseCore
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Вставка текста и чтение выделения через Accessibility. Только по твоему нажатию и только с твоего согласия.
@MainActor
enum TextInsertion {
    enum Outcome: Equatable {
        /// Текст встал, буфер цел.
        case inserted
        /// Текст в буфере обмена; прежнее содержимое буфера заменено.
        case inClipboard
    }

    /// Выделение и поле, откуда оно. Поле нужно, чтобы потом заменить текст.
    struct Selection {
        let text: String
        let element: AXUIElement?
        /// Текст стоит в поле: его можно заменить. Текст на странице — нет.
        let editable: Bool
    }

    static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Выделение. Chrome, VS Code и Figma не отдают его напрямую: тогда нажимаем ⌘C и сразу возвращаем буфер.
    static func selection(pasteboard: NSPasteboard = .general) async -> Selection? {
        let element = focusedElement()
        if let element, let text = string(element, kAXSelectedTextAttribute), !text.isEmpty {
            return Selection(text: text, element: element, editable: isEditable(element))
        }
        let saved = ClipboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        await press(key: kVK_ANSI_C)
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(30))
            if pasteboard.changeCount != before { break }
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        saved.restore(to: pasteboard)
        guard let text, !text.isEmpty else { return nil }
        return Selection(text: text, element: element, editable: element.map(isEditable) ?? false)
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
    }

    /// Запись в поле с проверкой: многие приложения отвечают «успех», а текст не меняют.
    private static func write(_ text: String, into element: AXUIElement) async -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue,
              let before = string(element, kAXValueAttribute),
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else { return false }
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(40))
            if let after = string(element, kAXValueAttribute), after != before, after.contains(text) { return true }
        }
        return false
    }

    /// Текст встаёт туда, где курсор. Куда бы ни пошла вставка, текст либо встал, либо лежит в буфере.
    static func insert(_ text: String, accessibility: Bool, pasteboard: NSPasteboard = .general) async -> Outcome {
        let trusted = accessibility && AXIsProcessTrusted()
        let element = trusted ? focusedElement() : nil
        let role = element.flatMap { string($0, kAXRoleAttribute) }
        switch DictationInsertPlan.choose(accessibility: trusted, role: role) {
        case .field:
            if let element, await write(text, into: element) { return .inserted }
            let saved = ClipboardSnapshot(pasteboard)
            let change = put(text, on: pasteboard)
            await pressPaste()
            // Приложение читает буфер не сразу; если за это время его сменил кто-то ещё, не трогаем.
            try? await Task.sleep(for: .milliseconds(600))
            if pasteboard.changeCount == change { saved.restore(to: pasteboard) }
            return .inserted
        case .pasteKeepingClipboard:
            _ = put(text, on: pasteboard)
            await pressPaste()
            return .inClipboard
        case .clipboard:
            _ = put(text, on: pasteboard)
            NSSound(named: "Pop")?.play()
            return .inClipboard
        }
    }

    /// Заменить выделение там, откуда оно взято.
    static func replace(_ selection: Selection, with text: String, pasteboard: NSPasteboard = .general) async -> Outcome {
        if let element = selection.element, await write(text, into: element) { return .inserted }
        return await insert(text, accessibility: true, pasteboard: pasteboard)
    }

    private static func put(_ text: String, on pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    private static func pressPaste() async {
        await press(key: kVK_ANSI_V)
    }

    private static func press(key: Int) async {
        // ⌃⌥ могут быть ещё зажаты: с ⌘ они дали бы другую команду.
        for _ in 0..<20 where !CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: [.maskControl, .maskAlternate]) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Содержимое буфера со всеми типами: ⌘V не должен съедать то, что ты скопировал раньше.
@MainActor
private struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { saved in
            let item = NSPasteboardItem()
            saved.forEach { item.setData($0.value, forType: $0.key) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
