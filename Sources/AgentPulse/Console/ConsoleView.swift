import AgentPulseCore
import AppKit
import SwiftUI

/// Подложка Пульта: тёмная и полупрозрачная. Пульт — инструмент, поэтому он строже маскота.
private struct HUDBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private extension LimitZone {
    func color(_ service: LimitService) -> Color {
        switch self {
        case .normal: Color(hex: service.color)
        case .attention: Color(hex: 0xFF9F0A)
        case .critical, .exhausted: Color(hex: ConsoleLook.alertColor)
        }
    }
}

/// Кольцо: заполнение — расход самого тесного окна. Нет данных — пустое кольцо, а не 0%.
private struct LimitRing: View {
    let fraction: Double?
    let color: Color
    let dimmed: Bool
    var size = ConsoleLook.ring

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: 3)
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(1.5)
        .frame(width: size, height: size)
        .opacity(dimmed ? 0.45 : 1)
    }
}

private struct CapsuleBody: View {
    let model: ConsoleModel

    var body: some View {
        let accent = model.alert.map { Color(hex: $0.color) }
        HStack(spacing: ConsoleLook.labelGap) {
            if model.showsDot {
                Image(nsImage: SolarIcons.image("tuning-2") ?? NSImage())
                    .resizable()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.white)
                    .opacity(0.4)
            } else if let capsule = model.capsule {
                HStack(spacing: ConsoleLook.ringGap) {
                    ForEach(model.visibleRings) { ring in
                        LimitRing(fraction: ring.fraction, color: ring.zone.color(ring.service), dimmed: ring.stale)
                    }
                }
                if model.showsLabel {
                    Text(capsule.label)
                        .font(Font(ConsoleLook.labelFont))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, model.showsDot ? 0 : ConsoleLook.padding)
        .frame(width: model.capsuleWidth, height: model.capsuleHeight)
        .background(HUDBackground())
        .clipShape(Capsule())
        .overlay { if let accent { Capsule().strokeBorder(accent, lineWidth: 1.5) } }
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.capsule?.label ?? "Пульт")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { model.toggle() }
    }
}

private struct LimitRow: View {
    let reading: LimitReading?
    let kind: LimitWindowKind
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            LimitRing(fraction: reading.map { min(1, Double($0.usedPercent) / 100) }, color: reading.map { $0.zone.color($0.service) } ?? .white,
                      dimmed: reading?.stale ?? false, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white)
                Text(detail).font(.system(size: 11, design: .rounded).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Text(reading.map { "\($0.usedPercent)%" } ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    private var detail: String {
        guard let reading else { return LimitText.noData }
        if reading.stale { return LimitText.stale }
        return reading.resetsAt.map { "сброс \(LimitText.countdown($0, now: now))" } ?? " "
    }
}

/// Вкладка «Лимиты»: оба окна каждого сервиса с обратным отсчётом.
private struct LimitsTab: View {
    let model: ConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(LimitService.allCases, id: \.self) { service in
                VStack(alignment: .leading, spacing: 8) {
                    Text(service.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    ForEach(LimitWindowKind.allCases, id: \.self) { kind in
                        LimitRow(reading: model.limits.book.reading(service, kind, now: model.now), kind: kind, now: model.now)
                    }
                }
            }
        }
    }
}

private struct ExpandedBody: View {
    let model: ConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.limits.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            LimitsTab(model: model)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: model.expandedWidth, height: ConsoleLayout.expandedHeight, alignment: .topLeading)
        .background(HUDBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ConsoleRootView: View {
    let model: ConsoleModel

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || model.director.quietChange
        VStack(alignment: model.onLeft ? .leading : .trailing, spacing: ConsoleLayout.expandedGap) {
            if model.expanded { ExpandedBody(model: model).transition(.opacity) }
            CapsuleBody(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.onLeft ? .bottomLeading : .bottomTrailing)
        .animation(reduce ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: model.capsuleWidth)
        .animation(reduce ? nil : .easeOut(duration: 0.2), value: model.expanded)
    }
}
