import SwiftUI

/// Упрощённое зеркало Figma: последний кадр фрейма, который меняет агент.
struct MirrorView: View {
    static let maxSize = CGSize(width: 200, height: 150)

    let frame: MirrorFrame

    var body: some View {
        Image(nsImage: frame.image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: Self.maxSize.width, maxHeight: Self.maxSize.height)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 6)
            .help(frame.node.isEmpty ? frame.file : "\(frame.file) · \(frame.node)")
    }
}
