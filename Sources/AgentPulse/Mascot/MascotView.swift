import AppKit
import SwiftUI

/// Процедурный маскот: круглое тело с белым свечением и два чёрных овала-глаза. Больше ничего.
struct MascotView: View {
    let animator: MascotAnimator
    let diameter: Double
    /// Панель скрыта — ноль кадров, ноль CPU.
    var paused = false
    /// Во сне хватает 10 fps: дыхание и «Zzz» медленные.
    var lowFrameRate = false

    /// Бодрствующему маскоту в 48 pt хватает 30 fps — глазу не отличить от 60, CPU вдвое меньше.
    static let awakeFrameInterval = 1.0 / 30
    static let sleepFrameInterval = 1.0 / 10

    /// Холст с запасом над головой — под «Zzz».
    static func boxSize(_ diameter: Double) -> Double {
        diameter * 2.2
    }

    var body: some View {
        Group {
            if paused {
                frame(at: Date())
            } else {
                // Строго периодическое расписание: `.animation(minimumInterval:)` всё равно будит
                // отрисовку с частотой экрана, и сон стоил столько же CPU, сколько работа.
                TimelineView(.periodic(from: .now, by: lowFrameRate ? Self.sleepFrameInterval : Self.awakeFrameInterval)) { timeline in
                    frame(at: timeline.date)
                }
            }
        }
        .frame(width: Self.boxSize(diameter), height: Self.boxSize(diameter))
    }

    private func frame(at date: Date) -> some View {
        let pose = animator.pose(at: date.timeIntervalSinceReferenceDate, cursor: NSEvent.mouseLocation)
        return Canvas { context, size in
            MascotRenderer.draw(pose, in: &context, size: size, diameter: diameter)
        }
    }
}

/// Геометрия задана для диаметра 48 pt и масштабируется от диаметра.
enum MascotRenderer {
    static func draw(_ pose: MascotPose, in context: inout GraphicsContext, size: CGSize, diameter: Double) {
        let unit = diameter / 48
        let center = CGPoint(
            x: size.width / 2 + pose.bodyOffset.x * unit,
            y: size.height / 2 + pose.bodyOffset.y * unit
        )
        let radius = diameter / 2 * pose.bodyScale
        let body = Path(ellipseIn: circle(center, radius))

        // Тень держит силуэт на светлом холсте Figma и белых окнах; считывается как часть свечения.
        // Радиальный градиент вместо фильтра размытия: вид тот же, а рисуется в разы дешевле.
        let shadowRadius = radius + 8 * unit
        context.fill(
            Path(ellipseIn: circle(center, shadowRadius)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0.25), location: 0),
                    .init(color: .black.opacity(0.25), location: (radius - 4 * unit) / shadowRadius),
                    .init(color: .black.opacity(0), location: 1),
                ]),
                center: center, startRadius: 0, endRadius: shadowRadius
            )
        )

        let glowRadius = radius + pose.glowRadius * unit
        context.fill(
            Path(ellipseIn: circle(center, glowRadius)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(pose.glowOpacity), .white.opacity(0)]),
                center: center, startRadius: radius * 0.8, endRadius: glowRadius
            )
        )

        context.fill(body, with: .color(.white))
        drawZzz(pose, in: &context, center: center, radius: radius, unit: unit)

        let eyeWidth = 7 * unit * pose.bodyScale
        let eyeHeight = 10 * unit * pose.bodyScale
        for side in [-1.0, 1.0] {
            let eyeCenter = CGPoint(
                x: center.x + (side * 8 + pose.gaze.x * 6) * unit,
                y: center.y + (-2 + pose.gaze.y * 4) * unit
            )
            // При взгляде вбок дальний глаз сужается — объём шара без лишних элементов.
            let isFar = (side < 0 && pose.gaze.x > 0) || (side > 0 && pose.gaze.x < 0)
            let width = eyeWidth * (isFar ? 1 - 0.15 * min(1, abs(pose.gaze.x)) : 1)
            let height = eyeHeight * pose.eyeScale

            // Почти закрытый овал плавно перетекает в веко «‿» — закрытые глаза видны, а не исчезают.
            let closed = min(max((0.35 - pose.eyeScale) / 0.25, 0), 1) * (1 - pose.happy)
            if pose.happy < 1, closed < 1, height > 0.3 {
                let oval = CGRect(x: eyeCenter.x - width / 2, y: eyeCenter.y - height / 2, width: width, height: height)
                context.fill(Path(ellipseIn: oval), with: .color(.black.opacity((1 - pose.happy) * (1 - closed))))
            }
            if closed > 0 {
                var lid = Path()
                lid.move(to: CGPoint(x: eyeCenter.x - eyeWidth * 0.65, y: eyeCenter.y))
                lid.addQuadCurve(
                    to: CGPoint(x: eyeCenter.x + eyeWidth * 0.65, y: eyeCenter.y),
                    control: CGPoint(x: eyeCenter.x, y: eyeCenter.y + eyeHeight * 0.4)
                )
                context.stroke(
                    lid, with: .color(.black.opacity(closed)),
                    style: StrokeStyle(lineWidth: 1.8 * unit, lineCap: .round)
                )
            }
            if pose.happy > 0 {
                var arc = Path()
                arc.move(to: CGPoint(x: eyeCenter.x - eyeWidth * 0.6, y: eyeCenter.y + eyeHeight * 0.15))
                arc.addQuadCurve(
                    to: CGPoint(x: eyeCenter.x + eyeWidth * 0.6, y: eyeCenter.y + eyeHeight * 0.15),
                    control: CGPoint(x: eyeCenter.x, y: eyeCenter.y - eyeHeight * 0.55)
                )
                context.stroke(
                    arc, with: .color(.black.opacity(pose.happy)),
                    style: StrokeStyle(lineWidth: 2.2 * unit, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    /// Три «z» всплывают от макушки внутрь экрана, растут и тают по очереди.
    private static func drawZzz(_ pose: MascotPose, in context: inout GraphicsContext, center: CGPoint, radius: Double, unit: Double) {
        guard pose.zzz > 0.01 else { return }
        let period = 2.6
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 2 * unit))
            for index in 0..<3 {
                let phase = (pose.time / period + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let x = center.x + pose.zzzSide * (radius * 0.55 + 20 * unit * phase)
                let y = center.y - radius * 0.7 - 26 * unit * phase
                let size = (16 + 12 * phase) * unit
                let opacity = pose.zzz * sin(.pi * phase)
                layer.draw(
                    Text("z").font(.system(size: size, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(opacity)),
                    at: CGPoint(x: x, y: y)
                )
            }
        }
    }

    private static func circle(_ center: CGPoint, _ radius: Double) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
