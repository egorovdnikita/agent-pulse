// Иконка приложения по шаблону macOS: белая скруглённая плашка с мягкой тенью,
// в центре — `sleeping-circle` (Solar Bold из box-ui) цвета `--box-palette-blue-solid-500` (#3b82f6).
// Запуск: swift scripts/make-icon.swift → Resources/AppIcon.icns
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let glyph = NSImage(contentsOf: root.appending(path: "Resources/Icon/sleeping-circle.svg"))!

/// Холст 1024: плашка 824×824 со сдвигом 100, скругление ~22.5% — как у системных иконок Big Sur и новее.
func render(_ size: Int) -> NSBitmapImageRep {
    // sRGB — чтобы #3b82f6 из дизайн-системы остался ровно #3b82f6.
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!.retagging(with: .sRGB)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let plate = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let shape = NSBezierPath(roundedRect: plate, xRadius: 185 * scale, yRadius: 185 * scale)

    // Мягкая тень под плашкой.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 28 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Чисто белая плашка, как у системных иконок в новом стиле: без градиента и кромки.
    NSColor.white.setFill()
    shape.fill()

    // Значок: 66% плашки, мягкое цветное свечение и лёгкий градиент — светлее сверху.
    let side = 824 * scale * 0.66
    let rect = NSRect(x: (CGFloat(size) - side) / 2, y: (CGFloat(size) - side) / 2 - 4 * scale, width: side, height: side)
    let blue = NSColor(srgbRed: 0x3b / 255, green: 0x82 / 255, blue: 0xf6 / 255, alpha: 1)
    let glow = NSShadow()
    glow.shadowColor = blue.withAlphaComponent(0.45)
    glow.shadowBlurRadius = 36 * scale
    glow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    NSGraphicsContext.saveGraphicsState()
    glow.set()
    glyph.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    // Градиент по форме значка: сверху светлее (blue/400 #60a5fa), снизу — ровно blue/500 #3b82f6.
    if let context = NSGraphicsContext.current?.cgContext,
       let mask = glyph.cgImage(forProposedRect: nil, context: nil, hints: [.ctm: AffineTransform(scale: scale * 8)]) {
        context.saveGState()
        context.clip(to: rect, mask: mask)
        let light = NSColor(srgbRed: 0x60 / 255, green: 0xa5 / 255, blue: 0xfa / 255, alpha: 1)
        NSGradient(colors: [light, blue], atLocations: [0, 0.75], colorSpace: .sRGB)!.draw(in: rect, angle: -90)
        context.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * factor).representation(using: .png, properties: [:])!.write(to: iconset.appending(path: name))
    }
}
try! render(1024).representation(using: .png, properties: [:])!.write(to: root.appending(path: "Resources/Icon/AppIcon-1024.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Resources/AppIcon.icns" : "iconutil failed")
