import AgentPulseCore
import SwiftUI

/// Компактный режим: маскот и облачко-реплика рядом. Облачко — со стороны, противоположной краю экрана.
struct PillView: View {
    let model: PulseModel

    static let mirrorSlot = MirrorView.maxSize.height + 12

    static func rowHeight(diameter: Double) -> Double {
        max(MascotView.boxSize(diameter), 64)
    }

    /// Над рядом (под ним, если маскот сверху) — место под зеркало Figma. Пустое место пропускает клики.
    static func size(diameter: Double) -> CGSize {
        let box = MascotView.boxSize(diameter)
        return CGSize(width: BubbleView.maxWidth + box, height: rowHeight(diameter: diameter) + mirrorSlot)
    }

    var body: some View {
        let diameter = model.config.display.mascotSize
        let anchor = model.config.display.anchor
        let size = Self.size(diameter: diameter)
        VStack(spacing: 0) {
            if anchor.isTop {
                row(diameter, anchorRight: anchor.isRight)
                mirrorSlot(anchor)
            } else {
                mirrorSlot(anchor)
                row(diameter, anchorRight: anchor.isRight)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func row(_ diameter: Double, anchorRight: Bool) -> some View {
        HStack(spacing: 0) {
            if anchorRight {
                bubbleSlot(tailOnRight: true)
                mascot(diameter)
            } else {
                mascot(diameter)
                bubbleSlot(tailOnRight: false)
            }
        }
        .frame(height: Self.rowHeight(diameter: diameter))
    }

    private func mirrorSlot(_ anchor: PulseConfig.Display.Anchor) -> some View {
        ZStack(alignment: Alignment(horizontal: anchor.isRight ? .trailing : .leading, vertical: anchor.isTop ? .top : .bottom)) {
            if model.showMirror, let frame = model.mirror {
                MirrorView(frame: frame)
                    .id(frame.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: anchor.isTop ? .top : .bottom)))
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: anchor.isRight ? .trailing : .leading, vertical: anchor.isTop ? .top : .bottom))
        .frame(height: Self.mirrorSlot)
        .animation(.easeInOut(duration: 0.25), value: model.showMirror)
        .animation(.easeInOut(duration: 0.2), value: model.mirror?.id)
    }

    private func mascot(_ diameter: Double) -> some View {
        MascotView(
            animator: model.animator,
            diameter: diameter,
            paused: !model.overlayVisible,
            lowFrameRate: model.state == .sleep
        )
        .contentShape(Circle())
        .onTapGesture { model.activateSource() }
    }

    private func bubbleSlot(tailOnRight: Bool) -> some View {
        let reduceMotion = model.animator.reduceMotion
        let insertion: AnyTransition = reduceMotion
            ? .opacity
            : .scale(scale: 0.6, anchor: tailOnRight ? .trailing : .leading).combined(with: .opacity)
        return ZStack(alignment: tailOnRight ? .trailing : .leading) {
            if let text = model.visibleBubbleText {
                BubbleView(text: text, tailOnRight: tailOnRight)
                    .id(model.bubbleKey)
                    .transition(.asymmetric(insertion: insertion, removal: .opacity.animation(.easeOut(duration: 0.2))))
                    .help(model.statusLine)
                    .onTapGesture { model.activateSource() }
            }
        }
        .frame(width: BubbleView.maxWidth, alignment: tailOnRight ? .trailing : .leading)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.18), value: model.bubbleKey)
    }
}
