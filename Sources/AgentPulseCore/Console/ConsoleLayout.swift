import CoreGraphics
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
    /// Отступ панели от Dock и всего Пульта от края экрана: один и тот же, чтобы он стоял ровно в углу.
    public static let screenGap = 16.0
    /// Замер на macOS 26: tilesize 81, 11 иконок — 988 pt, шаг иконки 84.8 pt; остаток — поля и разделитель.
    public static let dockTilePitch = 1.05
    public static let dockPadding = 56.0
    public static let capsuleHeight = 32.0
    public static let dotSize = 28.0
    public static let minWidth = 96.0
    public static let maxWidth = 220.0
    /// Капсула активного режима: волна диктовки.
    public static let activeWidth = 240.0
    /// Широкая и низкая: сервисы и колонки страниц стоят рядом, а не друг под другом.
    public static let expandedWidth = 640.0
    public static let expandedHeight = 232.0
    /// Запас окна: пружина формы слегка заходит за её размер, и край не должен обрезаться.
    public static let overshoot = 24.0
    /// Наименьший зазор между панелью и капсулой, если Dock скрыт.
    public static let expandedGap = 8.0
    /// Нижний отступ капсулы, если полосы Dock нет.
    public static let edgeMargin = 4.0

    /// Сколько места у капсулы рядом с Dock. nil Dock — оценка не удалась.
    public static func fit(screenWidth: Double, dock: DockMetrics?) -> ConsoleFit {
        guard let dock else { return .leader }
        if dock.edge != .bottom || dock.hidden { return .full(width: maxWidth) }
        let free = (screenWidth - dock.length) / 2 - screenGap * 2
        if free >= minWidth { return .full(width: min(free, maxWidth)) }
        return free >= dotSize ? .leader : .dot
    }

    /// Капсула активного режима тоже не заезжает на Dock.
    public static func activeWidth(screenWidth: Double, dock: DockMetrics?) -> Double {
        guard let dock, dock.edge == .bottom, !dock.hidden else { return activeWidth }
        let free = (screenWidth - dock.length) / 2 - screenGap * 2
        return max(minWidth, min(activeWidth, free))
    }

    /// Капсула на уровне Dock, как маскот: по центру его полосы, а если Dock скрыт — у края.
    public static func capsuleY(screen: CGRect, visible: CGRect) -> Double {
        screen.minY + max(edgeMargin, (visible.minY - screen.minY - capsuleHeight) / 2)
    }

    /// Панель стоит над Dock, поэтому зазор до капсулы зависит от его высоты: `visible` даёт система.
    public static func gap(screen: CGRect, visible: CGRect) -> Double {
        let capsuleTop = capsuleY(screen: screen, visible: visible) + capsuleHeight
        return max(expandedGap, visible.minY + screenGap - capsuleTop)
    }

    /// Левый край Пульта: от края экрана или от бокового Dock.
    public static func x(visible: CGRect, width: Double, onLeft: Bool) -> Double {
        onLeft ? visible.minX + screenGap : visible.maxX - screenGap - width
    }
}
