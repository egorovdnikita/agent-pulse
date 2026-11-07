import AgentPulseCore
import AppKit
import SwiftUI

private extension ConsoleModuleID {
    /// Значок модуля в капсуле.
    var icon: String {
        switch self {
        case .limits: "tuning-2"
        case .prompter, .dictation: "document-text"
        case .calendar: "calendar"
        case .translate: "translation"
        case .shelf: "folder-with-files"
        case .media: "music-note"
        }
    }
}

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
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                    // Значки, а не цветные точки: точка рядом с числом уже значит зону лимита.
                    HStack(spacing: 6) {
                        ForEach(model.indicators, id: \.self) { module in
                            Image(nsImage: SolarIcons.image(module.icon) ?? NSImage())
                                .resizable()
                                .frame(width: ConsoleLook.indicator, height: ConsoleLook.indicator)
                                .foregroundStyle(.white)
                                .opacity(0.55)
                                .accessibilityLabel(model.tabs.first { $0.id == module }?.title ?? "")
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ServiceMark(service: service, size: 17)
                    Text(service.title).font(ConsoleStyle.font(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                    if model.mascotService() == service, let animator = model.mascotAnimator {
                        // Маскот — деталь рядом с именем того, кто работает. Холст шире строки: запас под прыжки.
                        let box = MascotView.boxSize(ConsoleLook.mascot)
                        MascotView(animator: animator, diameter: ConsoleLook.mascot, paused: !model.expanded)
                            .frame(width: box, height: box)
                            .frame(width: 24, height: 20)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                    if readings.allSatisfy({ $0.reading == nil }) {
                        Button("Подключить") { model.onOpenSettings?("Лимиты \(service.title)") }
                            .buttonStyle(ConsolePressStyle())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        // Процент — расход: у похожих приложений такое же число значит остаток.
                        Text("использовано").font(ConsoleStyle.font(11)).foregroundStyle(ConsoleStyle.caption).lineLimit(1)
                        chip(readings.map(\.reading))
                    }
                }
                .frame(height: 20)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    ForEach(readings, id: \.kind) { item in
                        LimitGauge(reading: item.reading, kind: item.kind, now: model.now).frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
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
        HStack(spacing: 8) {
            ForEach(LimitService.allCases, id: \.self) { LimitCard(model: model, service: $0) }
        }
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
                        // Вес один: иначе при смене страницы соседние слова сдвигаются.
                        .font(ConsoleStyle.font(13, .medium))
                        .foregroundStyle(model.tab == tab.id ? .white : ConsoleStyle.caption)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(height: ConsoleLook.tabs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ConsolePressStyle())
            }
            Spacer(minLength: 0)
            Button {
                model.setExpanded(false)
                model.onOpenSettings?(nil)
            } label: {
                Image(nsImage: SolarIcons.image("settings") ?? NSImage())
                    .resizable()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.white)
                    .opacity(0.55)
                    .frame(width: ConsoleLook.tabs, height: ConsoleLook.tabs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ConsolePressStyle())
            .accessibilityLabel("Настройки")
        }
    }
}

private struct ExpandedBody: View {
    let model: ConsoleModel

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        VStack(alignment: .leading, spacing: 0) {
            PageTabs(model: model)
                .padding(.horizontal, ConsoleStyle.inset + 4)
                .padding(.top, ConsoleStyle.inset - 4)
            ZStack(alignment: .topLeading) {
                // Страница едет целиком: анимация не проваливается внутрь, иначе текст и подложка двигаются порознь.
                page
                    .transaction { $0.animation = nil }
                    .compositingGroup()
                    .id(model.tab)
                    .transition(pageTransition(reduced: reduce))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .padding(.bottom, ConsoleStyle.inset)
            .clipped()
        }
        .opacity(model.contentShown ? 1 : 0)
        .animation(ConsoleStyle.contentMotion(appearing: model.contentShown, reduced: reduce), value: model.contentShown)
        .animation(ConsoleStyle.pageMotion(reduced: reduce), value: model.tab)
        .frame(width: ConsoleLayout.expandedWidth, height: ConsoleLayout.expandedHeight, alignment: .topLeading)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, ConsoleStyle.inset)
    }

    /// Следующая страница чуть выходит справа, предыдущая слева; старая просто гаснет: движется только одна.
    private func pageTransition(reduced: Bool) -> AnyTransition {
        guard !reduced else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: Double(model.pageTravel) * ConsoleLook.pageShift)),
            removal: .opacity.animation(.easeOut(duration: 0.08))
        )
    }
}

/// Чёрная форма панели. Как в шторке референса: содержимое стоит на месте, а форма вырастает из капсулы
/// и обрезает его по себе. Ничего не масштабируется, поэтому текст не плывёт и не сжимается.
private struct PanelSurface<Content: View>: View {
    let model: ConsoleModel
    @ViewBuilder let content: Content

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let open = model.panelOpen
        let alignment: Alignment = model.onLeft ? .bottomLeading : .bottomTrailing
        let width = open ? ConsoleLayout.expandedWidth : model.capsuleWidth
        let height = open ? ConsoleLayout.expandedHeight : model.capsuleHeight
        let radius = open ? ConsoleStyle.surfaceRadius : model.capsuleHeight / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack(alignment: alignment) {
            shape.fill(Color.black).frame(width: width, height: height)
            content.mask(alignment: alignment) { shape.frame(width: width, height: height) }
            shape.strokeBorder(ConsoleStyle.edge, lineWidth: 1).frame(width: width, height: height)
        }
        .frame(width: ConsoleLayout.expandedWidth, height: ConsoleLayout.expandedHeight, alignment: alignment)
        .offset(y: open ? 0 : model.expandedGap + model.capsuleHeight)
        .animation(model.director.quietChange ? nil : ConsoleStyle.panelMotion(opening: open, reduced: reduce), value: open)
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

    var body: some View { PanelSurface(model: model) { ExpandedBody(model: model) } }
}

struct ConsoleRootView: View {
    let model: ConsoleModel

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        VStack(alignment: model.onLeft ? .leading : .trailing, spacing: model.expandedGap) {
            if model.panelMounted { PanelSurface(model: model) { ExpandedBody(model: model) } }
            CapsuleBody(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.onLeft ? .bottomLeading : .bottomTrailing)
        .animation(model.director.quietChange ? nil : ConsoleStyle.motion(opening: true, reduced: reduce), value: model.capsuleWidth)
    }
}
