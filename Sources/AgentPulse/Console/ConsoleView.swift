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

private extension ConsoleModuleID {
    var pageIcon: String {
        switch self {
        case .limits: "tuning-2"
        case .prompter: "document-text"
        case .calendar: "calendar"
        case .shelf: "folder-with-files"
        case .media: "music-note"
        case .translate: "translation"
        case .dictation: "document-text"
        }
    }
}

/// Страницы: точки, под курсором — кнопки с иконками и подписью.
private struct PageSwitcher: View {
    let model: ConsoleModel

    var body: some View {
        let open = model.pagesHovered
        let shown = model.pageUnderCursor ?? model.tab
        HStack(spacing: 4) {
            ForEach(model.tabs, id: \.id) { tab in
                page(tab.id, title: tab.title, open: open)
            }
        }
        .frame(maxWidth: .infinity)
        // Название страницы видно всегда: одних точек мало, чтобы понять, где ты.
        .overlay(alignment: .leading) {
            Text(model.tabs.first { $0.id == shown }?.title ?? "")
                .font(ConsoleStyle.font(10, .medium))
                .foregroundStyle(ConsoleStyle.caption)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, 8)
        }
        .padding(.horizontal, ConsoleStyle.inset)
        .frame(height: open ? ConsoleLook.pagesOpen : ConsoleLook.pagesClosed, alignment: .center)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            // Кнопки встают поверх страницы: край уходит в чёрное, а не обрезается.
            if open {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 14)
                    Color.black.frame(height: ConsoleLook.pagesOpen)
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            model.pagesHovered = inside
            if !inside { model.pageUnderCursor = nil }
        }
        .animation(ConsoleStyle.motion(opening: open, reduced: false), value: open)
    }

    private func page(_ id: ConsoleModuleID, title: String, open: Bool) -> some View {
        let current = model.tab == id
        let opacity: Double = if open {
            current ? 0x66 / 255 : 0x2E / 255
        } else {
            current ? 0xB3 / 255 : 0x3D / 255
        }
        return Button { model.tab = id } label: {
            RoundedRectangle(cornerRadius: open ? 4 : 3, style: .continuous)
                .fill(Color.white.opacity(opacity))
                .frame(width: open ? 22 : 6, height: open ? 22 : 6)
                .overlay {
                    Image(nsImage: SolarIcons.image(id.pageIcon) ?? NSImage())
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.white)
                        .opacity(open ? (current ? 1 : 0.6) : 0)
                }
                .frame(width: open ? 22 : 8, height: open ? 22 : 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(ConsolePressStyle())
        .onHover { model.pageUnderCursor = $0 ? id : nil }
        .accessibilityLabel(title)
    }
}

private struct ExpandedBody: View {
    let model: ConsoleModel

    var body: some View {
        ZStack(alignment: .bottom) {
            page
                .id(model.tab)
                .transition(.opacity)
            PageSwitcher(model: model)
        }
        .frame(width: model.expandedWidth, height: ConsoleLayout.expandedHeight, alignment: .topLeading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: ConsoleStyle.surfaceRadius, style: .continuous))
        .animation(.easeOut(duration: ConsoleLook.pageFade), value: model.tab)
        .overlay {
            RoundedRectangle(cornerRadius: ConsoleStyle.surfaceRadius, style: .continuous).strokeBorder(ConsoleStyle.edge, lineWidth: 1)
        }
    }
}

private extension ExpandedBody {
    var page: some View {
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
        .padding([.horizontal, .top], ConsoleStyle.inset)
        .padding(.bottom, ConsoleLook.pagesClosed)
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

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        VStack(alignment: model.onLeft ? .leading : .trailing, spacing: ConsoleLayout.expandedGap) {
            if model.expanded { ExpandedBody(model: model).transition(.opacity) }
            CapsuleBody(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.onLeft ? .bottomLeading : .bottomTrailing)
        .animation(model.director.quietChange ? nil : ConsoleStyle.motion(opening: true, reduced: reduce), value: model.capsuleWidth)
        .animation(
            model.director.quietChange ? nil : ConsoleStyle.motion(opening: model.expanded, reduced: reduce), value: model.expanded
        )
    }
}
