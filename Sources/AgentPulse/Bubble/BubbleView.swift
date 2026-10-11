import SwiftUI

/// Пузырь с хвостиком к маскоту. Белая заливка, чёрный текст, мягкая тёмная тень — палитра маскота.
struct BubbleView: View {
    static let maxWidth: CGFloat = 200
    nonisolated static let tailSize: CGFloat = 5

    let text: String
    let tailOnRight: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.black)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 22)
            .padding(tailOnRight ? .trailing : .leading, Self.tailSize)
            .background(
                BubbleShape(tailOnRight: tailOnRight)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4)
            )
            .frame(maxWidth: Self.maxWidth, alignment: tailOnRight ? .trailing : .leading)
    }
}

struct BubbleShape: Shape {
    let tailOnRight: Bool

    func path(in rect: CGRect) -> Path {
        let tail = BubbleView.tailSize
        let body = tailOnRight
            ? CGRect(x: rect.minX, y: rect.minY, width: rect.width - tail, height: rect.height)
            : CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height)
        var path = Path(roundedRect: body, cornerRadius: min(11, body.height / 2), style: .continuous)
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
