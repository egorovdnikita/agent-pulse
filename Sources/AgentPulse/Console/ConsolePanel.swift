import AgentPulseCore
import AppKit
import Carbon.HIToolbox
import SwiftUI
import QuickLookUI

/// Вид Пульта: сообщает о курсоре и принимает первый клик, не активируя приложение.
private final class ConsoleHostingView<Content: View>: NSHostingView<Content> {
    var onDropTarget: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?
    var acceptsFiles: (() -> Bool)?

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard acceptsFiles?() == true, !DroppedFiles.urls(sender).isEmpty else { return [] }
        onDropTarget?(true)
        return .copy
    }

    // Без этого ответ на движение даёт сам NSHostingView и отказывает: файл нельзя бросить.
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        acceptsFiles?() == true && !DroppedFiles.urls(sender).isEmpty ? .copy : []
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { onDropTarget?(false) }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDropTarget?(false)
        let urls = DroppedFiles.urls(sender)
        onDrop?(urls)
        return !urls.isEmpty
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Панель Пульта. Как у маскота, но раскрытая становится key: иначе не работает Esc, а дальше и поле суфлёра.
/// Свёрнутая капсула фокус не забирает.
@MainActor
final class ConsolePanel: NSPanel {
    private let model: ConsoleModel
    private let shelfPreview = ShelfPreviewSource()
    private var shrinkTask: Task<Void, Never>?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var menuTracking = false
    private var swipe = PageSwipe()
    private weak var placedScreen: NSScreen?
    private var placedVisible = NSRect.zero
    private var axis = ScrollAxis()
    private var heldEvents: [NSEvent] = []

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
        // Чёрное на тёмных окнах держится на тени: одного тонкого края мало.
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        let host = ConsoleHostingView(rootView: ConsoleRootView(model: model))
        host.sizingOptions = []
        host.registerForDraggedTypes([.fileURL])
        host.acceptsFiles = { [weak model] in model?.shelfEnabled == true || model?.prompterTabOpen == true }
        host.onDropTarget = { [weak model] on in model?.dropTargeted = on }
        host.onDrop = { [weak model] urls in model?.dropped(urls) }
        contentView = host
        model.onShelfPreview = { [weak self] urls, index in self?.showShelfPreview(urls, index: index) }
        // Изменили размер Dock или скрыли его: система сдвинула видимую область, Пульт идёт за ней.
        model.placementChanged = { [weak self] in
            guard let self, let screen = self.placedScreen else { return false }
            return screen.visibleFrame != self.placedVisible
        }
    }

    override var canBecomeKey: Bool { model.expanded }
    override var canBecomeMain: Bool { false }

    /// Пульт в углу, напротив маскота: капсула на уровне Dock, раскрытая панель над ним.
    /// Перетаскивание меняет только отступ маскота.
    func place(on screen: NSScreen, anchor: PulseConfig.Display.Anchor, animated: Bool = false) {
        let dock = DockReader.read()
        let visible = screen.visibleFrame
        model.onLeft = anchor.isRight
        model.fit = ConsoleLayout.fit(screenWidth: screen.frame.width, dock: dock)
        model.activeWidth = ConsoleLayout.activeWidth(screenWidth: screen.frame.width, dock: dock)
        model.expandedGap = ConsoleLayout.gap(screen: screen.frame, visible: visible)
        let size = model.panelSize
        model.placedSize = size
        placedScreen = screen
        placedVisible = visible
        apply(NSRect(
            x: ConsoleLayout.x(visible: visible, width: size.width, onLeft: model.onLeft),
            y: ConsoleLayout.capsuleY(screen: screen.frame, visible: visible), width: size.width, height: size.height
        ))
    }

    /// Пружина ширины идёт внутри панели, поэтому панель растёт сразу, а сжимается после анимации.
    private func apply(_ target: NSRect) {
        shrinkTask?.cancel()
        let grows = target.width >= frame.width && target.height >= frame.height
        if grows {
            setFrame(target, display: true)
            refreshShadow()
            return
        }
        let union = NSRect(
            x: min(frame.minX, target.minX), y: target.minY,
            width: max(frame.maxX, target.maxX) - min(frame.minX, target.minX), height: max(frame.height, target.height)
        )
        setFrame(union, display: true)
        shrinkTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(ConsoleLook.closeMilliseconds))
            guard !Task.isCancelled else { return }
            self?.setFrame(target, display: true)
            self?.refreshShadow()
        }
    }

    /// Тень считается по содержимому окна, поэтому обновляется после анимации формы.
    private func refreshShadow() {
        invalidateShadow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            MainActor.assumeIsolated { self?.invalidateShadow() }
        }
    }

    /// Раскрыт: становится key, ловит Esc и клик мимо. Закрыт: отдаёт всё обратно.
    func expandedChanged(overFullScreen: Bool) {
        if model.expanded {
            let center = NotificationCenter.default
            for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
                menuObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.menuTracking = name == NSMenu.didBeginTrackingNotification }
                })
            }
            if overFullScreen { collectionBehavior = OverlayPanel.spaceBehavior.union(.fullScreenAuxiliary) }
            orderFrontRegardless()
            makeKey()
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { if self?.menuTracking == false { self?.model.setExpanded(false) } }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
                if event.type == .flagsChanged {
                    MainActor.assumeIsolated {
                        self?.model.comparingTranslation = event.modifierFlags.intersection([.option, .command, .control]) == .option
                    }
                    return event
                }
                if event.window is QLPreviewPanel { return event }
                if MainActor.assumeIsolated({ self?.menuTracking == true }) { return event }
                if event.type == .keyDown, MainActor.assumeIsolated({ self?.handleTranslationKey(event) == true }) { return nil }
                if event.type == .keyDown, MainActor.assumeIsolated({ self?.handleShelfKey(event) == true }) { return nil }
                if event.type == .keyDown, MainActor.assumeIsolated({ self?.handlePageKey(event) == true }) { return nil }
                // У приложения без меню ⌘V и остальные некому обработать: поле суфлёра осталось бы без вставки.
                if event.type == .keyDown, event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command,
                   let action = Self.editActions[Int(event.keyCode)],
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
            if QLPreviewPanel.sharedPreviewPanelExists(), let preview = QLPreviewPanel.shared(),
               (preview.currentController as AnyObject?) === self { preview.orderOut(nil) }
            menuObservers.forEach(NotificationCenter.default.removeObserver)
            menuObservers.removeAll()
            menuTracking = false
            collectionBehavior = OverlayPanel.spaceBehavior
            [outsideMonitor, localMonitor].compactMap(\.self).forEach(NSEvent.removeMonitor)
            outsideMonitor = nil
            localMonitor = nil
            resignKey()
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        model.expanded && model.tab == .shelf && !shelfPreview.urls.isEmpty
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = shelfPreview
        panel.reloadData()
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil }

    private func showShelfPreview(_ urls: [URL], index: Int) {
        guard let preview = QLPreviewPanel.shared() else { return }
        if preview.isVisible, (preview.currentController as AnyObject?) === self {
            preview.orderOut(nil)
            return
        }
        shelfPreview.urls = urls
        makeKey()
        // Показ запускает поиск контроллера по цепочке responder; у скрытой панели его ещё нет.
        NSApp.activate()
        preview.makeKeyAndOrderFront(nil)
        preview.updateController()
        if (preview.currentController as AnyObject?) === self {
            preview.reloadData()
            preview.currentPreviewItemIndex = min(max(0, index), urls.count - 1)
        }
    }

    /// ⌘A и Delete на странице «Файлы»: выделить всё и убрать выбранное.
    private func handleShelfKey(_ event: NSEvent) -> Bool {
        guard model.tab == .shelf else { return false }
        guard !(firstResponder is NSTextView) else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        let navigationFlags = flags.subtracting([.function, .numericPad])
        if navigationFlags.isEmpty || navigationFlags == .shift,
           let step = [123: -1, 124: 1, 125: 7, 126: -7][Int(event.keyCode)] {
            model.moveShelfSelection(by: step, extending: navigationFlags == .shift)
            return true
        }
        if navigationFlags.isEmpty, event.keyCode == 49, !model.shelfSelection.isEmpty {
            model.previewShelfFiles()
            return true
        }
        if navigationFlags.isEmpty, [36, 76].contains(Int(event.keyCode)), !model.shelfSelection.isEmpty {
            model.openShelfFiles()
            return true
        }
        if flags == .command, Int(event.keyCode) == kVK_ANSI_C, !model.shelfSelection.isEmpty {
            model.copyShelfFiles()
            return true
        }
        if flags == [.command, .shift], Int(event.keyCode) == kVK_ANSI_Z, model.shelfHistory.canRedo {
            model.redoShelf()
            return true
        }
        if flags == .command, Int(event.keyCode) == kVK_ANSI_Z, model.shelfHistory.canUndo {
            model.undoShelf()
            return true
        }
        if flags == .command, Int(event.keyCode) == kVK_ANSI_A {
            model.selectAllShelf()
            return true
        }
        if navigationFlags.isEmpty, let input = event.characters,
           input.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 && $0.value != 127 }) {
            _ = model.searchShelf(input)
            return true
        }
        if event.keyCode == 51, !model.shelfSelection.isEmpty {
            model.removeSelectedFiles()
            return true
        }
        return false
    }

    private func handleTranslationKey(_ event: NSEvent) -> Bool {
        guard model.tab == .translate else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if flags == [.command, .shift], Int(event.keyCode) == kVK_ANSI_C,
           case .done(_, let text) = model.translate.state {
            model.copyTranslation(text)
            return true
        }
        return false
    }

    private static let editActions: [Int: Selector] = [
        kVK_ANSI_V: #selector(NSText.paste(_:)), kVK_ANSI_C: #selector(NSText.copy(_:)), kVK_ANSI_X: #selector(NSText.cut(_:)),
        kVK_ANSI_A: #selector(NSText.selectAll(_:)), kVK_ANSI_Z: Selector(("undo:")),
    ]

    /// Прокрутка разбирается здесь, а не в мониторе: поле и списки забирают жест в свой цикл, и монитор его больше не видит.
    /// Вбок — страницы, вверх-вниз — тому, кто под курсором. Пока направление неясно, события придерживаются.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel, model.expanded else {
            super.sendEvent(event)
            return
        }
        // Мышь с колесом: фаз у неё нет, каждое событие решается само.
        if event.phase.isEmpty, event.momentumPhase.isEmpty {
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
                super.sendEvent(event)
                return
            }
            if isOverHorizontalScroll(event) { super.sendEvent(event) }
            else { turnPage(event, phase: .wheel) }
            return
        }
        if !event.momentumPhase.isEmpty {
            if axis.owner == .pages { turnPage(event, phase: .momentum) } else { super.sendEvent(event) }
            return
        }
        if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
            axis.begin(overHorizontalList: isOverHorizontalScroll(event))
            if axis.owner == .list {
                heldEvents = []
                super.sendEvent(event)
                return
            }
            heldEvents = [event]
            turnPage(event, phase: .began)
            return
        }
        let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        if axis.owner == nil, !ended {
            heldEvents.append(event)
            guard let owner = axis.feed(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY) else { return }
            if owner == .list {
                heldEvents.forEach { super.sendEvent($0) }
            } else {
                heldEvents.dropFirst().forEach { turnPage($0, phase: .moved) }
            }
            heldEvents = []
            return
        }
        switch axis.owner {
        case .pages:
            turnPage(event, phase: ended ? .ended : .moved)
        case .list:
            super.sendEvent(event)
        case nil:
            // Палец лёг и убран: жест никому не нужен, но начало и конец список должен получить парой.
            heldEvents.forEach { super.sendEvent($0) }
            heldEvents = []
            super.sendEvent(event)
        }
    }

    /// Метка задаёт только область жеста, не участвуя в кликах и выборе языка.
    private func isOverHorizontalScroll(_ event: NSEvent) -> Bool {
        func containsRegion(_ view: NSView) -> Bool {
            guard !view.isHidden else { return false }
            if view is ConsoleHorizontalScrollMarker {
                return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
            }
            return view.subviews.contains(where: containsRegion)
        }
        return contentView.map(containsRegion) ?? false
    }

    private func turnPage(_ event: NSEvent, phase: PageSwipe.Phase) {
        // Пальцы вправо — следующая страница, при любом направлении прокрутки в системе.
        let forward = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        if let step = swipe.feed(dx: forward, dy: event.scrollingDeltaY, phase: phase, at: Date()) {
            model.movePage(by: step)
        }
    }

    /// ← → и цифры листают страницы, если ты не пишешь в поле.
    private func handlePageKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if flags == .command, let number = [18: 1, 19: 2, 20: 3, 21: 4][Int(event.keyCode)] {
            model.selectPage(number: number)
            return true
        }
        guard !(firstResponder is NSTextView),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad, .capsLock]).isEmpty else { return false }
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
