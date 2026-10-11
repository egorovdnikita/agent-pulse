import AgentPulseCore
import AppKit
import SwiftUI

/// Панель поверх всех окон: не крадёт фокус, видна на всех Spaces и поверх полноэкранных приложений.
@MainActor
final class OverlayPanel: NSPanel {
    private let model: PulseModel
    private var currentScreen: NSScreen?

    init(model: PulseModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        contentView = FirstMouseHostingView(rootView: PillView(model: model))
        reposition()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func followActiveScreen() {
        guard model.config.display.screen == "active", let screen = targetScreen(), screen != currentScreen else { return }
        reposition()
    }

    /// Позиция — анкер + отступ на текущем мониторе, а не абсолютные координаты:
    /// при отключении внешнего экрана панель не уезжает за край.
    func reposition() {
        guard let screen = targetScreen() else { return }
        currentScreen = screen
        let display = model.config.display
        let size = PillView.size(diameter: display.mascotSize)
        let visible = screen.visibleFrame
        let margin = 12.0
        let x = display.anchor.isRight ? visible.maxX - size.width - margin : visible.minX + margin
        let y = display.anchor.isTop ? visible.maxY - size.height - margin : visible.minY + margin
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)

        let box = MascotView.boxSize(display.mascotSize)
        let centerX = display.anchor.isRight ? x + size.width - box / 2 : x + box / 2
        model.animator.screenCenter = CGPoint(x: centerX, y: y + size.height / 2)
    }

    private func targetScreen() -> NSScreen? {
        switch model.config.display.screen {
        case "main":
            return NSScreen.screens.first
        case "builtin":
            return NSScreen.screens.first { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                    .map { CGDisplayIsBuiltin($0) != 0 } ?? false
            } ?? NSScreen.screens.first
        default:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        }
    }
}

/// Клик по маскоту срабатывает с первого раза, без предварительной активации окна.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
