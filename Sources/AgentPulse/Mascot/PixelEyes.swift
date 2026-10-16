import CoreGraphics
import Foundation

/// Пиксельное выражение глаз — как на точечном экране: сердечки, «> <», «— —», звёзды, спираль.
/// Это форма глаз, а не новые элементы: рисуется теми же пикселями на месте глаза.
enum EyeGlyph: Equatable {
    case none
    case heart
    /// «> <» — зажмурился: чих, тычок.
    case squeeze
    /// «— —» — обиделся, не впечатлён, ошибка.
    case flat
    case star
    /// Спираль — укачало.
    case spiral

    /// Битмап правого глаза сверху вниз; левый — зеркально (для несимметричных).
    var bitmap: [String] {
        switch self {
        case .none: []
        case .heart: [
            ".XX.XX.",
            "XXXXXXX",
            "XXXXXXX",
            ".XXXXX.",
            "..XXX..",
            "...X...",
        ]
        case .squeeze: [
            "....XX",
            "..XXXX",
            "XXXX..",
            "..XXXX",
            "....XX",
        ]
        case .flat: [
            "XXXXXXX",
            "XXXXXXX",
        ]
        case .star: [
            "...X...",
            "..XXX..",
            "XXXXXXX",
            ".XXXXX.",
            "..XXX..",
            ".XX.XX.",
        ]
        case .spiral: [
            "XXXXXXX",
            "......X",
            "XXXXX.X",
            "X...X.X",
            "X.XXX.X",
            "X.....X",
            "XXXXXXX",
        ]
        }
    }
}

/// Растеризация глаз в пиксельную сетку. Сетка привязана к центру тела: взгляд и моргание
/// идут шагами в пиксель — это и есть пиксельная анимация, ничего не «плывёт» между клетками.
enum PixelEyes {
    enum Shape: Equatable {
        /// Открытый глаз: овал размером в pt.
        case oval(width: Double, height: Double)
        /// Радость «^» шириной в pt.
        case arc(width: Double)
        /// Закрытые глаза «‿».
        case lid(width: Double)
        case glyph(EyeGlyph)
    }

    /// Клетки глаза (координаты в клетках относительно центра глаза; центр — на линии сетки).
    static func cells(_ shape: Shape, mirrored: Bool, pixel: Double) -> [(Int, Int)] {
        switch shape {
        case .oval(let width, let height):
            guard width > 0.4, height > 0.4 else { return [] }
            let a = width / 2 / pixel, b = height / 2 / pixel
            return grid(halfWidth: Int(ceil(a)), halfHeight: Int(ceil(b))) { x, y in
                (x * x) / (a * a) + (y * y) / (b * b) <= 1
            }
        case .arc(let width):
            let half = width / 2 / pixel
            // «^»: вершина вверху, концы внизу.
            return stroke(half: half, thickness: 1.7) { s in (s * half, -half * 0.55 + abs(s) * abs(s) * half * 0.9 - half * 0.15) }
        case .lid(let width):
            let half = width / 2 / pixel
            // «‿»: концы вверху, середина ниже.
            return stroke(half: half, thickness: 1.6) { s in (s * half, half * 0.35 * (1 - s * s)) }
        case .glyph(let glyph):
            let rows = glyph.bitmap
            guard let columns = rows.first?.count else { return [] }
            var result: [(Int, Int)] = []
            for (row, line) in rows.enumerated() {
                for (column, char) in line.enumerated() where char == "X" {
                    let x = mirrored ? columns - 1 - column : column
                    // Битмап центрирован: клетка (0,0) — справа-снизу от центра глаза.
                    result.append((x - columns / 2, row - rows.count / 2))
                }
            }
            return result
        }
    }

    /// Клетки, центры которых лежат внутри фигуры; центр клетки (i, j) — в (i + 0.5, j + 0.5) с «нулём» на линии сетки.
    private static func grid(halfWidth: Int, halfHeight: Int, inside: (Double, Double) -> Bool) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for j in -halfHeight..<halfHeight {
            for i in -halfWidth..<halfWidth where inside(Double(i) + 0.5, Double(j) + 0.5) {
                result.append((i, j))
            }
        }
        return result
    }

    /// Линия толщиной `thickness` клеток вдоль кривой s ∈ −1…1.
    private static func stroke(half: Double, thickness: Double, curve: (Double) -> (Double, Double)) -> [(Int, Int)] {
        let samples = (0...24).map { curve(-1 + 2 * Double($0) / 24) }
        let reach = Int(ceil(half)) + 2
        return grid(halfWidth: reach, halfHeight: reach) { x, y in
            samples.contains { (x - $0.0) * (x - $0.0) + (y - $0.1) * (y - $0.1) <= thickness * thickness / 4 }
        }
    }

    /// Путь из квадратных пикселей с маленьким зазором — как точечная матрица.
    static func path(_ cells: [(Int, Int)], origin: CGPoint, pixel: Double, gap: Double, maxRow: Int? = nil, minRow: Int = .min) -> CGPath {
        let path = CGMutablePath()
        let size = pixel - gap
        let corner = size * 0.18
        for (i, j) in cells where j >= minRow && (maxRow.map { j <= $0 } ?? true) {
            let rect = CGRect(x: origin.x + Double(i) * pixel + gap / 2, y: origin.y + Double(j) * pixel + gap / 2, width: size, height: size)
            path.addRoundedRect(in: rect, cornerWidth: corner, cornerHeight: corner)
        }
        return path
    }
}
