import AgentPulseCore
import AppKit
import ApplicationServices

/// Чат в Claude desktop через Accessibility: у приложения нет канала событий, а в окне во время ответа
/// видна кнопка «Stop response». Только opt-in, требует разрешения «Универсальный доступ».
///
/// Дешёвый опрос: один раз находим контейнер кнопок композера, дальше раз в 150 ms смотрим только его детей.
/// Полный обход окна — лишь при потере контейнера и для поиска кнопок одобрения, не чаще раза в секунду.
final class ChatWindowWatcher: @unchecked Sendable {
    typealias Handler = @Sendable ([AgentEvent]) -> Void

    static let pollInterval: TimeInterval = 0.15
    static let scanInterval: TimeInterval = 1
    static let scanLimit = 8000

    private let handler: Handler
    private let queue = DispatchQueue(label: "agentpulse.chatwindow", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var pid: pid_t?
    private var appElement: AXUIElement?
    private var composer: AXUIElement?
    private var url: String?
    private var lastScan = Date.distantPast
    private var approvalVisible = false
    private var state = ChatWindowSignals.State.idle
    private var session = "desktop-chat"

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Показывает системный запрос на «Универсальный доступ», если разрешения ещё нет.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.pollInterval, leeway: .milliseconds(30))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Опрос (на queue)

    private func poll() {
        guard Self.isTrusted, let app = claudeApp() else {
            reset()
            return
        }
        let now = Date()
        if composer == nil || state != .idle, now.timeIntervalSince(lastScan) >= Self.scanInterval {
            scan(app)
            lastScan = now
        }
        guard ChatWindowSignals.isChatPage(url) else {
            transition(to: .idle)
            return
        }
        var labels: [String] = []
        if let composer {
            guard let children = Self.children(composer) else {
                // Контейнер исчез (сменился чат) — найдём заново при следующем обходе.
                self.composer = nil
                lastScan = .distantPast
                return
            }
            labels = children.compactMap(Self.label)
        }
        transition(to: ChatWindowSignals.state(buttonLabels: labels, approvalVisible: approvalVisible))
    }

    private func claudeApp() -> AXUIElement? {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: ChatWindowSignals.hostBundleId).first else {
            return nil
        }
        if pid != running.processIdentifier || appElement == nil {
            pid = running.processIdentifier
            let element = AXUIElementCreateApplication(running.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.25)
            // Electron строит дерево доступности только по просьбе.
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            appElement = element
            composer = nil
        }
        return appElement
    }

    /// Полный обход окна: контейнер композера, адрес страницы, кнопки одобрения.
    private func scan(_ app: AXUIElement) {
        var queue: [AXUIElement] = Self.windows(app)
        var visited = 0
        var foundComposer: AXUIElement?
        var foundURL: String?
        var approval = false
        while !queue.isEmpty, visited < Self.scanLimit {
            let element = queue.removeFirst()
            visited += 1
            let role = Self.string(element, kAXRoleAttribute)
            if role == "AXWebArea", foundURL == nil {
                foundURL = Self.url(element)
            }
            if role == kAXButtonRole as String, let label = Self.label(element) {
                if foundComposer == nil, ChatWindowSignals.isComposerButton(label) {
                    foundComposer = Self.parent(element)
                }
                if ChatWindowSignals.isApproval(label) {
                    approval = true
                }
            }
            queue += Self.children(element) ?? []
        }
        if let foundComposer { composer = foundComposer }
        if let foundURL { url = foundURL }
        approvalVisible = approval
        let id = ChatWindowSignals.sessionId(url)
        if id != session {
            transition(to: .idle)
            session = id
        }
    }

    private func transition(to next: ChatWindowSignals.State) {
        guard next != state else { return }
        let events = BrowserBridge.events(
            source: .claudeChat, session: session, state: next.rawValue, from: state.rawValue,
            host: ChatWindowSignals.hostBundleId
        )
        state = next
        if !events.isEmpty { handler(events) }
    }

    private func reset() {
        transition(to: .idle)
        appElement = nil
        composer = nil
        pid = nil
    }

    // MARK: - Отладочный снимок

    /// Роли и подписи кнопок, адреса страниц — без текста переписки. Для настройки признаков.
    func snapshot(completion: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            guard Self.isTrusted else { return completion("Нет разрешения «Универсальный доступ».") }
            guard let app = claudeApp() else { return completion("Claude не запущен.") }
            var lines: [String] = []
            var queue: [(AXUIElement, Int)] = Self.windows(app).map { ($0, 0) }
            var visited = 0
            while !queue.isEmpty, visited < Self.scanLimit {
                let (element, depth) = queue.removeFirst()
                visited += 1
                let role = Self.string(element, kAXRoleAttribute) ?? "?"
                if role == "AXWebArea" {
                    lines.append("\(depth) AXWebArea url=\(Self.url(element) ?? "-")")
                } else if role == kAXButtonRole as String {
                    lines.append("\(depth) AXButton label=\(Self.label(element) ?? "-")")
                }
                queue += (Self.children(element) ?? []).map { ($0, depth + 1) }
            }
            lines.insert("элементов обойдено: \(visited)", at: 0)
            completion(lines.joined(separator: "\n"))
        }
    }

    // MARK: - AX-помощники

    private static func windows(_ app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        if error == .invalidUIElement { return nil }
        return value as? [AXUIElement] ?? []
    }

    private static func parent(_ element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Подпись кнопки: описание, заголовок или подсказка — что задал веб-интерфейс.
    private static func label(_ element: AXUIElement) -> String? {
        for attribute in [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute] as [String] {
            if let value = string(element, attribute), !value.isEmpty { return value }
        }
        return nil
    }

    private static func url(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &value) == .success else { return nil }
        return (value as? URL)?.absoluteString ?? (value as? String)
    }
}
