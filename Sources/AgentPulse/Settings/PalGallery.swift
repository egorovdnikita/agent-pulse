import AgentPulseCore
import SwiftUI

/// Сценарии: клип бота и облачко — как это выглядит на экране в настоящей ситуации.
/// Реплики берутся из тех же пулов (`Phrases`), заголовки и иконки — из тех же категорий, что у живого маскота.
struct PalGallery: View {
    let skin: PalSkin

    /// Ситуация: состояние маскота, реакция тела (повторяется по кругу) и облачко.
    /// Движения — настоящий `MascotAnimator`: дыхание, покачивание, прыжки, вздрагивания, как у живого маскота.
    struct Scenario: Identifiable {
        let id: String
        let state: MascotState
        var target: WorkTarget? = nil
        var reaction: MascotReaction? = nil
        var hovered = false
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
        Scenario(id: "Ты дал задачу в Orca", state: .think, reaction: .notice,
                 message: agent(.claudeCode, host: OrcaStatus.hostBundleId, .notice)),
        Scenario(id: "Думает над ответом", state: .think, message: agent(.claudeCode, .think)),
        Scenario(id: "Читает файлы", state: .work(.read), target: .code, message: agent(.claudeCode, .workRead)),
        Scenario(id: "Ищет по проекту", state: .work(.search), target: .code, message: agent(.codex, .workSearch)),
        Scenario(id: "Правит код", state: .work(.edit), target: .code,
                 message: agent(.claudeCode, host: OrcaStatus.hostBundleId, .workEditCode)),
        Scenario(id: "Рисует в Figma", state: .work(.edit), target: .figma, message: agent(.figmaMCP, .workEditFigma)),
        Scenario(id: "Запускает команды", state: .work(.run), target: .code, message: agent(.codex, .workRun)),
        Scenario(id: "Долгая задача, раз в 15 мин", state: .work(.general), reaction: .yawn,
                 message: BubbleMessage(category: .claude, title: "Claude Code", text: "Ещё работаю, уже 14 мин")),
        Scenario(id: "Просит разрешения — громче всего", state: .waitYou(.permission), message: agent(.codex, .waitPermission)),
        Scenario(id: "Ждёт твоего ответа", state: .waitYou(.input),
                 message: agent(.claudeCode, host: OrcaStatus.hostBundleId, .waitInput)),
        Scenario(id: "Задача готова", state: .idle, reaction: .done, message: agent(.claudeCode, .done)),
        Scenario(id: "Не получилось", state: .idle, reaction: .error, message: agent(.codex, .error)),
        Scenario(id: "Наведение курсора в работе", state: .work(.general), hovered: true,
                 message: BubbleMessage(category: .orca, title: "Orca", text: "Работаю 12 мин, сделано 8 шагов")),
        Scenario(id: "Батарея меньше 20%", state: .idle, reaction: .slowClose, message: plain(.battery, "Есть хочу")),
        Scenario(id: "Ноутбук перегрелся", state: .idle, reaction: .fastBlink, message: plain(.wellbeing, "Мне жарко…")),
        Scenario(id: "Утро, первое появление", state: .idle, reaction: .notice, message: plain(.day, "Привет")),
        Scenario(id: "Все отдыхают — засыпает", state: .sleep, message: plain(.rest, line(.fallAsleep))),
        Scenario(id: "Сон: облачко молчит", state: .sleep, message: nil),
    ]

    var diameter: Double = 52

    var body: some View {
        // Ленивый список: живые маскоты есть только у карточек на экране.
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Self.scenarios) { scenario in
                VStack(alignment: .leading, spacing: 4) {
                    Text(scenario.id).font(ConsoleStyle.font(11, .semibold)).foregroundStyle(.secondary)
                    DesktopScene(skin: skin, scenario: scenario, diameter: diameter)
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
    let scenario: PalGallery.Scenario
    let diameter: Double

    private var message: BubbleMessage? { scenario.message }

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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            ScenarioMascot(skin: skin, scenario: scenario, diameter: diameter)
                .frame(width: MascotView.boxSize(diameter), height: MascotView.boxSize(diameter))
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

/// Живой маскот сценария: свой аниматор в нужном состоянии, реакция повторяется по кругу —
/// те же движения тела (дыхание, покачивание, прыжки, вздрагивания), что у маскота на экране.
/// Аниматор живёт в самом виде: SwiftUI пересоздаёт описание карточки, а маскот остаётся тем же.
private struct ScenarioMascot: NSViewRepresentable {
    let skin: PalSkin
    let scenario: PalGallery.Scenario
    let diameter: Double

    func makeNSView(context: Context) -> ScenarioMascotView {
        ScenarioMascotView(skin: skin, scenario: scenario, diameter: diameter)
    }

    func updateNSView(_ view: ScenarioMascotView, context: Context) {}

    static func dismantleNSView(_ view: ScenarioMascotView, coordinator: ()) {
        view.stop()
    }
}

@MainActor
private final class ScenarioMascotView: NSView {
    private let animator = MascotAnimator()
    private let mascot: MascotLayerView
    private var timer: Timer?

    init(skin: PalSkin, scenario: PalGallery.Scenario, diameter: Double) {
        mascot = MascotLayerView(animator: animator, diameter: diameter)
        super.init(frame: .zero)
        mascot.autoresizingMask = [.width, .height]
        addSubview(mascot)

        animator.skin = skin
        animator.workTarget = scenario.target
        animator.hovered = scenario.hovered
        // Облачко висит — маскот говорит и не спит; «Вздремну» — исключение, как в оверлее.
        animator.speaking = scenario.message.map { $0.category != .rest } ?? false
        animator.setState(scenario.state, at: Date.timeIntervalSinceReferenceDate)

        guard let reaction = scenario.reaction else { return }
        animator.enqueue(reaction)
        // Итог держит свой клип две петли (4.8 s) — повторяем чуть реже.
        let period = reaction == .done || reaction == .error ? 6.5 : 4.5
        timer = Timer.scheduledTimer(withTimeInterval: period, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.animator.enqueue(reaction) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        mascot.frame = bounds
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
