import AgentPulseCore
import AppKit
import CoreText
import SwiftUI

/// Язык Пульта: чёрная поверхность, карточки, дуговые шкалы и точки-страницы. Значения сняты с CapaTheNotch (MIT).
/// Панель Пульта ниже его шторки, поэтому размеры шкалы — те же пропорции в масштабе 0.82.
enum ConsoleStyle {
    static let green = Color(hex: 0x30D158)
    static let yellow = Color(hex: 0xFFD60A)
    static let red = Color(hex: 0xFF453A)
    static let orange = Color(hex: 0xFF9F0A)

    static let caption = Color.white.opacity(0x8C / 255)
    static let track = Color.white.opacity(0x26 / 255)
    static let card = Color.white.opacity(0x14 / 255)
    static let button = Color.white.opacity(0x33 / 255)
    /// Край на тёмных обоях: у референса чёрное сливается со шторкой, Пульту сливаться не с чем.
    static let edge = Color.white.opacity(0.12)

    /// Отступ страницы от края панели и радиусы: внутренний и внешний концентричны.
    static let inset = 12.0
    static let cardRadius = 20.0
    static let surfaceRadius = cardRadius + inset
    static let cardPadding = 12.0

    static let gaugeSize = 72.0
    static let gaugeLine = 6.0

    /// Открытие с лёгкой отдачей, закрытие без перелёта.
    static func motion(opening: Bool, reduced: Bool) -> Animation {
        if reduced { return .easeInOut(duration: 0.15) }
        return opening ? .spring(response: 0.42, dampingFraction: 0.8) : .spring(response: 0.45, dampingFraction: 1)
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

extension CapsuleRing {
    /// Число в капсуле. Нет данных — прочерк, а не 0%.
    var figure: String {
        fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
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
            arc(to: 1).stroke(exhausted ? ConsoleStyle.red.opacity(0.22) : ConsoleStyle.track, style: stroke)
            if let reading, let used, !exhausted {
                arc(to: used).stroke(ConsoleStyle.color(reading.zone), style: stroke).opacity(reading.stale ? 0.45 : 1)
            }
            VStack(spacing: 0) {
                Text(reading.map { "\($0.usedPercent)%" } ?? "—")
                    .font(ConsoleStyle.font(18, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(exhausted ? ConsoleStyle.red : reading == nil ? ConsoleStyle.caption : .white)
                Text(kind.title)
                    .font(ConsoleStyle.font(10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            VStack {
                Spacer()
                Text(bottom)
                    .font(ConsoleStyle.font(10))
                    .monospacedDigit()
                    .foregroundStyle(exhausted ? ConsoleStyle.red : ConsoleStyle.caption)
                    .lineLimit(1)
            }
        }
        .frame(width: ConsoleStyle.gaugeSize, height: ConsoleStyle.gaugeSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title): \(reading.map { "\($0.usedPercent)%" } ?? LimitText.noData)")
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

/// Карточка: подложка всех страниц.
struct ConsoleCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(ConsoleStyle.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ConsoleStyle.card, in: RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius, style: .continuous))
    }
}

/// Тонкий ползунок: перемотка и громкость.
struct ThinSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let label: String
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { space in
            let span = max(range.upperBound - range.lowerBound, 0.001)
            let fraction = min(1, max(0, (value - range.lowerBound) / span))
            ZStack(alignment: .leading) {
                Capsule().fill(ConsoleStyle.track)
                Capsule().fill(.white).frame(width: max(4, space.size.width * fraction))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(range.lowerBound + span * min(1, max(0, drag.location.x / max(space.size.width, 1))))
            })
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

/// Отрисовка Пульта в файлы: `--console-sheet папка`. Окна не показываются, проверять можно при любом экране.
@MainActor
enum ConsoleSheet {
    static func render(_ model: ConsoleModel, to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        write(CapsulePreview(model: model), size: CGSize(width: model.capsuleWidth + 16, height: 48), to: folder.appending(path: "capsule.png"))
        model.setExpanded(true)
        for width in [ConsoleLayout.expandedMaxWidth, ConsoleLayout.expandedMinWidth] {
            model.expandedWidth = width
            for tab in model.tabs {
                model.tab = tab.id
                write(
                    PanelPreview(model: model),
                    size: CGSize(width: width + 16, height: ConsoleLayout.expandedHeight + 16),
                    to: folder.appending(path: "\(tab.id.rawValue)-\(Int(width)).png")
                )
            }
        }
        model.tab = .limits
        model.pagesHovered = true
        write(
            PanelPreview(model: model),
            size: CGSize(width: ConsoleLayout.expandedMinWidth + 16, height: ConsoleLayout.expandedHeight + 16),
            to: folder.appending(path: "pages-open.png")
        )
    }

    private static func write(_ view: some View, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(white: 0.32)))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
