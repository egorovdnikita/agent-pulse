import AgentPulseCore
import SwiftUI

/// Сценарии: клип бота и облачко — как это выглядит на экране в настоящей ситуации.
/// Реплики берутся из тех же пулов (`Phrases`), заголовки и иконки — из тех же категорий, что у живого маскота.
struct PalGallery: View {
    let skin: PalSkin

    struct Scenario: Identifiable {
        let id: String
        let clip: PalClip
        let message: BubbleMessage?
    }

    /// Реплика-пример: первая из пула.
    private static func line(_ trigger: BubbleTrigger) -> String {
        Phrases.pool(for: trigger).first ?? ""
    }

    private static func agent(_ source: AgentEvent.Source, host: String? = nil, _ trigger: BubbleTrigger) -> BubbleMessage {
        BubbleMessage(
            category: BubbleCategory.agent(source, host: host),
            title: BubbleCategory.agentTitle(source, host: host),
            text: line(trigger)
        )
    }

    private static func plain(_ category: BubbleCategory, _ text: String) -> BubbleMessage {
        BubbleMessage(category: category, title: category.title, text: text)
    }

    /// По порядку, как обычно идёт день: задача от начала до итога, потом самочувствие и отдых.
    static let scenarios: [Scenario] = [
        Scenario(id: "Ты дал задачу в Orca", clip: .thinking, message: agent(.claudeCode, host: OrcaStatus.hostBundleId, .notice)),
        Scenario(id: "Думает над ответом", clip: .thinking, message: agent(.claudeCode, .think)),
        Scenario(id: "Читает файлы", clip: .reading, message: agent(.claudeCode, .workRead)),
        Scenario(id: "Ищет по проекту", clip: .searching, message: agent(.codex, .workSearch)),
        Scenario(id: "Правит код", clip: .coding, message: agent(.claudeCode, host: OrcaStatus.hostBundleId, .workEditCode)),
        Scenario(id: "Рисует в Figma", clip: .designing, message: agent(.figmaMCP, .workEditFigma)),
        Scenario(id: "Запускает команды", clip: .typing, message: agent(.codex, .workRun)),
        Scenario(id: "Долгая задача, раз в 15 мин", clip: .working,
                 message: BubbleMessage(category: .claude, title: "Claude Code", text: "Ещё работаю, уже 14 мин")),
        Scenario(id: "Просит разрешения — громче всего", clip: .listening, message: agent(.codex, .waitPermission)),
        Scenario(id: "Ждёт твоего ответа", clip: .listening, message: agent(.claudeCode, host: OrcaStatus.hostBundleId, .waitInput)),
        Scenario(id: "Задача готова", clip: .done, message: agent(.claudeCode, .done)),
        Scenario(id: "Не получилось", clip: .error, message: agent(.codex, .error)),
        Scenario(id: "Наведение курсора в работе", clip: .working,
                 message: BubbleMessage(category: .orca, title: "Orca", text: "Работаю 12 мин, сделано 8 шагов")),
        Scenario(id: "Батарея меньше 20%", clip: .idle, message: plain(.battery, "Есть хочу")),
        Scenario(id: "Ноутбук перегрелся", clip: .idle, message: plain(.wellbeing, "Мне жарко…")),
        Scenario(id: "Утро, первое появление", clip: .idle, message: plain(.day, "Привет")),
        Scenario(id: "Все отдыхают — засыпает", clip: .sleeping, message: plain(.rest, line(.fallAsleep))),
        Scenario(id: "Сон: облачко молчит", clip: .sleeping, message: nil),
    ]

    var diameter: Double = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.scenarios) { scenario in
                VStack(alignment: .leading, spacing: 4) {
                    Text(scenario.id).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    DesktopScene(skin: skin, clip: scenario.clip, message: scenario.message, diameter: diameter)
                }
            }
        }
        .padding(.vertical, 4)
        .id(skin.bot)
    }
}

/// Угол экрана, как он выглядит у тебя: низ окна со строкой состояния, край Dock с Orca и Корзиной,
/// чёрный рабочий стол, справа маскот и облачко. Размеры и цвета сняты со скриншота (pt = px / 2),
/// сцена 570×255 pt вписывается в ширину карточки целиком, без искажений.
private struct DesktopScene: View {
    let skin: PalSkin
    let clip: PalClip
    let message: BubbleMessage?
    let diameter: Double

