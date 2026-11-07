import CoreGraphics
import Foundation

public enum ConsoleLayout {
    /// Отступ от Dock и от края экрана: один и тот же, чтобы Пульт стоял ровно в углу.
    public static let screenGap = 16.0
    public static let capsuleHeight = 32.0
    public static let dotSize = 28.0
    public static let minWidth = 96.0
    public static let maxWidth = 220.0
    /// Капсула активного режима: волна диктовки.
    public static let activeWidth = 240.0
    public static let expandedWidth = 460.0
    public static let expandedHeight = 400.0
    public static let expandedGap = 8.0

    /// Левый нижний угол панели. `visible` — область экрана без Dock и строки меню:
    /// её даёт система, поэтому Пульт сам следует за высотой Dock, а скрытый Dock просто не мешает.
    public static func origin(visible: CGRect, size: CGSize, onLeft: Bool) -> CGPoint {
        CGPoint(
            x: onLeft ? visible.minX + screenGap : visible.maxX - screenGap - size.width,
            y: visible.minY + screenGap
        )
    }
}
