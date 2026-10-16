import AgentPulseCore
import AppKit
import QuartzCore
import SwiftUI

/// Отладка: `AgentPulse --design-sheet out.png` — ключевые позы на светлом, сером и тёмном фоне одной картинкой.
/// Рисует настоящий `MascotLayerView`, чтобы дизайн проверялся глазами, а не по коду.
@MainActor
enum DesignSheet {
    static let poses: [(String, MascotPose)] = {
        var idle = MascotPose()
        var look = MascotPose(); look.gaze = SIMD2(0.9, -0.2)
        var think = MascotPose(); think.gaze = SIMD2(-0.6, -0.8); think.eyeScale = 0.85; think.tilt = 0.12
        var wait = MascotPose(); wait.eyeScale = 1.15; wait.glowRadius = 14; wait.glowOpacity = 0.75
        var happy = MascotPose(); happy.happy = 1; happy.glowOpacity = 0.8; happy.squash = 0.05
        var squint = MascotPose(); squint.eyeScale = 0.55
        var sleep = MascotPose(); sleep.eyeScale = 0.08; sleep.glowOpacity = 0.45; sleep.zzz = 1; sleep.time = 0.9
        var night = MascotPose(); night.glowWarmth = 1; night.eyeScale = 0.9
        idle.time = 0
        return [("idle", idle), ("look", look), ("think", think), ("wait", wait), ("happy", happy), ("squint", squint), ("sleep", sleep), ("night", night)]
    }()

    static func render(to url: URL, diameter: Double = 48, scale: Double = 3) {
        let cell = MascotView.boxSize(diameter)
        let backgrounds: [NSColor] = [NSColor(white: 0.97, alpha: 1), NSColor(white: 0.55, alpha: 1), NSColor(white: 0.1, alpha: 1)]
        let size = CGSize(width: cell * Double(poses.count), height: cell * Double(backgrounds.count))
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.scaleBy(x: scale, y: scale)
        for (row, background) in backgrounds.enumerated() {
            for (column, (_, pose)) in poses.enumerated() {
                let origin = CGPoint(x: Double(column) * cell, y: Double(backgrounds.count - 1 - row) * cell)
                context.setFillColor(background.cgColor)
                context.fill(CGRect(origin: origin, size: CGSize(width: cell, height: cell)))
                let view = MascotLayerView(animator: MascotAnimator(), diameter: diameter)
                view.frame = CGRect(x: 0, y: 0, width: cell, height: cell)
                view.layoutSubtreeIfNeeded()
                view.apply(pose)
                context.saveGState()
                context.translateBy(x: origin.x, y: origin.y)
                view.layer?.render(in: context)
                context.restoreGState()
            }
        }
        guard let image = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Отладка: `AgentPulse --bubble-sheet out.png` — облачко каждой категории на светлом и тёмном фоне.
@MainActor
enum BubbleSheet {
    static let samples: [BubbleMessage] = [
        BubbleMessage(category: .claude, title: "Claude Code", text: "Готово, проверь"),
        BubbleMessage(category: .figma, title: "Figma", text: "Двигаю слои…"),
        BubbleMessage(category: .news, title: "Новости дизайна", text: "Айдентику редко используют ровно в тех форматах, которые предусматривались при разработке"),
        BubbleMessage(category: .battery, title: "Батарея", text: "Мне бы поесть"),
        BubbleMessage(category: .wellbeing, title: "Самочувствие", text: "Мне жарко…"),
        BubbleMessage(category: .network, title: "Сеть", text: "Я никого не слышу"),
        BubbleMessage(category: .devices, title: "Вокруг меня", text: "Что слушаем?"),
        BubbleMessage(category: .day, title: "Наш день", text: "Привет", when: "5 мин назад"),
        BubbleMessage(category: .news, title: "Новости дизайна", text: "Тут разбирают, как редизайнить B2B-продукт и не сломать привычные сценарии", when: "2 ч назад"),
        BubbleMessage(category: .holiday, title: "Праздник", text: "С днюхой!"),
        BubbleMessage(category: .together, title: "Мы с тобой", text: "Мне приятно…"),
        BubbleMessage(category: .mood, title: "Настроение", text: "Апчхи"),
        BubbleMessage(category: .rest, title: "Отдых", text: "Я подремлю"),
    ]

    static func render(to url: URL) {
        let content = HStack(spacing: 0) {
            ForEach([Color(white: 0.96), Color(white: 0.12)], id: \.self) { background in
                VStack(alignment: .trailing, spacing: 10) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, message in
                        BubbleView(message: message, tailOnRight: true)
                    }
                }
                .padding(16)
                .frame(width: BubbleView.maxWidth + 32)
                .background(background)
            }
        }
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
