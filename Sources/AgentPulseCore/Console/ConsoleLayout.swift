import Foundation

/// Что известно о Dock из настроек `com.apple.dock`: только размеры и число иконок, без названий.
public struct DockMetrics: Sendable, Equatable {
    public enum Edge: String, Sendable { case bottom, left, right }

    public var edge: Edge
    public var tileSize: Double
    /// Закреплённые и недавние иконки + Finder и Корзина.
    public var icons: Int
    public var hidden: Bool

    public init(edge: Edge, tileSize: Double, icons: Int, hidden: Bool) {
        self.edge = edge
        self.tileSize = tileSize
        self.icons = icons
        self.hidden = hidden
    }

    /// Длина Dock вдоль края экрана, pt. Шаг иконки и поля сверены замером на macOS 26.
    public var length: Double {
        Double(icons) * tileSize * ConsoleLayout.dockTilePitch + ConsoleLayout.dockPadding
    }
}

/// Сколько места у капсулы и какой она может быть.
public enum ConsoleFit: Sendable, Equatable {
    /// Лидер целиком, не шире `width`.
    case full(width: Double)
    /// Только лидер без подписи.
    case leader
    /// Только точка.
    case dot
}

public enum ConsoleLayout {
    public static let dockGap = 16.0
    public static let screenMargin = 12.0
    /// Замер на macOS 26: tilesize 81, 11 иконок — 988 pt, шаг иконки 84.8 pt; остаток — поля и разделитель.
    public static let dockTilePitch = 1.05
    public static let dockPadding = 56.0
    public static let capsuleHeight = 32.0
    public static let dotSize = 28.0
    public static let minWidth = 96.0
    public static let maxWidth = 220.0
    public static let expandedMaxWidth = 360.0
    public static let expandedMinWidth = 280.0
    /// Вкладка над капсулой; вместе с ней и зазором — не выше 320 pt.
    public static let expandedHeight = 280.0
    public static let expandedGap = 8.0

    /// Сколько места между углом экрана и Dock. nil Dock — оценка не удалась.
    public static func fit(screenWidth: Double, dock: DockMetrics?) -> ConsoleFit {
        guard let dock else { return .leader }
        if dock.edge != .bottom || dock.hidden { return .full(width: maxWidth) }
        let free = (screenWidth - dock.length) / 2 - screenMargin - dockGap
        if free >= minWidth { return .full(width: min(free, maxWidth)) }
        return free >= dotSize ? .leader : .dot
    }

    /// Раскрытый Пульт не заезжает на Dock: до 360 pt, сколько есть до его края.
    public static func expandedWidth(screenWidth: Double, dock: DockMetrics?) -> Double {
        guard let dock, dock.edge == .bottom, !dock.hidden else { return expandedMaxWidth }
        let free = (screenWidth - dock.length) / 2 - screenMargin - dockGap
        return max(expandedMinWidth, min(expandedMaxWidth, free))
    }

    /// Отступ от края экрана: у бокового Dock на той же стороне — 16 pt от него.
    public static func sideInset(dock: DockMetrics?, onRight: Bool) -> Double {
        guard let dock, !dock.hidden else { return screenMargin }
        let dockSide: DockMetrics.Edge = onRight ? .right : .left
        return dock.edge == dockSide ? dock.tileSize + dockPadding + dockGap : screenMargin
    }
}