    static let size = CGSize(width: 570, height: 255)
    static let mascot = CGPoint(x: 511.5, y: 196.75)

    var body: some View {
        Color.clear
            .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    let scale = proxy.size.width / Self.size.width
                    scene
                        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
                        .scaleEffect(scale, anchor: .topLeading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private static func gray(_ value: Int) -> Color {
        Color(red: Double(value) / 255, green: Double(value) / 255, blue: Double(value) / 255)
    }

    /// Снимок угла экрана владельца (`Resources/Scenes/DeskCorner.png`, 1140×510 px = сцена @2x),
    /// свой маскот на нём закрашен. Нет снимка — фон рисуется по замерам ниже.
    private static let backdrop: NSImage? = Bundle.main.url(forResource: "DeskCorner", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    private var scene: some View {
        ZStack(alignment: .topLeading) {
            if let backdrop = Self.backdrop {
                Image(nsImage: backdrop).resizable().interpolation(.high)
                    .frame(width: Self.size.width, height: Self.size.height)
            } else {
                drawnBackdrop
            }

            // Облачко: хвостик в 8 pt от тела, по центру маскота — как в оверлее.
            if let message {
                BubbleView(message: message, tailOnRight: true)
                    .frame(width: Self.mascot.x - diameter / 2 - 8, height: Self.mascot.y * 2, alignment: .trailing)
            }
            PalClipView(skin: skin, clip: clip)
                .frame(width: diameter * 2, height: diameter * 2)
                .position(Self.mascot)
        }
    }

    private var drawnBackdrop: some View {
        ZStack(alignment: .topLeading) {
            Color.black

            // Окно: кромка #454545, тело #171717, радиус 12 pt справа снизу; левый край за кадром.
            UnevenRoundedRectangle(bottomTrailingRadius: 12, style: .continuous)
                .fill(Self.gray(0x45))
                .frame(width: 589.5, height: 148)
                .offset(x: -20)
            UnevenRoundedRectangle(bottomTrailingRadius: 11, style: .continuous)
                .fill(Self.gray(0x17))
                .frame(width: 588.5, height: 147)
                .offset(x: -20)
            // Левая панель #101010 до разделителя строки состояния; линии контента #888.
            Rectangle().fill(Self.gray(0x10)).frame(width: 350, height: 124)
            Rectangle().fill(Self.gray(0x88)).frame(width: 343, height: 1).offset(y: 51.5)
            Rectangle().fill(Self.gray(0x88)).frame(width: 343, height: 1).offset(y: 83.5)
            Rectangle().fill(Self.gray(0x27)).frame(width: 1, height: 124).offset(x: 350)
            Rectangle().fill(Self.gray(0x27)).frame(width: 569.5, height: 1).offset(y: 124)

            // Dock: #0b0b0b с рамкой, радиус 27.5 pt; левый край за кадром.
            RoundedRectangle(cornerRadius: 27.5, style: .continuous)
                .fill(Self.gray(0x0B))
                .overlay(RoundedRectangle(cornerRadius: 27.5, style: .continuous).strokeBorder(Self.gray(0x30), lineWidth: 1))
                .frame(width: 264.5, height: 100.5)
                .offset(x: -40, y: 149)
            Rectangle().fill(Self.gray(0x30)).frame(width: 1, height: 74.5).offset(x: 113, y: 162)
            icon(Self.orcaIcon, center: CGPoint(x: 50.25, y: 199.25))
            Circle().fill(Self.gray(0x87)).frame(width: 4, height: 4).position(x: 49.75, y: 243.75)
            icon(Self.trashIcon, center: CGPoint(x: 174.25, y: 200.5))
        }
    }

    /// Значок Dock: рисунок 65.5 pt, у системных значков он занимает ~80.5% холста.
    private func icon(_ image: NSImage?, center: CGPoint) -> some View {
        let side = 65.5 / 0.805
        return Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            }
        }
        .frame(width: side, height: side)
        .position(center)
    }

    /// Светлая стеклянная корзина, как в Dock; `NSImage.trashEmptyName` — тёмная и не та.
    private static let trashIcon: NSImage? =
        NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns")
            ?? NSImage(named: NSImage.trashEmptyName)

    private static let orcaIcon: NSImage? = NSWorkspace.shared.urlForApplication(withBundleIdentifier: OrcaStatus.hostBundleId)
        .map { NSWorkspace.shared.icon(forFile: $0.path) }
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
