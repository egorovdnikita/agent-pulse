import AgentPulseCore
import AppKit
import Observation
import SwiftUI

/// Меню в строке меню и по правому клику на маскоте: только то, что нужно каждый день.
/// Своё, а не системное: системное меню не принимает язык Пульта. Всё остальное — в окне «Настройки».
struct PulseMenuView: View {
    let app: AppDelegate
    let dismiss: () -> Void

    static let width = 260.0

    var body: some View {
        let model = app.model
        VStack(alignment: .leading, spacing: 0) {
            status(model).padding(.vertical, 4)
            divider
            // Реакция без реплики: оценивать нечего, а её внутреннее имя показывать нельзя.
            if model.lastReaction != nil, let line = model.lastLine, !line.isEmpty {
                reaction(model, line: line).padding(.vertical, 6)
                divider
            }
            PulseMenuSwitch(title: "Показывать маскота", isOn: model.overlayVisible) { app.setOverlayVisible($0) }
            PulseMenuSwitch(title: "Рассказывать новости", isOn: model.config.character.designNews) { app.setDesignNews($0) }
            divider
            PulseMenuRow(title: "Настройки", keys: "⌘,") { act { app.showSettings() } }
                .keyboardShortcut(",")
            PulseMenuRow(title: "Выйти", keys: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(5)
        .frame(width: Self.width, alignment: .topLeading)
        .background(SettingsStyle.window)
    }

    private var divider: some View {
        Rectangle().fill(SettingsStyle.ring).frame(height: 1).padding(.horizontal, 9).padding(.vertical, 4)
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
                Text("Сейчас никто не работает").font(SettingsStyle.body).foregroundStyle(SettingsStyle.muted)
            } else {
                ForEach(active.prefix(6)) { session in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(ConsoleStyle.green).frame(width: 6, height: 6).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(BubbleCategory.sessionTitle(session)).font(SettingsStyle.bodyMedium).foregroundStyle(SettingsStyle.text).lineLimit(1)
                            Text(session.phase.text).font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted).lineLimit(1)
                        }
                    }
                }
            }
            if model.serverError != nil {
                Text("Не вижу агентов. Перезапусти приложение").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.destructive).lineLimit(2)
            }
            if !model.hooksInstalled {
                Button("Подключить Claude Code") { act { app.showSettings(.sources) } }
                    .buttonStyle(SettingsButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 9)
    }

    private func reaction(_ model: PulseModel, line: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Как тебе эта реплика?").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                Text("«\(line)»").font(SettingsStyle.bodyMedium).foregroundStyle(SettingsStyle.text).lineLimit(2)
            }
            HStack(spacing: 6) {
                Button("Нравится") { act { model.feedback("мило") } }
                Button("Больше не надо") { act { model.feedback("бесит") } }
            }
            .buttonStyle(SettingsButtonStyle())
        }
        .padding(.horizontal, 9)
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
                    Text(title).font(SettingsStyle.body).foregroundStyle(SettingsStyle.text).lineLimit(1)
                    Spacer(minLength: 8)
                    if let keys { Text(keys).font(.system(size: 12)).foregroundStyle(SettingsStyle.muted) }
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
                    Text(title).font(SettingsStyle.body).foregroundStyle(SettingsStyle.text).lineLimit(1)
                    Spacer(minLength: 8)
                    ConsoleSwitch(isOn: isOn, on: SettingsStyle.accent, off: SettingsStyle.switchOff)
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
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                hovering.wrappedValue ? SettingsStyle.hover : .clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
            .onHover { hovering.wrappedValue = $0 }
    }
}

/// Состояние раскрытия меню.
@MainActor
@Observable
private final class MenuReveal {
    var open = false
    var contentShown = false
    var size = CGSize(width: PulseMenuView.width, height: 200)
}

/// Форма меню вырастает из точки клика, как Пульт из капсулы: содержимое стоит на месте и проявляется в ней.
private struct PulseMenuSurface: View {
    let reveal: MenuReveal
    let content: PulseMenuView
    static let shadowRoom = 24.0
    static let startSize = 44.0

    var body: some View {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let open = reveal.open
        let width = open ? reveal.size.width : Self.startSize
        let height = open ? reveal.size.height : Self.startSize
        let shape = RoundedRectangle(cornerRadius: open ? 12 : Self.startSize / 2, style: .continuous)
        ZStack(alignment: .bottomTrailing) {
            shape.fill(SettingsStyle.window)
                .frame(width: width, height: height)
                .consoleShadow()
            content
                .opacity(reveal.contentShown ? 1 : 0)
                .animation(ConsoleStyle.contentMotion(appearing: reveal.contentShown, reduced: reduce), value: reveal.contentShown)
                .mask(alignment: .bottomTrailing) { shape.frame(width: width, height: height) }
            shape.strokeBorder(SettingsStyle.ring, lineWidth: 1).frame(width: width, height: height)
            shape.strokeBorder(ConsoleStyle.edge, lineWidth: 1).frame(width: width, height: height)
        }
        .frame(width: reveal.size.width, height: reveal.size.height, alignment: .bottomTrailing)
        .animation(ConsoleStyle.panelMotion(opening: open, reduced: reduce), value: open)
        .padding(Self.shadowRoom)
    }
}

/// Меню по правому клику на маскоте. Закрывается кликом мимо и Esc, не активирует приложение.
@MainActor
final class PulseMenuPanel: NSPanel {
    private var monitors: [Any] = []
    private let reveal = MenuReveal()
    private let measuredMenu: PulseMenuView
    private var hideTask: Task<Void, Never>?

    init(app: AppDelegate) {
        measuredMenu = PulseMenuView(app: app) {}
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PulseMenuView.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = OverlayPanel.spaceBehavior.union(.fullScreenAuxiliary)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        let view = PulseMenuSurface(reveal: reveal, content: PulseMenuView(app: app) { [weak self] in self?.close() })
        contentView = NSHostingView(rootView: view)
    }

    override var canBecomeKey: Bool { true }

    /// Стоит у курсора и не выходит за видимую часть экрана. Правый нижний угол меню — точка клика.
    func show(at point: NSPoint) {
        hideTask?.cancel()
        let measured = NSHostingView(rootView: measuredMenu).fittingSize
        reveal.size = measured
        reveal.open = false
        reveal.contentShown = false
        let room = PulseMenuSurface.shadowRoom
        let visible = NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(visible.minX + 8, point.x - measured.width), visible.maxX - measured.width - 8)
        let y = min(max(visible.minY + 8, point.y), visible.maxY - measured.height - 8)
        setFrame(
            NSRect(x: x - room, y: y - room, width: measured.width + room * 2, height: measured.height + room * 2), display: true
        )
        orderFrontRegardless()
        makeKey()
        DispatchQueue.main.async { [reveal] in
            MainActor.assumeIsolated {
                reveal.open = true
                reveal.contentShown = true
            }
        }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(outside) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            let closes = event.type == .keyDown ? event.keyCode == 53 : event.windowNumber != self?.windowNumber
            if closes { MainActor.assumeIsolated { self?.close() } }
            return event.type == .keyDown && closes ? nil : event
        }) { monitors.append(local) }
    }

    /// На выходе форма уходит обратно в точку клика, и только потом окно прячется.
    override func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reveal.contentShown = false
        reveal.open = false
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(ConsoleLook.closeMilliseconds))
            guard !Task.isCancelled else { return }
            self?.orderOut(nil)
        }
    }
}
