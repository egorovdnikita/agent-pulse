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

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Self.scenarios) { scenario in
                VStack(alignment: .leading, spacing: 4) {
                    Text(scenario.id).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    // Хвостик в 8 pt от тела, как на экране: клетка 96, тело — половина, поле по 24 pt.
                    HStack(spacing: -16) {
                        Spacer(minLength: 0)
                        if let message = scenario.message {
                            BubbleView(message: message, tailOnRight: true)
                        }
                        PalClipView(skin: skin, clip: scenario.clip)
                            .frame(width: 96, height: 96)
                    }
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
