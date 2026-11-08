import AgentPulseCore
import AppKit
import CoreGraphics
import Observation
import SwiftUI

/// Суфлёр — единственное, что уходит из угла: текст должен идти под камерой, иначе взгляд бегает.
/// Панель не становится key и не забирает фокус у созвона.
@MainActor
@Observable
final class PrompterReveal {
    var open = false
    var contentShown = false
}

@MainActor
final class PrompterPanel: NSPanel {
    private final class Host<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private let model: ConsoleModel
    private let reveal = PrompterReveal()
    private var hideTask: Task<Void, Never>?

    init(model: ConsoleModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PrompterLayout.width, height: PrompterLayout.textHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        // Нужен именно поверх полноэкранного Zoom и Keynote.
        collectionBehavior = OverlayPanel.spaceBehavior.union(.fullScreenAuxiliary)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        let host = Host(rootView: PrompterSurface(model: model, reveal: reveal))
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Экран со встроенной камерой. Крышка закрыта и такого нет — экран Пульта.
    static func cameraScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number.map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
        }
    }

    func show(fallback: NSScreen?, hiddenFromSharing: Bool) {
        hideTask?.cancel()
        reveal.open = false
        reveal.contentShown = false
        place(fallback: fallback, hiddenFromSharing: hiddenFromSharing)
        orderFrontRegardless()
        DispatchQueue.main.async { [reveal] in
            MainActor.assumeIsolated {
                reveal.open = true
                reveal.contentShown = true
            }
        }
    }

    /// Форма уходит обратно к камере, и только потом окно прячется.
    func hide() {
        reveal.open = false
        reveal.contentShown = false
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(ConsoleLook.closeMilliseconds))
            guard !Task.isCancelled else { return }
            self?.orderOut(nil)
        }
    }

    private func place(fallback: NSScreen?, hiddenFromSharing: Bool) {
        sharingType = hiddenFromSharing ? .none : .readOnly
        guard let screen = Self.cameraScreen() ?? fallback else { return }
        // Отладка: `--prompter-notch 37` — показать вид с вырезом на Mac без него.
        let arguments = CommandLine.arguments
        let forced = arguments.firstIndex(of: "--prompter-notch").flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil }
        let notch = forced ?? Double(screen.safeAreaInsets.top)
        model.prompterNotch = notch
        let frame = PrompterLayout.frame(screen: screen.frame, visible: screen.visibleFrame, notch: notch)
        // Запас под пружину и тень: форма рисуется внутри окна.
        let room = PrompterSurface.room
        setFrame(NSRect(x: frame.minX - room, y: frame.minY - room, width: frame.width + room * 2, height: frame.height + room), display: true)
    }
}

/// Строка суфлёра. За голосом за текущим словом плывёт мягкая плашка.
private struct PrompterLineView: View {
    let line: PrompterScript.Line
    /// Какое слово строки сейчас говорится; nil — строка идёт по часам.
    let litWord: Int?
    let points: Double

    var body: some View {
        Text(line.text)
            .font(ConsoleStyle.font(points, .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .background(alignment: .leading) {
                if let litWord, let spot = spot(litWord) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ConsoleStyle.green.opacity(0.35))
                        .frame(width: spot.width + 8, height: PrompterLook.lineStep(points) - 2)
                        .offset(x: spot.start - 4)
                        .animation(.easeOut(duration: 0.14), value: litWord)
                }
            }
    }

    /// Где слово стоит в строке. Меряется тем же шрифтом, каким нарисовано.
    private func spot(_ index: Int) -> (start: Double, width: Double)? {
        let words = line.text.split(separator: " ").map(String.init)
        guard words.indices.contains(index) else { return nil }
        let measure = { (text: String) in (text as NSString).size(withAttributes: [.font: PrompterLook.font(points)]).width }
        let before = index == 0 ? "" : words[..<index].joined(separator: " ") + " "
        return (Double(measure(before)), Double(measure(words[index])))
    }
}

