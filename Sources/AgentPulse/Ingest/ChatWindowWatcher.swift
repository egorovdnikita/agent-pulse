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
    static let scanLimit = 4000

    private let handler: Handler
    private let queue = DispatchQueue(label: "agentpulse.chatwindow", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var pid: pid_t?
    private var appElement: AXUIElement?
    private var composer: AXUIElement?
    /// Веб-область claude.ai: её адрес читаем на каждом опросе — сменилась вкладка или чат.
    private var webArea: AXUIElement?
    private var url: String?
    private var lastScan = Date.distantPast
    private var approvalVisible = false
    private var state = ChatWindowSignals.State.idle
    private var session = "desktop-chat"
    /// Сколько полных обходов подряд не нашли кнопок композера.
    private var missedScans = 0
    private var diagnosticWritten = false
    private var chatSnapshotWritten = false

    /// Сюда пишется снимок кнопок, если признаки не нашлись, — по нему выставляются точные подписи.
    static var diagnosticURL: URL {
        PulsePaths.supportDirectory.appending(path: "claude-window.txt")
    }

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
        // Кнопок не нашли — следующий обход реже (1, 2, 4… до 30 s): полный обход окна дорог и для Claude.
        // Во время ответа полный обход нужен только ради кнопок одобрения — раз в 3 s.
        let interval = composer == nil ? min(30, Self.scanInterval * pow(2, Double(min(missedScans, 5)))) : 3
        if composer == nil || state != .idle, now.timeIntervalSince(lastScan) >= interval {
            scan(app)
            lastScan = now
        }
        if let webArea {
            let current = Self.url(webArea)
            if current != url {
                url = current
                composer = nil
                missedScans = 0
                lastScan = .distantPast
                return
            }
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
        transition(to: ChatWindowSignals.state(buttonLabels: labels, approvalVisible: approvalVisible, onChat: true))
    }

    private var lastLookup = Date.distantPast

    private func claudeApp() -> AXUIElement? {
        // Процесс уже известен и жив — не дёргаем LaunchServices каждые 150 ms.
        if let pid, appElement != nil, kill(pid, 0) == 0 {
            return appElement
        }
        // Claude не запущен — ищем его не чаще раза в 2 секунды.
        guard Date().timeIntervalSince(lastLookup) >= 2 else { return nil }
        lastLookup = Date()
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
        var foundArea: AXUIElement?
        var approval = false
        while !queue.isEmpty, visited < Self.scanLimit {
            let element = queue.removeFirst()
            visited += 1
            let role = Self.string(element, kAXRoleAttribute)
            if role == "AXWebArea", foundURL == nil, let address = Self.url(element), ChatWindowSignals.isClaudePage(address) {
                foundURL = address
                foundArea = element
            }
            if role == kAXButtonRole as String, let label = Self.label(element) {
                if foundComposer == nil, ChatWindowSignals.isComposerButton(label, onChat: ChatWindowSignals.isChatPage(foundURL ?? url)) {
                    foundComposer = Self.parent(element)
                }
                if ChatWindowSignals.isApproval(label) {
                    approval = true
                }
            }
            queue += Self.children(element) ?? []
        }
        // Снимок управляющих кнопок: при первом обходе и когда впервые открыт чат — сверить настоящие подписи.
        let onChat = ChatWindowSignals.isChatPage(foundURL)
        if !diagnosticWritten || (onChat && !chatSnapshotWritten) {
            diagnosticWritten = true
            chatSnapshotWritten = chatSnapshotWritten || onChat
            writeSnapshot(app)
        }
        if let foundComposer {
            composer = foundComposer
            missedScans = 0
        } else if composer == nil {
            missedScans += 1
        }
        if let foundURL { url = foundURL }
        if let foundArea { webArea = foundArea }
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
        webArea = nil
        pid = nil
    }

    // MARK: - Отладочный снимок

    /// Роли и подписи кнопок, адреса страниц — без текста переписки. Для настройки признаков.
    func snapshot(completion: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            guard Self.isTrusted else { return completion("Нет разрешения «Универсальный доступ».") }
            guard let app = claudeApp() else { return completion("Claude не запущен.") }
            completion(Self.describe(app))
        }
    }

    private func writeSnapshot(_ app: AXUIElement) {
        try? FileManager.default.createDirectory(at: PulsePaths.supportDirectory, withIntermediateDirectories: true)
        try? Self.describe(app).write(to: Self.diagnosticURL, atomically: true, encoding: .utf8)
    }

    private static func describe(_ app: AXUIElement) -> String {
        var lines: [String] = []
        var queue: [(AXUIElement, Int)] = windows(app).map { ($0, 0) }
        var visited = 0
        while !queue.isEmpty, visited < Self.scanLimit {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let role = string(element, kAXRoleAttribute) ?? "?"
            if role == "AXWebArea" {
                lines.append("\(depth) AXWebArea url=\(url(element) ?? "-")")
            } else if role == kAXButtonRole as String, let text = label(element), isControlLabel(text) {
                lines.append("\(depth) AXButton label=\(text)")
            }
            queue += (children(element) ?? []).map { ($0, depth + 1) }
        }
        lines.insert("элементов обойдено: \(visited)", at: 0)
        return lines.joined(separator: "\n")
    }

    /// В снимок попадают только подписи управляющих кнопок: в боковой панели кнопки подписаны названиями чатов.
    private static let controlWords = ["stop", "send", "submit", "allow", "deny", "cancel", "отправ", "останов", "разреш", "отмен", "запрет"]

    private static func isControlLabel(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return text.count <= 40 && controlWords.contains { lowered.contains($0) }
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
