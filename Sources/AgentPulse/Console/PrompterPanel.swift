import AgentPulseCore
import AppKit
import CoreGraphics
import SwiftUI

/// Суфлёр — единственное, что уходит из угла: текст должен идти под камерой, иначе взгляд бегает.
/// Панель не становится key и не забирает фокус у созвона.
@MainActor
final class PrompterPanel: NSPanel {
    private final class Host<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private let model: ConsoleModel

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
        let host = Host(rootView: PrompterView(model: model))
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

    func place(fallback: NSScreen?, hiddenFromSharing: Bool) {
        sharingType = hiddenFromSharing ? .none : .readOnly
        guard let screen = Self.cameraScreen() ?? fallback else { return }
        // Отладка: `--prompter-notch 37` — показать вид с вырезом на Mac без него.
        let arguments = CommandLine.arguments
        let forced = arguments.firstIndex(of: "--prompter-notch").flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil }
        let notch = forced ?? Double(screen.safeAreaInsets.top)
        model.prompterNotch = notch
        setFrame(PrompterLayout.frame(screen: screen.frame, visible: screen.visibleFrame, notch: notch), display: true)
    }
}

/// Строка суфлёра. Шрифт один: крупнее текущая становится масштабом, чтобы переход был плавным.
private struct PrompterLineView: View {
    let line: PrompterScript.Line
    /// Сколько слов строки уже сказано голосом; nil — вся строка одного цвета.
    let spoken: Int?

    var body: some View {
        Text(attributed)
            .font(.system(size: PrompterLook.fontSize, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
    }

    private var attributed: AttributedString {
        guard let spoken else {
            var text = AttributedString(line.text)
            text.foregroundColor = .white
            return text
        }
        var result = AttributedString()
        for (index, word) in line.text.split(separator: " ").enumerated() {
            var part = AttributedString(index == 0 ? String(word) : " \(word)")
            part.foregroundColor = index < spoken ? .white : .white.opacity(0.55)
            result += part
        }
        return result
    }
}

private struct PrompterView: View {
    let model: ConsoleModel

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let current = model.prompterLine
        let notched = model.prompterNotch > 0
        let lines = model.prompterLines
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: notched ? 0 : 18, bottomLeadingRadius: 18, bottomTrailingRadius: 18,
            topTrailingRadius: notched ? 0 : 18, style: .continuous
        )
        ZStack {
            ForEach(lines.indices.filter { abs($0 - current) <= 2 }, id: \.self) { index in
                let distance = index - current
                PrompterLineView(line: lines[index], spoken: spoken(in: lines[index], isCurrent: distance == 0))
                    .scaleEffect(distance == 0 ? 1 : PrompterLook.sideScale)
                    .opacity(distance == 0 ? 1 : abs(distance) == 1 ? 0.45 : 0)
                    .offset(y: Double(distance) * PrompterLook.lineStep)
            }
            if let status = model.prompterStatus {
                Text(status)
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 14)
                    .padding(.bottom, 6)
            }
        }
        .opacity(model.prompter.mode == .paused ? 0.6 : 1)
        .frame(width: PrompterLayout.width, height: PrompterLayout.textHeight)
        .clipped()
        .padding(.top, model.prompterNotch)
        .background(notched ? AnyView(shape.fill(.black)) : AnyView(HUDBackground().clipShape(shape)))
        .contentShape(shape)
        .onTapGesture { model.togglePrompterPause() }
        .animation(reduce ? nil : .easeInOut(duration: 0.28), value: current)
        .accessibilityLabel("Суфлёр")
    }

    private func spoken(in line: PrompterScript.Line, isCurrent: Bool) -> Int? {
        guard model.prompter.followsVoice, isCurrent else { return nil }
        return min(line.words.count, max(0, Int(model.prompter.position) - line.words.lowerBound))
    }
}

enum PrompterLook {
    static let fontSize = 20.0
    static let sideScale = 0.72
    static let lineStep = 28.0
    static let textWidth = PrompterLayout.width - 36
    @MainActor static let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)

    /// Запас на скруглённое начертание: строка не должна упереться в край.
    @MainActor static func fits(_ text: String) -> Bool {
        (text as NSString).size(withAttributes: [.font: font]).width * 1.04 <= textWidth
    }
}
