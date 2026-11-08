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
