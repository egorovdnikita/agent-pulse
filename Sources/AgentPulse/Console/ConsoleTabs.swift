import AgentPulseCore
import AppKit
import SwiftUI

private let tabFont = ConsoleStyle.font(13, .medium)
private let noteFont = ConsoleStyle.font(11).monospacedDigit()

@MainActor private func solar(_ name: String, _ size: Double) -> some View {
    Image(nsImage: SolarIcons.image(name) ?? NSImage()).resizable().frame(width: size, height: size).foregroundStyle(.white)
}

// MARK: - Календарь

private struct EventRow: View {
    let model: ConsoleModel
    let event: MeetingEvent
    let showsDay: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(time).font(noteFont).foregroundStyle(ConsoleStyle.caption).frame(width: showsDay ? 72 : 40, alignment: .leading)
            Text(event.title).font(tabFont).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 4)
            if let link = event.link, event.end > model.now {
                Button("Войти") { model.onJoin?(link.url) }
                    .buttonStyle(.plain).font(tabFont).foregroundStyle(ConsoleStyle.orange)
            }
        }
    }

    private var time: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = showsDay ? "EE, d, HH:mm" : "HH:mm"
        return event.isAllDay ? (showsDay ? "весь день" : "день") : formatter.string(from: event.start)
    }
}

private struct MonthGrid: View {
    let model: ConsoleModel

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: model.now)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let days = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        // Понедельник — первая колонка.
        let lead = (calendar.component(.weekday, from: start) + 5) % 7
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
            ForEach(["пн", "вт", "ср", "чт", "пт", "сб", "вс"], id: \.self) { Text($0).font(noteFont).foregroundStyle(ConsoleStyle.caption) }
            ForEach(0..<(lead + days), id: \.self) { index in
                if index < lead {
                    Color.clear.frame(height: 24)
                } else if let day = calendar.date(byAdding: .day, value: index - lead, to: start) {
                    Button {
                        model.calendarDay = day
                        model.calendarScope = .day
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(index - lead + 1)").font(noteFont)
                                .foregroundStyle(calendar.isDate(day, inSameDayAs: today) ? ConsoleStyle.orange : .white)
                            Circle().fill(model.calendar.events(on: day).isEmpty ? Color.clear : Color(hex: model.calendar.accent)).frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct CalendarTab: View {
    let model: ConsoleModel

    var body: some View {
        ConsoleCard {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ForEach(CalendarScope.allCases, id: \.self) { scope in
                    Button(scope.title) {
                        model.calendarDay = model.now
                        model.calendarScope = scope
                    }
                    .buttonStyle(.plain).font(tabFont)
                    .foregroundStyle(.white.opacity(model.calendarScope == scope ? 1 : 0.5))
                }
            }
            switch model.calendarScope {
            case .month:
                MonthGrid(model: model)
            case .day, .week:
                let events = listed
                if events.isEmpty {
                    Text("Встреч нет").font(noteFont).foregroundStyle(ConsoleStyle.caption)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(events) { EventRow(model: model, event: $0, showsDay: model.calendarScope == .week) }
                        }
                    }
                }
            }
        }
    }

    private var listed: [MeetingEvent] {
        let calendar = Calendar.current
        if model.calendarScope == .day { return model.calendar.events(on: model.calendarDay) }
        let start = calendar.startOfDay(for: model.now)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return model.calendar.events.filter { $0.start < end && $0.end > start }
    }
}

// MARK: - Полка

/// Строка полки: файл вытаскивается наружу, и после этого его на полке нет.
private final class ShelfDragView: NSView, NSDraggingSource {
    var url: URL?
    var onDropped: ((URL) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDragged(with event: NSEvent) {
        guard let url else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let location = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: location.x - 16, y: location.y - 16, width: 32, height: 32), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [], let url { onDropped?(url) }
    }
}

private struct ShelfDragArea: NSViewRepresentable {
    let url: URL
    let onDropped: (URL) -> Void

    func makeNSView(context: Context) -> ShelfDragView { ShelfDragView() }

    func updateNSView(_ view: ShelfDragView, context: Context) {
        view.url = url
        view.onDropped = onDropped
    }
}

struct ShelfTab: View {
    let model: ConsoleModel

    var body: some View {
        if model.shelf.items.isEmpty {
            ConsoleCard { Text("Брось файл на Пульт или на маскота").font(tabFont).foregroundStyle(ConsoleStyle.caption) }
        } else {
            ConsoleCard { files }
        }
    }

