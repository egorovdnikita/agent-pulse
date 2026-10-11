import AppKit
import SwiftUI

/// Процедурный маскот: круглое тело с белым свечением и два чёрных овала-глаза. Больше ничего.
struct MascotView: View {
    let animator: MascotAnimator
    let diameter: Double
    /// Панель скрыта — ноль кадров, ноль CPU.
    var paused = false
    /// Во сне хватает 15 fps.
    var lowFrameRate = false

    static func boxSize(_ diameter: Double) -> Double {
        diameter * 1.75
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: lowFrameRate ? 1.0 / 15 : nil, paused: paused)) { timeline in
            let pose = animator.pose(at: timeline.date.timeIntervalSinceReferenceDate, cursor: NSEvent.mouseLocation)
            Canvas { context, size in
                MascotRenderer.draw(pose, in: &context, size: size, diameter: diameter)
            }
        }
        .frame(width: Self.boxSize(diameter), height: Self.boxSize(diameter))
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
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 8 * unit))
            layer.fill(body, with: .color(.black.opacity(0.25)))
        }

        let glowRadius = radius + pose.glowRadius * unit
        context.fill(
            Path(ellipseIn: circle(center, glowRadius)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(pose.glowOpacity), .white.opacity(0)]),
                center: center, startRadius: radius * 0.8, endRadius: glowRadius
            )
        )

        context.fill(body, with: .color(.white))

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

            if pose.happy < 1, height > 0.3 {
                let oval = CGRect(x: eyeCenter.x - width / 2, y: eyeCenter.y - height / 2, width: width, height: height)
                context.fill(Path(ellipseIn: oval), with: .color(.black.opacity(1 - pose.happy)))
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

    private static func circle(_ center: CGPoint, _ radius: Double) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
