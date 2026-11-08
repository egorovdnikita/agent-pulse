import AgentPulseCore
import AppKit
import CoreText
import SwiftUI

/// Токены обновлённого макета Пульта.
enum ConsoleStyle {
    static let green = Color(hex: 0x22C55E)
    static let yellow = Color(hex: 0xF59E0B)
    static let red = Color(hex: 0xEF4444)
    static let orange = Color(hex: 0xF59E0B)
    static let blue = Color(hex: 0x0EA5E9)
    /// Акцент, когда над Пультом несут файл.
    static let dropAccent = Color.white.opacity(0.7)

    static let text = Color(hex: 0xFAFAFA)
    static let surface = Color(hex: 0x0A0A0A)
    static let subtle = Color(hex: 0x737373)
    static let accent = Color(hex: 0x7279F5)
    static let selection = Color(hex: 0x373375)
    static let caption = Color(hex: 0xA3A3A3)
    /// Приглушённый значок: та же яркость, что у подписи.
    static let iconOpacity = 0x8C / 255.0
    /// Дорожки ползунков из макета.
    static let track = Color(hex: 0x262626)
    /// Дорожка шкалы спокойнее: это фон, главное в шкале — дуга и число.
    static let gaugeTrack = Color(hex: 0x262626)
    static let card = Color(hex: 0x171717)
    static let button = Color(hex: 0x737373).opacity(0.24)
    /// Плитка файла.
    static let tile = card
    /// Край на тёмных обоях: у референса чёрное сливается со шторкой, Пульту сливаться не с чем.
    static let edge = Color.white.opacity(0.07)

    /// Отступ страницы от края панели и радиусы: внутренний и внешний концентричны.
    static let inset = 8.0
    static let cardRadius = 20.0
    static let surfaceRadius = 24.0
    static let cardPadding = 12.0
    static let cardGap = 12.0
    static let cardHeader = 22.0

    static let gaugeSize = 120.0
    static let gaugeLine = 6.0
    static let gaugeInset = 4.776

    /// Открытие с лёгкой отдачей, закрытие без перелёта.
    static func motion(opening: Bool, reduced: Bool) -> Animation {
        if reduced { return .easeInOut(duration: 0.15) }
        return opening ? .spring(response: 0.42, dampingFraction: 0.8) : .spring(response: 0.45, dampingFraction: 1)
    }

    /// Панель: открытие с лёгкой отдачей, закрытие быстрое: на выходе ждать нечего.
    static func panelMotion(opening: Bool, reduced: Bool) -> Animation {
        if reduced { return .easeInOut(duration: 0.15) }
        return opening ? .spring(response: 0.42, dampingFraction: 0.8) : .spring(response: 0.45, dampingFraction: 1)
    }

