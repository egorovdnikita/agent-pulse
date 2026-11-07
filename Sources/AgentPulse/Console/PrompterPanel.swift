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
        hasShadow = true
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

/// Строка суфлёра.
private struct PrompterLineView: View {
    let line: PrompterScript.Line

    var body: some View {
        Text(line.text)
            .font(ConsoleStyle.font(PrompterLook.fontSize, .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Текущая строка всегда верхняя, ближе всего к камере: взгляд не уходит вниз. Прочитанного на панели нет.
struct PrompterView: View {
    let model: ConsoleModel

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let current = model.prompterLine
        let notched = model.prompterNotch > 0
        let lines = model.prompterLines
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: notched ? 0 : 22, bottomLeadingRadius: 22, bottomTrailingRadius: 22,
            topTrailingRadius: notched ? 0 : 22, style: .continuous
        )
        ZStack(alignment: .topLeading) {
            ForEach(lines.indices.filter { $0 >= current && $0 < current + PrompterLook.visibleLines }, id: \.self) { index in
                PrompterLineView(line: lines[index])
                    .opacity(PrompterLayout.lineOpacity(row: index - current))
                    .offset(x: PrompterLook.textInset, y: PrompterLook.topInset + Double(index - current) * PrompterLook.lineStep)
            }
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
        .clipped()
        .padding(.top, model.prompterNotch)
        .background(shape.fill(.black))
        .overlay { if !notched { shape.strokeBorder(ConsoleStyle.edge, lineWidth: 1) } }
        .contentShape(shape)
        .onTapGesture { model.togglePrompterPause() }
        .animation(reduce ? nil : .easeInOut(duration: 0.28), value: current)
        .accessibilityLabel("Суфлёр")
    }
}

enum PrompterLook {
    static let fontSize = 20.0
    static let lineStep = 28.0
    static let visibleLines = 3
    static let topInset = 10.0
    static let textInset = 18.0
    static let textWidth = PrompterLayout.width - textInset * 2
    @MainActor static let font = ConsoleStyle.nsFont(fontSize, .semibold)

    /// Запас: строка не должна упереться в край.
    @MainActor static func fits(_ text: String) -> Bool {
        (text as NSString).size(withAttributes: [.font: font]).width * 1.04 <= textWidth
    }
}
