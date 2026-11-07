import AppKit
import AgentPulseCore
import SwiftUI

/// Пузырь с хвостиком к маскоту. Сверху — категория: иконка и заголовок, ниже — суть, чуть мельче и светлее.
/// Чёрная заливка с тонким краем и Geist — тот же язык, что у Пульта.
struct BubbleView: View {
    static let maxWidth: CGFloat = 220
    nonisolated static let tailSize: CGFloat = 5

    let message: BubbleMessage
    let tailOnRight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                CategoryIcon(category: message.category)
                Text(message.title)
                    .font(ConsoleStyle.font(13, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let when = message.when {
                    Text(when)
                        .font(ConsoleStyle.font(11))
                        .foregroundStyle(ConsoleStyle.caption)
                        .lineLimit(1)
                }
            }
            Text(message.text)
                .font(ConsoleStyle.font(13))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .padding(tailOnRight ? .trailing : .leading, Self.tailSize)
        .background(
            BubbleShape(tailOnRight: tailOnRight)
                .fill(.black)
                .overlay { BubbleShape(tailOnRight: tailOnRight).stroke(ConsoleStyle.edge, lineWidth: 1) }
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        )
        .frame(maxWidth: Self.maxWidth, alignment: tailOnRight ? .trailing : .leading)
    }
}

/// Иконка категории: у работы агента — значок самого приложения, у остальных — Solar Bold в цвете категории.
struct CategoryIcon: View {
    let category: BubbleCategory
    static let size: CGFloat = 15

    var body: some View {
        if let app = Self.appIcon(category.appBundleId) {
            Image(nsImage: app)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.size + 2, height: Self.size + 2)
        } else if let icon = SolarIcons.image(category.icon) {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Self.readable(category.color))
                .frame(width: Self.size, height: Self.size)
        }
    }

    /// Тёмные цвета категорий на чёрном не читаются: они светлеют, сохраняя оттенок.
    static func readable(_ hex: UInt32) -> Color {
        let (red, green, blue) = (Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
        let light = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
        guard light < 0.35 else { return Color(hex: hex) }
        let mix = 0.55
        return Color(.sRGB, red: (red + (255 - red) * mix) / 255, green: (green + (255 - green) * mix) / 255, blue: (blue + (255 - blue) * mix) / 255)
    }

    @MainActor private static var appIcons: [String: NSImage] = [:]

    @MainActor static func appIcon(_ bundleId: String?) -> NSImage? {
        guard let bundleId else { return nil }
        if let cached = appIcons[bundleId] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundleId] = icon
        return icon
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, opacity: 1
        )
    }
}

struct BubbleShape: Shape {
    let tailOnRight: Bool

    func path(in rect: CGRect) -> Path {
        let tail = BubbleView.tailSize
        let body = tailOnRight
            ? CGRect(x: rect.minX, y: rect.minY, width: rect.width - tail, height: rect.height)
            : CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height)
        var path = Path(roundedRect: body, cornerRadius: min(14, body.height / 2), style: .continuous)
        let midY = rect.midY
        if tailOnRight {
            path.move(to: CGPoint(x: body.maxX - 1, y: midY - 4))
            path.addLine(to: CGPoint(x: rect.maxX, y: midY))
            path.addLine(to: CGPoint(x: body.maxX - 1, y: midY + 4))
        } else {
            path.move(to: CGPoint(x: body.minX + 1, y: midY - 4))
            path.addLine(to: CGPoint(x: rect.minX, y: midY))
            path.addLine(to: CGPoint(x: body.minX + 1, y: midY + 4))
        }
        path.closeSubpath()
        return path
    }
}
