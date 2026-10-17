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

    // Белый фон с едва заметным объёмом сверху вниз и тонкой кромкой.
    NSGradient(colors: [NSColor.white, NSColor(white: 0.955, alpha: 1)])!.draw(in: shape, angle: -90)
    NSColor(white: 0, alpha: 0.06).setStroke()
    shape.lineWidth = max(1, 2 * scale)
    shape.stroke()

    // Значок: 60% плашки.
    let side = 824 * scale * 0.6
    glyph.draw(in: NSRect(x: (CGFloat(size) - side) / 2, y: (CGFloat(size) - side) / 2, width: side, height: side))
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