    private var files: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.shelf.items.reversed()) { item in
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 20, height: 20)
                                Text(item.name).font(tabFont).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 4)
                                Button { model.removeFromShelf(item.url) } label: { solar("close-circle", 14).opacity(0.5) }
                                    .buttonStyle(.plain).accessibilityLabel("Убрать с полки")
                            }
                            .background(ShelfDragArea(url: item.url) { model.removeFromShelf($0) })
                        }
                    }
                }
                Button("Очистить") { model.clearShelf() }.buttonStyle(.plain).font(noteFont).foregroundStyle(ConsoleStyle.caption)
            }
        }
    }
}

// MARK: - Музыка

struct MediaTab: View {
    let model: ConsoleModel

    private func clock(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    var body: some View {
        if model.media.availability == .unavailable {
            VStack(alignment: .leading, spacing: 8) {
                Text("Недоступно на этой системе").font(tabFont).foregroundStyle(.white)
                Button("Управлять «Музыкой» и Spotify") { model.onConnectMusic?() }
                    .buttonStyle(.plain).font(noteFont).foregroundStyle(ConsoleStyle.orange)
            }
        } else if let playing = model.media.playing {
            ConsoleCard { player(playing) }
        } else {
            ConsoleCard { Text("Сейчас ничего не играет").font(tabFont).foregroundStyle(ConsoleStyle.caption) }
        }
    }

    private func player(_ playing: NowPlaying) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Group {
                        if let artwork = model.artwork {
                            Image(nsImage: artwork).resizable().scaledToFill()
                        } else {
                            solar("music-note", 24).opacity(0.5).frame(maxWidth: .infinity, maxHeight: .infinity).background(ConsoleStyle.card)
                        }
                    }
                    .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playing.title).font(tabFont).foregroundStyle(.white).lineLimit(2)
                        if let artist = playing.artist { Text(artist).font(noteFont).foregroundStyle(ConsoleStyle.caption).lineLimit(1) }
                    }
                }
                if let duration = playing.duration {
                    VStack(spacing: 0) {
                    ThinSlider(value: playing.position(now: model.now), range: 0...duration, label: "Позиция") { model.onSeek?($0) }
                    HStack {
                        Text(clock(playing.position(now: model.now)))
                        Spacer()
                        Text(clock(duration))
                    }
                    .font(noteFont).foregroundStyle(ConsoleStyle.caption)
                    }
                }
                HStack(spacing: 18) {
                    control("skip-previous", "Предыдущий", .previous)
                    control(playing.isPlaying ? "pause" : "play", playing.isPlaying ? "Пауза" : "Играть", .togglePlayPause)
                    control("skip-next", "Следующий", .next)
                    if model.volume != nil {
                        ThinSlider(value: model.volume ?? 0, range: 0...1, label: "Громкость") { model.onVolume?($0) }
                    }
                }
            }
    }

    private func control(_ icon: String, _ label: String, _ command: MediaCommand) -> some View {
        Button { model.onMediaCommand?(command) } label: { solar(icon, 18) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
}

// MARK: - Суфлёр

/// Поле текста. Файлы принимает вкладка: NSTextView вставил бы вместо них путь.
private struct PrompterEditor: NSViewRepresentable {
    final class TextView: NSTextView {
        override func updateDragTypeRegistration() { unregisterDraggedTypes() }
    }

    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let view = TextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textColor = .white
        view.insertionPointColor = .white
        view.font = ConsoleStyle.nsFont(13)
        view.textContainerInset = NSSize(width: 6, height: 6)
        view.isVerticallyResizable = true
        view.autoresizingMask = .width
        view.textContainer?.widthTracksTextView = true
        view.string = text
        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        if let view = scroll.documentView as? NSTextView, view.string != text { view.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}

struct PrompterSmallButton: View {
    let title: String
    var strong = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ConsoleStyle.font(12, .medium))
                .foregroundStyle(strong ? .black : .white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, title.count == 1 ? 0 : 12)
                .frame(width: title.count == 1 ? 28 : nil, height: 28)
                .background(strong ? Color.white : ConsoleStyle.button, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Вкладка «Суфлёр»: текст, скорость, голос. Тексты хранятся только на этом Mac.
struct PrompterTab: View {
    @Bindable var model: ConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.prompter.isActive {
                running
            } else if model.prompterRecentOpen {
                recent
            } else {
                editor
            }
            if !model.prompterRecentOpen || model.prompter.isActive { controls }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                PrompterEditor(text: $model.prompterDraft)
                if model.prompterDraft.isEmpty {
                    Text("Вставь текст или перетащи .txt и .md")
                        .font(ConsoleStyle.font(13))
                        .foregroundStyle(ConsoleStyle.caption)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .background(ConsoleStyle.card, in: RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius - 8, style: .continuous))
            HStack(spacing: 8) {
                if !model.prompterLibrary.texts.isEmpty {
                    PrompterSmallButton(title: "Недавние") { model.prompterRecentOpen = true }
                }
                Spacer()
                if !model.prompterDraft.isEmpty {
                    PrompterSmallButton(title: "Очистить") { model.prompterDraft = "" }
                }
                PrompterSmallButton(title: "Старт", strong: true) { model.startPrompter() }
                    .disabled(model.prompterDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(model.prompterDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.prompterLibrary.texts, id: \.self) { text in
                HStack(spacing: 8) {
                    Button {
                        model.prompterDraft = text
                        model.prompterRecentOpen = false
                    } label: {
                        Text(text.replacingOccurrences(of: "\n", with: " "))
                            .font(ConsoleStyle.font(12))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button("Удалить") {
                        model.forgetPrompterText(text)
                        if model.prompterLibrary.texts.isEmpty { model.prompterRecentOpen = false }
                    }
                    .buttonStyle(.plain)
                    .font(ConsoleStyle.font(11))
                    .foregroundStyle(ConsoleStyle.caption)
                }
            }
            Spacer(minLength: 0)
            PrompterSmallButton(title: "Назад") { model.prompterRecentOpen = false }
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(PrompterModule.clock(model.prompter.elapsed)) из \(PrompterModule.clock(model.prompter.total))")
                .font(ConsoleStyle.font(22, .semibold).monospacedDigit())
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                PrompterSmallButton(title: model.prompter.mode == .paused ? "Дальше" : "Пауза") { model.togglePrompterPause() }
                PrompterSmallButton(title: "Стоп") { model.stopPrompter() }
            }
            Spacer(minLength: 0)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                PrompterSmallButton(title: "−") { model.changePrompterSpeed(faster: false) }
                Text("\(model.prompter.speed) сл/мин")
                    .font(ConsoleStyle.font(12).monospacedDigit())
                    .foregroundStyle(ConsoleStyle.caption)
                    .lineLimit(1)
                    .fixedSize()
                PrompterSmallButton(title: "+") { model.changePrompterSpeed(faster: true) }
                Spacer(minLength: 4)
                Text("За голосом")
                    .font(ConsoleStyle.font(12))
                    .foregroundStyle(ConsoleStyle.caption)
                    .lineLimit(1)
                    .fixedSize()
                Toggle("За голосом", isOn: Binding(
                    get: { model.prompter.followsVoice }, set: { model.onPrompterVoiceToggle?($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(ConsoleStyle.green)
            }
            if let problem = model.prompterVoiceProblem {
                Text(problem)
                    .font(ConsoleStyle.font(11))
                    .foregroundStyle(ConsoleStyle.orange)
            }
        }
    }
}

/// Вкладка «Перевод»: появляется по ⌃⌥T и уходит вместе с Пультом.
struct TranslateTab: View {
    let model: ConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.translate.state {
            case .idle:
                EmptyView()
            case .askToCopy:
                hint(TranslateModule.askToCopyHint)
            case .working:
                hint("Перевожу…")
            case .failed(let problem):
                hint(problem)
            case .done(let source, let result):
                Text(TranslateDirection.detect(source).title)
                    .font(ConsoleStyle.font(11, .semibold))
                    .foregroundStyle(ConsoleStyle.caption)
                ScrollView {
                    Text(result)
                        .font(ConsoleStyle.font(14))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    PrompterSmallButton(title: "Скопировать") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                    }
                    if model.translate.replaceable {
                        PrompterSmallButton(title: "Заменить выделенное") { model.onTranslateReplace?(result) }
                    }
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(ConsoleStyle.font(13))
            .foregroundStyle(ConsoleStyle.caption)
            .fixedSize(horizontal: false, vertical: true)
    }
}
