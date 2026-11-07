import AgentPulseCore
import AppKit
import SwiftUI

/// Меню в строке меню и по правому клику на маскоте: только то, что нужно каждый день.
/// Своё, а не системное: системное меню не принимает язык Пульта. Всё остальное — в окне «Настройки».
struct PulseMenuView: View {
    let app: AppDelegate
    let dismiss: () -> Void

    static let width = 280.0

    var body: some View {
        let model = app.model
        VStack(alignment: .leading, spacing: 8) {
            status(model)
            if let reaction = model.lastReaction {
                reactionCard(model, line: model.lastLine ?? reaction)
            }
            ConsoleCard(fills: false, padding: 4) {
                VStack(spacing: 0) {
                    PulseMenuSwitch(title: "Показывать маскота", isOn: model.overlayVisible) { app.setOverlayVisible($0) }
                    PulseMenuSwitch(title: "Рассказывать новости", isOn: model.config.character.designNews) { app.setDesignNews($0) }
                }
            }
            VStack(spacing: 0) {
                PulseMenuRow(title: "Вернуть маскота в угол") { act { app.panel?.resetPosition() } }
                PulseMenuRow(title: "Настройки", keys: "⌘,") { act { app.showSettings() } }
                    .keyboardShortcut(",")
                PulseMenuRow(title: "Выйти", keys: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(ConsoleStyle.inset)
        .frame(width: Self.width, alignment: .topLeading)
        .background(Color.black)
    }

    private func act(_ action: () -> Void) {
        dismiss()
        action()
    }

    @ViewBuilder
    private func status(_ model: PulseModel) -> some View {
        let active = model.activeSessions
        VStack(alignment: .leading, spacing: 4) {
            if active.isEmpty {
                Text("Сейчас никто не работает")
                    .font(ConsoleStyle.font(13, .medium))
                    .foregroundStyle(ConsoleStyle.caption)
            } else {
                ForEach(active.prefix(6)) { session in
                    HStack(spacing: 8) {
                        Circle().fill(ConsoleStyle.green).frame(width: 6, height: 6)
                        Text("\(BubbleCategory.sessionTitle(session)) — \(session.phase.text)")
                            .font(ConsoleStyle.font(13, .medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                }
            }
            if let error = model.serverError {
                Text("Сокет недоступен: \(error)").font(ConsoleStyle.font(11)).foregroundStyle(ConsoleStyle.red).lineLimit(2)
            }
            if !model.hooksInstalled {
                PrompterSmallButton(title: "Подключить Claude Code") { act { app.showSettings(.sources) } }
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func reactionCard(_ model: PulseModel, line: String) -> some View {
        ConsoleCard(fills: false) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Последняя реакция").font(ConsoleStyle.font(11)).foregroundStyle(ConsoleStyle.caption)
                    Text(line).font(ConsoleStyle.font(13, .medium)).foregroundStyle(.white).lineLimit(2)
                }
                HStack(spacing: 8) {
                    PrompterSmallButton(title: "Мило", wide: true) { act { model.feedback("мило") } }
                    PrompterSmallButton(title: "Бесит", wide: true) { act { model.feedback("бесит") } }
                }
            }
        }
    }
}

private struct PulseMenuRow: View {
    let title: String
    var keys: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PulseMenuHover {
                HStack {
                    Text(title).font(ConsoleStyle.font(13, .medium)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 8)
                    if let keys { Text(keys).font(.system(size: 12)).foregroundStyle(ConsoleStyle.caption) }
                }
            }
        }
        .buttonStyle(ConsolePressStyle())
    }
}

private struct PulseMenuSwitch: View {
    let title: String
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        Button { set(!isOn) } label: {
            PulseMenuHover {
                HStack {
                    Text(title).font(ConsoleStyle.font(13, .medium)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 8)
                    ConsoleSwitch(isOn: isOn)
                }
            }
        }
        .buttonStyle(ConsolePressStyle())
        .accessibilityValue(isOn ? "Включено" : "Выключено")
    }
}

/// Подсветка строки под курсором.
private struct PulseMenuHover<Content: View>: View {
    @ViewBuilder let content: Content
    // Обычный @State без Xcode недоступен: его макрос лежит только там.
    private let hovering = State(initialValue: false)

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                hovering.wrappedValue ? ConsoleStyle.card : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
            .onHover { hovering.wrappedValue = $0 }
    }
}

/// Меню по правому клику на маскоте. Закрывается кликом мимо и Esc, не активирует приложение.
@MainActor
final class PulseMenuPanel: NSPanel {
    private var monitors: [Any] = []

    init(app: AppDelegate) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PulseMenuView.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = OverlayPanel.spaceBehavior.union(.fullScreenAuxiliary)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        let view = PulseMenuView(app: app) { [weak self] in self?.close() }
            .clipShape(RoundedRectangle(cornerRadius: ConsoleStyle.surfaceRadius - 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ConsoleStyle.surfaceRadius - 8, style: .continuous)
                    .strokeBorder(ConsoleStyle.edge, lineWidth: 1)
            }
        contentView = NSHostingView(rootView: view)
    }

    override var canBecomeKey: Bool { true }

    /// Стоит у курсора и не выходит за видимую часть экрана.
    func show(at point: NSPoint) {
        guard let host = contentView else { return }
        let size = host.fittingSize
        let visible = NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(visible.minX + 8, point.x - size.width), visible.maxX - size.width - 8)
        let y = min(max(visible.minY + 8, point.y), visible.maxY - size.height - 8)
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(outside) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            let closes = event.type == .keyDown ? event.keyCode == 53 : event.windowNumber != self?.windowNumber
            if closes { MainActor.assumeIsolated { self?.close() } }
            return event.type == .keyDown && closes ? nil : event
        }) { monitors.append(local) }
    }

    override func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        orderOut(nil)
    }
}
