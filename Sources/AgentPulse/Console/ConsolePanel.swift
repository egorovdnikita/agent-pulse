import AgentPulseCore
import AppKit
import SwiftUI

/// Вид Пульта: сообщает о курсоре и принимает первый клик, не активируя приложение.
private final class ConsoleHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    var onDropTarget: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?
    var acceptsFiles: (() -> Bool)?

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard acceptsFiles?() == true, !DroppedFiles.urls(sender).isEmpty else { return [] }
        onDropTarget?(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { onDropTarget?(false) }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDropTarget?(false)
        let urls = DroppedFiles.urls(sender)
        onDrop?(urls)
        return !urls.isEmpty
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// Панель Пульта. Как у маскота, но раскрытая становится key: иначе не работает Esc, а дальше и поле суфлёра.
/// Свёрнутая капсула фокус не забирает.
@MainActor
final class ConsolePanel: NSPanel {
    private let model: ConsoleModel
    private var shrinkTask: Task<Void, Never>?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var swipe = PageSwipe()

    init(model: ConsoleModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: ConsoleLayout.minWidth, height: ConsoleLayout.capsuleHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = OverlayPanel.spaceBehavior
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        let host = ConsoleHostingView(rootView: ConsoleRootView(model: model))
        host.sizingOptions = []
        host.onHover = { [weak model] inside in model?.setHover(inside) }
        host.registerForDraggedTypes([.fileURL])
        host.acceptsFiles = { [weak model] in model?.shelfEnabled == true || model?.prompterTabOpen == true }
        host.onDropTarget = { [weak model] on in model?.dropTargeted = on }
        host.onDrop = { [weak model] urls in model?.dropped(urls) }
        contentView = host
    }

    override var canBecomeKey: Bool { model.expanded }
    override var canBecomeMain: Bool { false }

    /// Пульт в углу, противоположном маскоту, всегда внизу. Перетаскивание меняет только отступ маскота.
    func place(on screen: NSScreen, anchor: PulseConfig.Display.Anchor, animated: Bool = false) {
        let dock = DockReader.read()
        model.onLeft = anchor.isRight
        model.fit = ConsoleLayout.fit(screenWidth: screen.frame.width, dock: dock)
        model.expandedWidth = ConsoleLayout.expandedWidth(screenWidth: screen.frame.width, dock: dock)
        model.activeWidth = ConsoleLayout.activeWidth(screenWidth: screen.frame.width, dock: dock)
        let size = model.panelSize
        model.placedSize = size
        let inset = ConsoleLayout.sideInset(dock: dock, onRight: !model.onLeft)
        let frameRect = screen.frame
        let x = model.onLeft ? frameRect.minX + inset : frameRect.maxX - inset - size.width
        // На уровне Dock: по центру его полосы, а если Dock скрыт — у края, как маскот.
        let band = screen.visibleFrame.minY - frameRect.minY
        let y = frameRect.minY + max(4, (band - ConsoleLayout.capsuleHeight) / 2)
        apply(NSRect(x: x, y: y, width: size.width, height: size.height))
    }

    /// Пружина ширины идёт внутри панели, поэтому панель растёт сразу, а сжимается после анимации.
    private func apply(_ target: NSRect) {
        shrinkTask?.cancel()
        let grows = target.width >= frame.width && target.height >= frame.height
        if grows {
            setFrame(target, display: true)
            return
        }
        let union = NSRect(
            x: min(frame.minX, target.minX), y: target.minY,
            width: max(frame.maxX, target.maxX) - min(frame.minX, target.minX), height: max(frame.height, target.height)
        )
        setFrame(union, display: true)
        shrinkTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            self?.setFrame(target, display: true)
        }
    }

    /// Раскрыт: становится key, ловит Esc и клик мимо. Закрыт: отдаёт всё обратно.
    func expandedChanged(overFullScreen: Bool) {
        if model.expanded {
            if overFullScreen { collectionBehavior = OverlayPanel.spaceBehavior.union(.fullScreenAuxiliary) }
            orderFrontRegardless()
            makeKey()
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.setExpanded(false) }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .scrollWheel]) { [weak self] event in
                if event.type == .scrollWheel {
                    MainActor.assumeIsolated { self?.handleScroll(event) }
                    return event
                }
                if event.type == .keyDown, MainActor.assumeIsolated({ self?.handlePageKey(event) == true }) { return nil }
                // У приложения без меню ⌘V и остальные некому обработать: поле суфлёра осталось бы без вставки.
                if event.type == .keyDown, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                   let key = event.charactersIgnoringModifiers?.lowercased(), let action = Self.editActions[key],
                   NSApp.sendAction(action, to: nil, from: nil) {
                    return nil
                }
                let escape = event.type == .keyDown && event.keyCode == 53
                let click = event.type == .leftMouseDown
                let window = event.windowNumber
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if escape || (click && window != self.windowNumber) { self.model.setExpanded(false) }
                }
                return escape ? nil : event
            }
        } else {
            collectionBehavior = OverlayPanel.spaceBehavior
            [outsideMonitor, localMonitor].compactMap(\.self).forEach(NSEvent.removeMonitor)
            outsideMonitor = nil
            localMonitor = nil
            resignKey()
        }
    }

    private static let editActions: [String: Selector] = [
        "v": #selector(NSText.paste(_:)), "c": #selector(NSText.copy(_:)), "x": #selector(NSText.cut(_:)),
        "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:")),
    ]

    /// Горизонтальный свайп листает страницы; вертикальный остаётся спискам.
    private func handleScroll(_ event: NSEvent) {
        guard event.window === self else { return }
        let phase: PageSwipe.Phase
        if !event.momentumPhase.isEmpty {
            phase = .momentum
        } else if event.phase.isEmpty {
            phase = .wheel
        } else if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            phase = .began
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else {
            phase = .moved
        }
        // Вперёд — движение пальцев влево, при любом направлении прокрутки в системе.
        let forward = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaX : event.scrollingDeltaX
        if let step = swipe.feed(dx: forward, dy: event.scrollingDeltaY, phase: phase, at: Date()) {
            model.movePage(by: step)
        }
    }

    /// ← → и цифры листают страницы, если ты не пишешь в поле.
    private func handlePageKey(_ event: NSEvent) -> Bool {
        guard !(firstResponder is NSTextView),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad]).isEmpty else { return false }
        switch event.keyCode {
        case 123: model.movePage(by: -1)
        case 124: model.movePage(by: 1)
        default:
            guard let number = event.characters.flatMap(Int.init), number >= 1 else { return false }
            model.selectPage(number: number)
        }
        return true
    }

    func rejoinAllSpaces() {
        collectionBehavior = []
        collectionBehavior = OverlayPanel.spaceBehavior
    }
}

/// Брошенные файлы. Пути читаются только при броске: ты дал файл явно.
enum DroppedFiles {
    static func urls(_ info: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}

/// Настройки Dock: только размер иконок, их число и край. Названия не читаются, Accessibility не нужен.
@MainActor
enum DockReader {
    static func read() -> DockMetrics? {
        guard let dock = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") else { return nil }
        let tile = (dock["tilesize"] as? NSNumber)?.doubleValue ?? 48
        let count = { (key: String) in (dock[key] as? [Any])?.count ?? 0 }
        let recents = (dock["show-recents"] as? NSNumber)?.boolValue ?? true ? count("recent-apps") : 0
        // Запущенные, но не закреплённые приложения тоже в Dock: считаем по верхней оценке, без названий.
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.count
        let pinned = count("persistent-apps") + count("persistent-others") + recents
        let icons = max(pinned, running) + 2
        let edge = DockMetrics.Edge(rawValue: dock["orientation"] as? String ?? "bottom") ?? .bottom
        return DockMetrics(edge: edge, tileSize: tile, icons: icons, hidden: (dock["autohide"] as? NSNumber)?.boolValue ?? false)
    }
}
