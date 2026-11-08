import AppKit
import SwiftUI

/// Исходные векторы макета. Файлы лежат в приложении, сетевых загрузок при показе нет.
@MainActor
enum ConsoleAssets {
    private static var images: [String: NSImage] = [:]

    static func image(_ name: String, template: Bool = false) -> NSImage {
        let key = name + (template ? ".template" : "")
        if let image = images[key] { return image }
        let url = Bundle.main.resourceURL?.appending(path: "Console/\(name).svg")
        let image = url.flatMap { NSImage(contentsOf: $0) } ?? NSImage()
        image.isTemplate = template
        images[key] = image
        return image
    }
}

struct ConsoleAsset: View {
    let name: String
    let width: Double
    let height: Double
    var tint: Color?

    var body: some View {
        Image(nsImage: ConsoleAssets.image(name, template: tint != nil))
            .resizable()
            .renderingMode(tint == nil ? .original : .template)
            .foregroundStyle(tint ?? .white)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// Персонаж пустой Библиотеки: исходные слои Figma в их локальной геометрии.
struct LibraryEmptyCharacter: View {
    private func layer(_ name: String, _ width: Double, _ height: Double, _ x: Double, _ y: Double) -> some View {
        ConsoleAsset(name: "empty-" + name, width: width, height: height).offset(x: x, y: y)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            layer("ring-back", 70.4813, 27.3057, -5.305, 17.12)
            layer("sparkle-back", 9, 9, 53.96, 13.24)
            layer("star-back", 8, 8, 30.89, 40.71)
            layer("dot-back", 5, 5, -3.36, 35.84)
            layer("body", 60, 60, 0, 0)
            RoundedRectangle(cornerRadius: 2.25).fill(Color(hex: 0xFFF4E6))
                .frame(width: 4.5, height: 10).offset(x: 22.75, y: 27)
            RoundedRectangle(cornerRadius: 2.25).fill(Color(hex: 0xFFF4E6))
                .frame(width: 4.5, height: 10).offset(x: 32.75, y: 27)
            layer("ring-front", 70.4813, 27.3057, -5.173, 21.093)
            layer("sparkle-front", 9, 9, 53.96, 13.24)
            layer("star-front", 8, 8, 30.89, 40.71)
            layer("dot-front", 5, 5, -3.36, 35.84)
        }
        .frame(width: 60, height: 60, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Как в длинных состояниях макета: последние строки мягко уходят в край области прокрутки.
    func consoleScrollFade() -> some View {
        mask {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Color.white
                    LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: min(40, geometry.size.height / 3))
                }
            }
        }
    }
}
