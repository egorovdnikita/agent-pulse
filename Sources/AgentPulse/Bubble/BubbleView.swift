import AppKit
import AgentPulseCore
import SwiftUI

/// Пузырь с хвостиком к маскоту. Сверху — категория: иконка и заголовок, ниже — суть, чуть мельче и светлее.
/// Белая заливка, мягкая тёмная тень — палитра маскота.
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
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let when = message.when {
                    Text(when)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.black.opacity(0.4))
                        .lineLimit(1)
                }
            }
            Text(message.text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.black.opacity(0.6))
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .padding(tailOnRight ? .trailing : .leading, Self.tailSize)
        .background(
            BubbleShape(tailOnRight: tailOnRight)
                .fill(.white)
                .shadow(color: .black.opacity(0.25), radius: 4)
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
                .foregroundStyle(Color(hex: category.color))
                .frame(width: Self.size, height: Self.size)
        }
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
        var path = Path(roundedRect: body, cornerRadius: min(12, body.height / 2), style: .continuous)
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
