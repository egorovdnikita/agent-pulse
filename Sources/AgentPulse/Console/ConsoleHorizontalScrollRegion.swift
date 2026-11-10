import AppKit
import SwiftUI

/// Область, где горизонтальный жест принадлежит содержимому, а не вкладкам Пульта.
struct ConsoleHorizontalScrollRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> ConsoleHorizontalScrollMarker { ConsoleHorizontalScrollMarker() }
    func updateNSView(_ view: ConsoleHorizontalScrollMarker, context: Context) {}
}

final class ConsoleHorizontalScrollMarker: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