    /// Смена страницы.
    static func pageMotion(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.24)
    }

    /// Содержимое отстаёт от формы на такт: форма открывает его, а не пустоту.
    static func contentMotion(appearing: Bool, reduced: Bool) -> Animation {
        if reduced { return .easeInOut(duration: 0.15) }
        return appearing ? .easeOut(duration: 0.22).delay(0.06) : .easeIn(duration: 0.1)
    }

    static func font(_ size: Double, _ weight: Font.Weight = .regular) -> Font {
        let name = weight == .semibold ? "SemiBold" : weight == .bold ? "Bold" : weight == .medium ? "Medium" : "Regular"
        return Font.custom("PulseSans-" + name, fixedSize: size)
    }

    static func nsFont(_ size: Double, _ weight: NSFont.Weight = .regular) -> NSFont {
        let name = weight == .semibold ? "SemiBold" : weight == .bold ? "Bold" : weight == .medium ? "Medium" : "Regular"
        return NSFont(name: "PulseSans-" + name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func registerFont() {
        for name in ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold", "Coolvetica"] {
            if let url = Bundle.main.url(forResource: name, withExtension: name == "Coolvetica" ? "otf" : "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    /// Цвет шкалы по зоне: как у светофора, сервис виден по значку.
    static func color(_ zone: LimitZone) -> Color {
        switch zone {
        case .normal: green
        case .attention: yellow
        case .critical, .exhausted: red
        }
    }
}

/// Значок сервиса: одного размера, чтобы строки не прыгали.
struct ServiceMark: View {
    let service: LimitService
    var size = 15.0

    @MainActor private static let openAI: NSImage = {
        let image = Bundle.main.url(forResource: "OpenAIBlossom", withExtension: "svg").flatMap(NSImage.init(contentsOf:)) ?? NSImage()
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Group {
            switch service {
            case .claude:
                ConsoleAsset(name: "claude", width: size, height: size * 18 / 17)
            case .codex:
                Image(nsImage: Self.openAI).renderingMode(.template).resizable().scaledToFit().foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Открытая дуга на 270°, снизу слева по часовой. Исчерпано — вся дорожка красная.
struct LimitGauge: View {
    let reading: LimitReading?
    let kind: LimitWindowKind
    let now: Date

    var body: some View {
        let used = reading.map { min(1, Double($0.usedPercent) / 100) }
        ZStack {
            arc(to: 1).stroke(ConsoleStyle.gaugeTrack, style: stroke)
            if let reading, let used, used > 0 {
                arc(to: used).stroke(ConsoleStyle.color(reading.zone), style: stroke)
                    .opacity(reading.stale ? 0.45 : 1)
            }
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text(reading.map { "\($0.usedPercent)%" } ?? "—")
                        .font(ConsoleStyle.font(20, .semibold))
                        .foregroundStyle(reading == nil ? ConsoleStyle.caption : ConsoleStyle.text)
                        .frame(height: 24)
                    Text(kind.title)
                        .font(ConsoleStyle.font(12, .medium))
                        .foregroundStyle(ConsoleStyle.caption)
                        .frame(height: 16)
                }
                Text(bottom)
                    .font(ConsoleStyle.font(12, .medium))
                    .foregroundStyle(ConsoleStyle.caption)
                    .lineLimit(1)
                    .frame(height: 16)
            }
            .padding(.top, 12)
        }
        .frame(width: ConsoleStyle.gaugeSize, height: ConsoleStyle.gaugeSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title): \(reading.map { "использовано \($0.usedPercent)%" } ?? LimitText.noData)")
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: ConsoleStyle.gaugeLine, lineCap: .round) }

    private var bottom: String {
        guard let reading else { return "—" }
        return LimitText.gaugeReset(reading, now: now)
    }

    private func arc(to fraction: Double) -> some Shape {
        Circle()
            .inset(by: ConsoleStyle.gaugeInset)
            .trim(from: 0, to: 0.75 * min(max(fraction, 0), 1))
            .rotation(.degrees(135))
    }
}

/// Отклик кнопки: под курсором ярче, при нажатии чуть сжимается.
struct ConsolePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ConsolePressBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct ConsolePressBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    // Обычный @State без Xcode недоступен: его макрос лежит только там.
    private let hovering = State(initialValue: false)

    init(label: Label, pressed: Bool) {
        self.label = label
        self.pressed = pressed
    }

    var body: some View {
        label
            .brightness(hovering.wrappedValue ? 0.08 : 0)
            .scaleEffect(pressed ? 0.94 : 1)
            .opacity(pressed ? 0.75 : 1)
            .onHover { hovering.wrappedValue = $0 }
            .animation(.easeOut(duration: 0.1), value: pressed)
            .animation(.easeOut(duration: 0.12), value: hovering.wrappedValue)
    }
}

/// Пусто: что здесь будет и что сделать.
struct ConsoleEmpty: View {
    let icon: String
    let title: String
    var hint: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: SolarIcons.image(icon) ?? NSImage())
                .resizable()
                .frame(width: 22, height: 22)
                .foregroundStyle(ConsoleStyle.caption)
            Text(title).font(ConsoleStyle.font(15, .medium)).foregroundStyle(.white)
            if let hint {
                Text(hint)
                    .font(ConsoleStyle.font(11))
                    .foregroundStyle(ConsoleStyle.caption)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Переключатель в капсуле.
struct ConsoleSegments<Value: Hashable>: View {
    let values: [Value]
    let selected: Value
    let title: (Value) -> String
    let select: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                Button { select(value) } label: {
                    Text(title(value))
                        .font(ConsoleStyle.font(13, .medium))
                        .foregroundStyle(value == selected ? .white : ConsoleStyle.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(value == selected ? ConsoleStyle.button : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(ConsolePressStyle())
            }
        }
        .padding(2)
        .background(ConsoleStyle.card, in: Capsule())
    }
}

/// Карточка: подложка всех страниц.
extension View {
    /// Тень всех чёрных форм, что парят над рабочим столом.
    func consoleShadow() -> some View {
        shadow(color: .black.opacity(0.45), radius: 12, y: 4)
    }
}

struct ConsoleCard<Content: View>: View {
    var fills = true
    var padding = ConsoleStyle.cardPadding
    var radius = ConsoleStyle.cardRadius
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
            .background(ConsoleStyle.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Тонкий ползунок: перемотка и громкость.
struct ThinSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let label: String
    /// Команда уходит при отпускании: плеер не должен дёргаться от каждого движения мыши.
    let commitsOnEnd: Bool
    let onChange: (Double) -> Void
    // Обычный @State без Xcode недоступен: его макрос лежит только там.
    private let dragged = State<Double?>(initialValue: nil)

    init(value: Double, range: ClosedRange<Double>, label: String, commitsOnEnd: Bool = false, onChange: @escaping (Double) -> Void) {
        self.value = value
        self.range = range
        self.label = label
        self.commitsOnEnd = commitsOnEnd
        self.onChange = onChange
    }

    private var span: Double { max(range.upperBound - range.lowerBound, 0.001) }

    private var share: Double {
        min(1, max(0, ((dragged.wrappedValue ?? value) - range.lowerBound) / span))
    }

    var body: some View {
        GeometryReader { space in
            ZStack(alignment: .leading) {
                Capsule().fill(ConsoleStyle.track)
                Capsule().fill(ConsoleStyle.accent).frame(width: max(4, space.size.width * share))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let place = range.lowerBound + span * min(1, max(0, drag.location.x / max(space.size.width, 1)))
                        dragged.wrappedValue = place
                        if !commitsOnEnd { onChange(place) }
                    }
                    .onEnded { _ in
                        if commitsOnEnd, let place = dragged.wrappedValue { onChange(place) }
                        dragged.wrappedValue = nil
                    }
            )
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(share * 100))%")
        .accessibilityAdjustableAction { direction in
            let step = span / 20
            switch direction {
            case .increment: onChange(min(range.upperBound, value + step))
            case .decrement: onChange(max(range.lowerBound, value - step))
            @unknown default: break
            }
        }
    }
}

/// Отрисовка Пульта в файлы: `--console-sheet папка`. Окна не показываются, проверять можно при любом экране.
@MainActor
enum ConsoleSheet {
    static func render(_ model: ConsoleModel, app: AppDelegate, to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        write(CapsulePreview(model: model), size: CGSize(width: model.capsuleWidth + 16, height: 48), to: folder.appending(path: "capsule.png"))
        model.showPanelNow()
        let panel = CGSize(width: ConsoleLayout.expandedWidth + 16, height: ConsoleLayout.expandedHeight + 16)
        for tab in model.tabs {
            model.tab = tab.id
            write(PanelPreview(model: model), size: panel, to: folder.appending(path: "\(tab.id.rawValue).png"))
        }
        // Выделенные файлы.
        model.tab = .shelf
        model.selectAllShelf()
        write(PanelPreview(model: model), size: panel, to: folder.appending(path: "shelf-selected.png"))
        model.clearShelfSelection()


        // Перевод: четыре страницы Пульта.
        if let text = model.pressTranslate(selection: "Привет, это проверка перевода", clipboard: nil) {
            model.finishTranslate(source: text, result: .success("Hello, this is a translation check"))
            model.showPanelNow()
            write(PanelPreview(model: model), size: panel, to: folder.appending(path: "translate.png"))
        }
        model.showPanelNow()

        // Суфлёр идёт: текст запоминается, поэтому сразу забывается.
        let draft = model.prompterDraft
        model.setPrompterFollowsVoice(false)
        model.startPrompter()
        if model.prompter.isActive {
            model.showPanelNow()
            model.tab = .prompter
            write(PanelPreview(model: model), size: panel, to: folder.appending(path: "prompter-running.png"))
            model.stopPrompter()
            model.forgetPrompterText(draft)
        }

        // Пустые страницы.
        model.showPanelNow()
        model.clearShelf()
        for tab in [ConsoleModuleID.shelf] {
            model.tab = tab
            write(PanelPreview(model: model), size: panel, to: folder.appending(path: "\(tab.rawValue)-empty.png"))
        }
    }

    static func renderCapsule(_ model: ConsoleModel, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        write(CapsulePreview(model: model), size: CGSize(width: model.capsuleWidth + 16, height: 48), to: url)
    }

    static func renderStress(_ model: ConsoleModel, to folder: URL) {
        model.showPanelNow()
        let panel = CGSize(width: ConsoleLayout.expandedWidth + 16, height: ConsoleLayout.expandedHeight + 16)
        for tab in model.tabs {
            model.tab = tab.id
            write(PanelPreview(model: model), size: panel, to: folder.appending(path: "stress-\(tab.id.rawValue).png"))
        }
    }

    static func checkPrompterValidation(to folder: URL) async {
        let model = ConsoleModel()
        model.showPanelNow()
        model.tab = .prompter
        model.prompterDraft = "   \n"
        model.startPrompterDraft()
        precondition(model.prompterInputInvalid && !model.prompter.isActive)
        let panel = CGSize(width: ConsoleLayout.expandedWidth + 16, height: ConsoleLayout.expandedHeight + 16)
        write(PanelPreview(model: model), size: panel, to: folder.appending(path: "prompter-validation.png"))
        try? await Task.sleep(for: .milliseconds(600))
        model.startPrompterDraft()
        try? await Task.sleep(for: .milliseconds(600))
        precondition(model.prompterInputInvalid && !model.prompter.isActive)
        try? await Task.sleep(for: .milliseconds(500))
        precondition(!model.prompterInputInvalid && !model.prompter.isActive)
        write(PanelPreview(model: model), size: panel, to: folder.appending(path: "prompter-validation-cleared.png"))
        print("Prompter validation: passed (empty draft, repeated click, one-second reset)")
    }

    private static func write(_ view: some View, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(white: 0.32)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
