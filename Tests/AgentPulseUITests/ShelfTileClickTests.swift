import AgentPulseCore
import AppKit
import SwiftUI
import Testing
@testable import AgentPulse

/// Настоящие клики по плиткам: жест пустого места не должен сбрасывать выделение до клика по файлу.
@Suite @MainActor struct ShelfTileClickTests {
    private func click(_ window: NSWindow, at point: NSPoint, flags: NSEvent.ModifierFlags) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    @Test func shiftAndCommandClicksExtendSelection() {
        _ = NSApplication.shared
        let model = ConsoleModel(promo: true)
        model.addToShelf(["a.txt", "b.txt", "c.txt", "d.txt", "e.txt"].map { URL(fileURLWithPath: "/tmp/pulse-example/" + $0) })
        let height = 242.0
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ShelfTab(model: model).frame(width: 640, height: height))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let order = model.shelfOrder
        let frames = model.shelfFrames
        // Центр превью плитки в координатах окна (у окна ось Y снизу вверх).
        func point(_ index: Int) -> NSPoint {
            let frame = frames[order[index]]!
            return NSPoint(x: frame.midX + 8, y: height - (frame.minY + 38))
        }
        click(window, at: point(0), flags: [])
        #expect(model.shelfSelection.urls == [order[0]])
        click(window, at: point(2), flags: .shift)
        #expect(model.shelfSelection.urls == Set(order[0...2]))
        click(window, at: point(4), flags: .command)
        #expect(model.shelfSelection.urls == Set(order[0...2]).union([order[4]]))
        // Пустое место под плитками по-прежнему снимает выделение.
        click(window, at: NSPoint(x: frames[order[6 < order.count ? 6 : order.count - 1]]!.maxX + 60, y: height - (frames[order[0]]!.maxY + 20)), flags: [])
        #expect(model.shelfSelection.isEmpty)
    }
}
