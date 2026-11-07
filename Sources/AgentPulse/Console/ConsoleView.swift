import AgentPulseCore
import AppKit
import SwiftUI

/// Сторона капсулы: значок, число, точка зоны. Шесть пунктов цвета: число и так говорит, что происходит.
private struct LimitSide: View {
    let ring: CapsuleRing

    var body: some View {
        HStack(spacing: ConsoleLook.sideGap) {
            ServiceMark(service: ring.service, size: ConsoleLook.mark)
            Text(ring.figure)
                .font(ConsoleStyle.font(15, .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
            if ring.fraction != nil {
                Circle().fill(ConsoleStyle.color(ring.zone)).frame(width: ConsoleLook.dot, height: ConsoleLook.dot)
            }
        }
        .opacity(ring.stale ? 0.45 : 1)
    }
}

/// Живая волна диктовки: без текста, модель не даёт частичного результата. Пока идёт распознавание — застывшая и тише.
private struct DictationWave: View {
    let levels: [Float]
    let listening: Bool

    var body: some View {
        HStack(spacing: DictationLook.barGap) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(listening ? 0.9 : 0.4))
                    .frame(width: DictationLook.barWidth, height: max(DictationLook.barWidth, DictationLook.height * Double(levels[index])))
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct CapsuleBody: View {
    let model: ConsoleModel

    var body: some View {
        let accent = model.dropTargeted ? Color.white.opacity(0.7) : model.alert.map { Color(hex: $0.color) }
        HStack(spacing: ConsoleLook.labelGap) {
            if model.showsDot {
                Image(nsImage: SolarIcons.image("tuning-2") ?? NSImage())
                    .resizable()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.white)
                    .opacity(0.4)
            } else if model.capsule?.wave == true {
                DictationWave(levels: model.dictationLevels, listening: model.dictation.phase == .recording)
            } else if let capsule = model.capsule {
                if !capsule.rings.isEmpty {
                    HStack(spacing: ConsoleLook.ringGap) {
                        ForEach(model.visibleRings) { LimitSide(ring: $0) }
                    }
                } else if let image = model.leaderImage {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: ConsoleLook.ring, height: ConsoleLook.ring)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else if let icon = capsule.icon {
                    Image(nsImage: SolarIcons.image(icon) ?? NSImage()).resizable()
                        .frame(width: 16, height: 16).foregroundStyle(.white)
                }
                if let text = model.capsuleText {
                    HStack(spacing: 4) {
                        Text(text)
                            .font(Font(ConsoleLook.labelFont))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let tail = capsule.tail {
                            Text(tail)
                                .font(Font(ConsoleLook.labelFont))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
                if case .join(let url) = capsule.action {
                    Button("Войти") { model.onJoin?(url) }
                        .buttonStyle(.plain)
                        .font(Font(ConsoleLook.labelFont))
                        .foregroundStyle(ConsoleStyle.orange)
                        .frame(width: ConsoleLook.joinWidth)
                }
                if !model.indicators.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(model.indicators.enumerated()), id: \.offset) { _, color in
                            Circle().fill(Color(hex: color)).frame(width: ConsoleLook.dot, height: ConsoleLook.dot)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, model.showsDot ? 0 : ConsoleLook.padding)
        .frame(width: model.capsuleWidth, height: model.capsuleHeight)
        .background(Color.black)
        .clipShape(Capsule())
        .overlay { Capsule().strokeBorder(accent ?? ConsoleStyle.edge, lineWidth: accent == nil ? 1 : 1.5) }
        .contentShape(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.capsule?.label ?? "Пульт")
        .onTapGesture { model.toggle() }
    }
}

/// Карточка сервиса: заголовок и два окна. Процент — расход, как в капсуле.
private struct LimitCard: View {
    let model: ConsoleModel
    let service: LimitService

    var body: some View {
        let readings = LimitWindowKind.allCases.map { (kind: $0, reading: model.limits.book.reading(service, $0, now: model.now)) }
        ConsoleCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ServiceMark(service: service, size: 17)
                    Text(service.title).font(ConsoleStyle.font(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 0)
                    if readings.allSatisfy({ $0.reading == nil }) {
                        Button("Подключить") { model.onOpenSettings?() }
                            .buttonStyle(ConsolePressStyle())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        chip(readings.map(\.reading))
                    }
                }
                .frame(height: 20)
                HStack(spacing: 12) {
                    ForEach(readings, id: \.kind) { item in
                        LimitGauge(reading: item.reading, kind: item.kind, now: model.now).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func chip(_ readings: [LimitReading?]) -> some View {
        let known = readings.compactMap { $0 }
        let title = known.isEmpty ? "Нет данных" : known.contains(where: \.stale) ? "Устарело" : "Свежие"
        return Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(title == "Свежие" ? ConsoleStyle.green : ConsoleStyle.caption)
            .lineLimit(1)
    }
}

private struct LimitsTab: View {
    let model: ConsoleModel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(LimitService.allCases, id: \.self) { LimitCard(model: model, service: $0) }
        }
    }
}

/// Шапка: тот же маскот, что живёт в углу, и то, что он сказал бы при наведении.
private struct MascotHeader: View {
    let model: ConsoleModel

    var body: some View {
        // Фраза перечитывается раз в секунду: `now` обновляет тик.
        let _ = model.now
        HStack(spacing: 8) {
            if let animator = model.mascotAnimator {
                // У маскота холст с запасом под «Zzz» и прыжки: он шире строки, это нормально.
                let box = MascotView.boxSize(ConsoleLook.mascot)
                MascotView(animator: animator, diameter: ConsoleLook.mascot, paused: !model.expanded)
                    .frame(width: box, height: box)
                    .frame(width: ConsoleLook.header, height: ConsoleLook.header)
                    .accessibilityHidden(true)
            }
            Text(model.mascotLine())
                .font(ConsoleStyle.font(13, .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(height: ConsoleLook.header)
    }
}

/// Страницы текстом, без подложек: в слово легко попасть мышью.
private struct PageTabs: View {
    let model: ConsoleModel

    var body: some View {
        HStack(spacing: 14) {
            ForEach(model.tabs, id: \.id) { tab in
                Button { model.openPage(tab.id) } label: {
                    Text(tab.title)
                        .font(ConsoleStyle.font(13, model.tab == tab.id ? .semibold : .medium))
                        .foregroundStyle(model.tab == tab.id ? .white : ConsoleStyle.caption)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(height: ConsoleLook.tabs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ConsolePressStyle())
            }
            Spacer(minLength: 0)
        }
    }
}

/// Точки: где ты среди страниц. Нажимаются, но главная навигация — слова.
private struct PageDots: View {
    let model: ConsoleModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(model.tabs, id: \.id) { tab in
                Button { model.openPage(tab.id) } label: {
                    Circle()
                        .fill(Color.white.opacity(model.tab == tab.id ? 0xB3 / 255 : 0x3D / 255))
                        .frame(width: 6, height: 6)
                        .frame(width: 14, height: ConsoleLook.dots)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ExpandedBody: View {
    let model: ConsoleModel

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                MascotHeader(model: model)
                PageTabs(model: model)
            }
            .padding(.horizontal, ConsoleStyle.inset + 4)
            .padding(.top, ConsoleStyle.inset - 4)
            ZStack(alignment: .topLeading) {
                page
                    .id(model.tab)
                    .transition(pageTransition(reduced: reduce))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 6)
            .clipped()
            PageDots(model: model)
        }
        .opacity(model.contentShown ? 1 : 0)
        .offset(y: model.contentShown || reduce ? 0 : 8)
        .animation(ConsoleStyle.contentMotion(appearing: model.contentShown, reduced: reduce), value: model.contentShown)
        .animation(ConsoleStyle.pageMotion(reduced: reduce), value: model.tab)
        .frame(width: ConsoleLayout.expandedWidth, height: ConsoleLayout.expandedHeight, alignment: .topLeading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: ConsoleStyle.surfaceRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConsoleStyle.surfaceRadius, style: .continuous).strokeBorder(ConsoleStyle.edge, lineWidth: 1)
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.tab {
            case .prompter: PrompterTab(model: model)
            case .calendar: CalendarTab(model: model)
            case .shelf: ShelfTab(model: model)
            case .media: MediaTab(model: model)
            case .translate: TranslateTab(model: model)
            default: LimitsTab(model: model)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ConsoleStyle.inset)
    }

    /// Старая страница просто гаснет, новая приходит сбоку: одновременно двигается только одна, глаз не теряет её.
    private func pageTransition(reduced: Bool) -> AnyTransition {
        guard !reduced else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: Double(model.pageTravel) * ConsoleLook.pageShift)),
            removal: .opacity.animation(.easeOut(duration: 0.09))
        )
    }
}

/// Для `--console-sheet`.
struct CapsulePreview: View {
    let model: ConsoleModel

    var body: some View { CapsuleBody(model: model) }
}

struct PrompterPreview: View {
    let model: ConsoleModel

    var body: some View { PrompterView(model: model) }
}

struct PanelPreview: View {
    let model: ConsoleModel

    var body: some View { ExpandedBody(model: model) }
}

struct ConsoleRootView: View {
    let model: ConsoleModel

    /// Панель вырастает из капсулы, из своего угла, и уходит туда же, но быстрее.
    private func panelTransition(reduced: Bool) -> AnyTransition {
        guard !reduced else { return .opacity }
        let anchor: UnitPoint = model.onLeft ? .bottomLeading : .bottomTrailing
        return .asymmetric(
            insertion: .scale(scale: 0.88, anchor: anchor).combined(with: .opacity),
            removal: .scale(scale: 0.95, anchor: anchor).combined(with: .opacity)
        )
    }

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        VStack(alignment: model.onLeft ? .leading : .trailing, spacing: model.expandedGap) {
            if model.expanded { ExpandedBody(model: model).transition(panelTransition(reduced: reduce)) }
            CapsuleBody(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.onLeft ? .bottomLeading : .bottomTrailing)
        .animation(model.director.quietChange ? nil : ConsoleStyle.motion(opening: true, reduced: reduce), value: model.capsuleWidth)
        .animation(model.director.quietChange ? nil : ConsoleStyle.panelMotion(opening: model.expanded, reduced: reduce), value: model.expanded)
    }
}
