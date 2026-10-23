import AgentPulseCore
import SwiftUI

/// Компактный режим: маскот и облачко-реплика рядом. Облачко — со стороны, противоположной краю экрана.
struct PillView: View {
    let model: PulseModel
    let app: AppDelegate

    static let mirrorSlot = MirrorView.maxSize.height + 12

    /// Облачко заходит на поле холста маскота: хвостик в 8 pt от тела, а не у края холста.
    static func bubbleOverlap(diameter: Double) -> Double {
        max(0, (MascotView.boxSize(diameter) - diameter) / 2 - 8)
    }

    static func rowHeight(diameter: Double) -> Double {
        max(MascotView.boxSize(diameter), 64)
    }

    /// Над рядом (под ним, если маскот сверху) — место под зеркало Figma. Пустое место пропускает клики.
    static func size(diameter: Double) -> CGSize {
        let box = MascotView.boxSize(diameter)
        return CGSize(
            width: BubbleView.maxWidth + box - bubbleOverlap(diameter: diameter),
            height: rowHeight(diameter: diameter) + mirrorSlot
        )
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
        HStack(spacing: -Self.bubbleOverlap(diameter: diameter)) {
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
            paused: !model.overlayVisible || model.overlayOccluded,
            lowFrameRate: model.state == .sleep
        )
        .contentShape(Circle())
        .onTapGesture { model.tapMascot() }
        // Перетаскивание и бросок: окно двигает панель по положению курсора на экране.
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in app.panel?.dragChanged() }
                .onEnded { _ in app.panel?.dragEnded() }
        )
        // То же меню, что в строке меню: значок там легко потерять среди других.
        .contextMenu { MenuContent(app: app) }
        .overlay(alignment: model.config.display.anchor.isRight ? .topLeading : .topTrailing) {
            SessionCountBadge(count: model.activeSessions.count, diameter: diameter)
        }
    }

    private func bubbleSlot(tailOnRight: Bool) -> some View {
        let reduceMotion = model.animator.reduceMotion
        let insertion: AnyTransition = reduceMotion
            ? .opacity
            : .scale(scale: 0.6, anchor: tailOnRight ? .trailing : .leading).combined(with: .opacity)
        return ZStack(alignment: tailOnRight ? .trailing : .leading) {
            if let message = model.visibleMessage {
                BubbleView(message: message, tailOnRight: tailOnRight)
                    .id(model.bubbleKey)
                    .transition(.asymmetric(insertion: insertion, removal: .opacity.animation(.easeOut(duration: 0.2))))
                    .onTapGesture { model.tapBubble() }
            }
        }
        .frame(width: BubbleView.maxWidth, alignment: tailOnRight ? .trailing : .leading)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.18), value: model.bubbleKey)
    }
}

/// Несколько агентов работают одновременно — маленький счётчик у маскота. Маскот показывает самого важного.
struct SessionCountBadge: View {
    let count: Int
    let diameter: Double

    var body: some View {
        if count > 1 {
            Text("\(count)")
                .font(.system(size: max(9, diameter * 0.2), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 16)
                .background(Capsule().fill(.black.opacity(0.75)))
                .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
                .padding(diameter * 0.25)
                .transition(.scale.combined(with: .opacity))
                .help("Агентов в работе: \(count)")
        }
    }
}
