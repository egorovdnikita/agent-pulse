import AgentPulseCore
import SwiftUI

/// Компактный режим: маскот и облачко-реплика рядом. Облачко — со стороны, противоположной краю экрана.
struct PillView: View {
    let model: PulseModel

    static func size(diameter: Double) -> CGSize {
        let box = MascotView.boxSize(diameter)
        return CGSize(width: BubbleView.maxWidth + box, height: max(box, 64))
    }

    var body: some View {
        let diameter = model.config.display.mascotSize
        let anchorRight = model.config.display.anchor.isRight
        let size = Self.size(diameter: diameter)
        HStack(spacing: 0) {
            if anchorRight {
                bubbleSlot(tailOnRight: true)
                mascot(diameter)
            } else {
                mascot(diameter)
                bubbleSlot(tailOnRight: false)
            }
        }
        .frame(width: size.width, height: size.height)
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
