import AgentPulseCore
import AppKit
import CoreText
import SwiftUI

/// Язык Пульта: чёрная поверхность, карточки, дуговые шкалы и точки-страницы. Значения сняты с CapaTheNotch (MIT).
enum ConsoleStyle {
    static let green = Color(hex: 0x30D158)
    static let yellow = Color(hex: 0xFFD60A)
    static let red = Color(hex: 0xFF453A)
    static let orange = Color(hex: 0xFF9F0A)

    static let caption = Color.white.opacity(0x8C / 255)
    /// Дорожки ползунков и выключенные переключатели: не меньше 3:1 к карточке.
    static let track = Color.white.opacity(0.32)
    /// Дорожка шкалы спокойнее: это фон, главное в шкале — дуга и число.
    static let gaugeTrack = Color.white.opacity(0x26 / 255)
    static let card = Color.white.opacity(0x14 / 255)
    static let button = Color.white.opacity(0x33 / 255)
    /// Край на тёмных обоях: у референса чёрное сливается со шторкой, Пульту сливаться не с чем.
    static let edge = Color.white.opacity(0.18)

    /// Отступ страницы от края панели и радиусы: внутренний и внешний концентричны.
    static let inset = 12.0
    static let cardRadius = 20.0
    static let surfaceRadius = cardRadius + inset
    static let cardPadding = 14.0

    static let gaugeSize = 96.0
    static let gaugeLine = 7.0

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
        Font.custom("Geist", fixedSize: size).weight(weight)
    }

    /// То же для мест, где текст меряет AppKit. Нет Geist — системный шрифт.
    static func nsFont(_ size: Double, _ weight: NSFont.Weight = .regular) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: "Geist",
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// Шрифт лежит в приложении и виден только ему.
    static func registerFont() {
        guard let url = Bundle.main.url(forResource: "Geist", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
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
                ClaudeMark().foregroundStyle(ConsoleStyle.orange)
            case .codex:
                Image(nsImage: Self.openAI).renderingMode(.template).resizable().scaledToFit().foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Значок Claude: лучи из центра.
private struct ClaudeMark: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.12
        let base = outer * 0.115
        let tip = base * 0.34
        let rays = 11
        var path = Path()
        for index in 0..<rays {
            let angle = Double(index) / Double(rays) * 2 * .pi
            let along = CGVector(dx: cos(angle), dy: sin(angle))
            let across = CGVector(dx: -along.dy, dy: along.dx)
            let point = { (distance: Double, offset: Double) in
                CGPoint(x: center.x + along.dx * distance + across.dx * offset, y: center.y + along.dy * distance + across.dy * offset)
            }
            path.move(to: point(inner, -base))
            path.addLine(to: point(outer, -tip))
            path.addLine(to: point(outer, tip))
            path.addLine(to: point(inner, base))
            path.closeSubpath()
        }
        return path
    }
}

/// Открытая дуга на 270°, снизу слева по часовой. Исчерпано — вся дорожка красная.
struct LimitGauge: View {
    let reading: LimitReading?
    let kind: LimitWindowKind
    let now: Date

    var body: some View {
        let used = reading.map { min(1, Double($0.usedPercent) / 100) }
        let exhausted = reading?.zone == .exhausted
        ZStack {
            arc(to: 1).stroke(exhausted ? ConsoleStyle.red.opacity(0.22) : ConsoleStyle.gaugeTrack, style: stroke)
            if let reading, let used, !exhausted {
                arc(to: used).stroke(ConsoleStyle.color(reading.zone), style: stroke).opacity(reading.stale ? 0.45 : 1)
            }
            VStack(spacing: 0) {
                Text(reading.map { "\($0.usedPercent)%" } ?? "—")
                    .font(ConsoleStyle.font(20, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(exhausted ? ConsoleStyle.red : reading == nil ? ConsoleStyle.caption : .white)
                Text(kind.title)
                    .font(ConsoleStyle.font(11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            VStack {
                Spacer()
                Text(bottom)
                    .font(ConsoleStyle.font(11))
                    .monospacedDigit()
                    .foregroundStyle(exhausted ? ConsoleStyle.red : ConsoleStyle.caption)
                    .lineLimit(1)
            }
        }
        .frame(width: ConsoleStyle.gaugeSize, height: ConsoleStyle.gaugeSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title): \(reading.map { "использовано \($0.usedPercent)%" } ?? LimitText.noData)")
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: ConsoleStyle.gaugeLine, lineCap: .round) }

    private var bottom: String {
        guard let reading else { return "—" }
        return reading.resetsAt.map { LimitText.gaugeReset($0, now: now) } ?? " "
    }

    private func arc(to fraction: Double) -> some Shape {
        Circle()
            .inset(by: ConsoleStyle.gaugeLine / 2)
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
                .frame(width: 28, height: 28)
                .foregroundStyle(ConsoleStyle.caption)
            Text(title).font(ConsoleStyle.font(13, .medium)).foregroundStyle(.white)
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
struct ConsoleCard<Content: View>: View {
    var fills = true
    var padding = ConsoleStyle.cardPadding
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
            .background(ConsoleStyle.card, in: RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius, style: .continuous))
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
                Capsule().fill(.white).frame(width: max(4, space.size.width * share))
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
        for scope in [CalendarScope.week, .month] {
            model.tab = .calendar
            model.calendarScope = scope
            write(PanelPreview(model: model), size: panel, to: folder.appending(path: "calendar-\(scope.rawValue).png"))
        }
        model.calendarScope = .day

        // Меню маскота.
        write(PulseMenuView(app: app) {}, size: CGSize(width: PulseMenuView.width + 16, height: 340), to: folder.appending(path: "menu.png"))

        // Перевод: шесть страниц — самая тесная строка навигации.
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
        model.updateCalendar([])
        for tab in [ConsoleModuleID.shelf, .calendar] {
            model.tab = tab
            write(PanelPreview(model: model), size: panel, to: folder.appending(path: "\(tab.rawValue)-empty.png"))
        }
    }

    static func renderCapsule(_ model: ConsoleModel, to url: URL) {
        write(CapsulePreview(model: model), size: CGSize(width: model.capsuleWidth + 16, height: 48), to: url)
    }

    static func renderStress(_ model: ConsoleModel, to folder: URL) {
        model.showPanelNow()
        let panel = CGSize(width: ConsoleLayout.expandedWidth + 16, height: ConsoleLayout.expandedHeight + 16)
        for tab in model.tabs {
            model.tab = tab.id
            write(PanelPreview(model: model), size: panel, to: folder.appending(path: "stress-\(tab.id.rawValue).png"))
        }
        model.calendarScope = .week
        model.tab = .calendar
        write(PanelPreview(model: model), size: panel, to: folder.appending(path: "stress-week.png"))
    }

    private static func write(_ view: some View, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(white: 0.32)))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
