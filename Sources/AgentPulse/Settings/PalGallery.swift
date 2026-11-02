import AgentPulseCore
import SwiftUI

/// Все 13 клипов выбранного бота сразу, по кругу — посмотреть облик целиком.
/// Подписи — когда маскот играет этот клип (правила — `PalChoreographer`).
struct PalGallery: View {
    let skin: PalSkin

    private static let captions: [PalClip: String] = [
        .idle: "Покой", .sleeping: "Сон", .thinking: "Думает", .listening: "Ждёт тебя",
        .reading: "Читает", .searching: "Ищет", .typing: "Запускает", .coding: "Правит код",
        .designing: "Рисует в Figma", .working: "Прочая работа", .writing: "Пока не используется",
        .done: "Готово", .error: "Ошибка",
    ]
    /// Порядок — как обычно идёт задача: от покоя к итогу.
    private static let order: [PalClip] = [
        .idle, .sleeping, .thinking, .reading, .searching, .coding, .designing, .typing, .working,
        .listening, .done, .error, .writing,
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
            ForEach(Self.order, id: \.self) { clip in
                VStack(spacing: 2) {
                    PalClipView(skin: skin, clip: clip)
                        .frame(width: 88, height: 88)
                        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(clip.rawValue).font(.caption.weight(.semibold))
                    Text(Self.captions[clip] ?? "").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .id(skin.bot)
    }
}

/// Один клип в петле. Галерея живёт, только пока открыто окно настроек.
/// Рисует тот же `PalLayer`, что и маскот: `LottieAnimationView` на macOS не вписывает клип в свой размер.
private struct PalClipView: NSViewRepresentable {
    let skin: PalSkin
    let clip: PalClip

    func makeNSView(context: Context) -> PalClipNSView {
        PalClipNSView(skin: skin, clip: clip)
    }

    func updateNSView(_ view: PalClipNSView, context: Context) {}
}

@MainActor
private final class PalClipNSView: NSView {
    private let pal = PalLayer()

    init(skin: PalSkin, clip: PalClip) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(pal)
        pal.use(skin)
        pal.show(clip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Тело бота — половина клетки, как маскот на своём холсте.
        let scale = bounds.width * 0.5 / (PalLayer.canvas * PalLayer.bodyShare)
        pal.position = CGPoint(x: bounds.midX, y: bounds.midY)
        // Слой вида не перевёрнут, в отличие от холста маскота: Lottie здесь рисует вверх ногами.
        pal.transform = CATransform3DMakeScale(scale, -scale, 1)
        CATransaction.commit()
    }
}