/// Текущая строка всегда верхняя, ближе всего к камере: взгляд не уходит вниз. Прочитанного на панели нет.
struct PrompterView: View {
    let model: ConsoleModel

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let current = model.prompterLine
        let points = model.prompterTextSize.points
        let step = PrompterLook.lineStep(points)
        // Положение меняется пять раз в секунду, а движение между ними считает Core Animation: текст едет без кадров на CPU.
        let scroll = reduce ? Double(current) : model.prompterScroll
        let notched = model.prompterNotch > 0
        let lines = model.prompterLines
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: notched ? 0 : 20, bottomLeadingRadius: 20, bottomTrailingRadius: 20,
            topTrailingRadius: notched ? 0 : 20, style: .continuous
        )
        ZStack(alignment: .topLeading) {
            ForEach(lines.indices.filter { $0 >= current - 1 && $0 < current + PrompterLook.visibleLines + 1 }, id: \.self) { index in
                PrompterLineView(line: lines[index], litWord: index == current ? litWord(in: lines[index]) : nil, points: points)
                    .opacity(index < current ? 0 : PrompterLayout.lineOpacity(row: index - current))
                    .offset(x: PrompterLook.textInset, y: PrompterLook.topInset + (Double(index) - scroll) * step)
            }
            // Кнопки стоят на месте, пока текст едет.
            VStack(spacing: 2) {
                Button { model.togglePrompterPause() } label: {
                    Image(nsImage: SolarIcons.image(model.prompter.mode == .paused ? "play" : "pause") ?? NSImage())
                        .resizable()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(.white)
                        .frame(width: PrompterLook.controlsWidth, height: step)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(model.prompter.mode == .paused ? "Дальше" : "Пауза")
                .promoTarget("top-pause")
                Button { model.stopPrompter() } label: {
                    Image(nsImage: SolarIcons.image("stop-circle") ?? NSImage())
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(ConsoleStyle.red)
                        .frame(width: PrompterLook.controlsWidth, height: step)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Стоп")
                .promoTarget("top-stop")
            }
            .buttonStyle(ConsolePressStyle())
            .padding(.top, PrompterLook.topInset)
            .padding(.leading, PrompterLook.controlsInset)
            if let status = model.prompterStatus {
                Text(status)
                    .font(ConsoleStyle.font(11, .medium).monospacedDigit())
                    .foregroundStyle(ConsoleStyle.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 14)
                    .padding(.bottom, 6)
            }
        }
        .opacity(model.prompter.mode == .paused ? 0.6 : 1)
        .frame(width: PrompterLayout.width, height: PrompterLayout.textHeight, alignment: .topLeading)
        // Текст не обрывается по краю, а уходит в чёрное. Маска — после размера: иначе она режет текст по его рамке.
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.62), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .clipped()
        .padding(.top, model.prompterNotch)
        .contentShape(shape)
        .onTapGesture { model.togglePrompterPause() }
        .animation(reduce ? nil : .linear(duration: PrompterLook.tick), value: scroll)
        .accessibilityLabel("Суфлёр")
    }
}

private extension PrompterView {
    func litWord(in line: PrompterScript.Line) -> Int? {
        guard model.prompter.followsVoice else { return nil }
        return min(line.words.count - 1, max(0, Int(model.prompter.position) - line.words.lowerBound))
    }
}

/// Как и Пульт, суфлёр раскрывается формой: чёрное вырастает из-под камеры, текст проявляется уже в нём.
private struct PrompterSurface: View {
    let model: ConsoleModel
    let reveal: PrompterReveal
    static let room = 24.0
    static let startWidth = 180.0

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let open = reveal.open
        let notched = model.prompterNotch > 0
        let height = PrompterLayout.textHeight + model.prompterNotch
        let width = open ? PrompterLayout.width : Self.startWidth
        let shown = open ? height : max(model.prompterNotch, 32)
        let radius = open ? 20.0 : 16.0
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: notched ? 0 : radius, bottomLeadingRadius: radius, bottomTrailingRadius: radius,
            topTrailingRadius: notched ? 0 : radius, style: .continuous
        )
        ZStack(alignment: .top) {
            shape.fill(.black)
                .frame(width: width, height: shown)
                .consoleShadow()
            PrompterView(model: model)
                .opacity(reveal.contentShown ? 1 : 0)
                .animation(ConsoleStyle.contentMotion(appearing: reveal.contentShown, reduced: reduce), value: reveal.contentShown)
                .mask(alignment: .top) { shape.frame(width: width, height: shown) }
            if !notched { shape.strokeBorder(ConsoleStyle.edge, lineWidth: 1).frame(width: width, height: shown) }
        }
        .frame(width: PrompterLayout.width, height: height, alignment: .top)
        .animation(ConsoleStyle.panelMotion(opening: open, reduced: reduce), value: open)
        .padding([.horizontal, .bottom], Self.room)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

enum PrompterLook {
    /// Шаг таймера суфлёра.
    static let tick = 0.2
    static func lineStep(_ points: Double) -> Double { (points * 1.4).rounded() }
    static let visibleLines = 5
    static let topInset = 10.0
    /// Колонка кнопок слева и текст за ней.
    static let controlsInset = 14.0
    static let controlsWidth = 22.0
    static let textInset = controlsInset + controlsWidth + 10
    static let textWidth = PrompterLayout.width - textInset - 18
    @MainActor static func font(_ points: Double) -> NSFont { ConsoleStyle.nsFont(points, .semibold) }

    /// Запас: строка не должна упереться в край.
    @MainActor static func fits(_ text: String, points: Double) -> Bool {
        (text as NSString).size(withAttributes: [.font: font(points)]).width * 1.04 <= textWidth
    }
}
