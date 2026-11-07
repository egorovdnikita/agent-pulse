import AgentPulseCore
import AppKit
import SwiftUI

private let tabFont = ConsoleStyle.font(13, .medium)
private let noteFont = ConsoleStyle.font(11).monospacedDigit()

@MainActor private func solar(_ name: String, _ size: Double) -> some View {
    Image(nsImage: SolarIcons.image(name) ?? NSImage()).resizable().frame(width: size, height: size).foregroundStyle(.white)
}

// MARK: - Календарь

private enum CalendarText {
    static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = format
        return formatter
    }

    /// «Сегодня», «Завтра», дальше — день недели и число.
    static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Сегодня" }
        if let next = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: next) { return "Завтра" }
        return formatter("EE, d MMMM").string(from: date)
    }
}

private struct EventRow: View {
    let model: ConsoleModel
    let event: MeetingEvent

    var body: some View {
        let running = event.start <= model.now && event.end > model.now
        let over = event.end <= model.now
        HStack(spacing: 10) {
            Capsule()
                .fill(running ? ConsoleStyle.green : ConsoleStyle.track)
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(tabFont).foregroundStyle(.white).lineLimit(1)
                Text(detail(running: running)).font(noteFont).foregroundStyle(running ? ConsoleStyle.green : ConsoleStyle.caption).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let link = event.link, !over {
                PrompterSmallButton(title: "Войти", tint: ConsoleStyle.orange) { model.onJoin?(link.url) }
            }
        }
        .opacity(over ? 0.5 : 1)
    }

    private func detail(running: Bool) -> String {
        if event.isAllDay { return "Весь день" }
        let minutes = Int(event.start.timeIntervalSince(model.now) / 60)
        if running { return "Идёт, ещё \(max(1, Int(event.end.timeIntervalSince(model.now) / 60))) мин" }
        if minutes >= 0, minutes < 60 { return "Через \(max(1, minutes)) мин" }
        let clock = CalendarText.formatter("HH:mm")
        return "\(clock.string(from: event.start)) – \(clock.string(from: event.end))"
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
            ForEach(["пн", "вт", "ср", "чт", "пт", "сб", "вс"], id: \.self) {
                Text($0).font(ConsoleStyle.font(11)).foregroundStyle(ConsoleStyle.caption)
            }
            ForEach(0..<(lead + days), id: \.self) { index in
                if index < lead {
                    Color.clear.frame(height: 20)
                } else if let day = calendar.date(byAdding: .day, value: index - lead, to: start) {
                    cell(day, number: index - lead + 1, isToday: calendar.isDate(day, inSameDayAs: today))
                }
            }
        }
    }

    private func cell(_ day: Date, number: Int, isToday: Bool) -> some View {
        Button {
            model.calendarDay = day
            model.calendarScope = .day
        } label: {
            ZStack {
                if isToday { Circle().fill(.white).frame(width: 20, height: 20) }
                if !isToday, model.calendarScope == .day, Calendar.current.isDate(day, inSameDayAs: model.calendarDay) {
                    Circle().strokeBorder(.white, lineWidth: 1).frame(width: 20, height: 20)
                }
                Text("\(number)").font(noteFont).foregroundStyle(isToday ? .black : .white)
                if !model.calendar.events(on: day).isEmpty {
                    Circle().fill(isToday ? Color.black : ConsoleStyle.orange).frame(width: 3, height: 3).offset(y: 7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(ConsolePressStyle())
        .accessibilityLabel(CalendarText.day(day, now: model.now))
    }
}

struct CalendarTab: View {
    let model: ConsoleModel

    var body: some View {
        HStack(spacing: 8) {
            ConsoleCard(padding: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CalendarText.formatter("LLLL yyyy").string(from: model.now).capitalized)
                        .font(ConsoleStyle.font(13, .semibold))
                        .foregroundStyle(.white)
                    MonthGrid(model: model)
                }
            }
            .frame(width: 236)
            VStack(spacing: 6) {
                ConsoleSegments(values: [CalendarScope.day, .week], selected: model.calendarScope, title: \.title) { scope in
                    model.calendarDay = model.now
                    model.calendarScope = scope
                }
                ConsoleCard {
                    if model.calendarScope == .week { weekPage } else { dayPage }
                }
            }
        }
    }

    private var dayPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(CalendarText.day(model.calendarDay, now: model.now))
                    .font(ConsoleStyle.font(13, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                dayButton("alt-arrow-left", "Предыдущий день", -1)
                dayButton("alt-arrow-right", "Следующий день", 1)
            }
            let events = model.calendar.events(on: model.calendarDay)
            if events.isEmpty {
                ConsoleEmpty(icon: "calendar", title: "Встреч нет")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(events) { EventRow(model: model, event: $0) }
                    }
                }
            }
        }
    }

    private func dayButton(_ icon: String, _ label: String, _ step: Int) -> some View {
        Button {
            model.calendarDay = Calendar.current.date(byAdding: .day, value: step, to: model.calendarDay) ?? model.calendarDay
        } label: {
            solar(icon, 14).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(ConsolePressStyle())
        .accessibilityLabel(label)
    }

    private var weekPage: some View {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: model.now)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            .filter { !model.calendar.events(on: $0).isEmpty }
        return Group {
            if days.isEmpty {
                ConsoleEmpty(icon: "calendar", title: "На неделе встреч нет")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(days, id: \.self) { day in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(CalendarText.day(day, now: model.now))
                                    .font(ConsoleStyle.font(11, .semibold))
                                    .foregroundStyle(ConsoleStyle.caption)
                                ForEach(model.calendar.events(on: day)) { EventRow(model: model, event: $0) }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Полка

/// Файл вытаскивается наружу как из Finder, и после этого его на полке нет.
/// Вид лежит поверх плитки и сам ловит нажатие: снизу до него мышь не доходит.
private final class ShelfDragView: NSView, NSDraggingSource {
    var url: URL?
    var onDropped: ((URL) -> Void)?
    private var pressedAt: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressedAt = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let url, let start = pressedAt else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
        pressedAt = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let side = 48.0
        item.setDraggingFrame(
            NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side),
            contents: NSWorkspace.shared.icon(forFile: url.path)
        )
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        pressedAt = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.move, .copy, .generic, .link] : []
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

/// Лист с загнутым углом: один для всех форматов, различает их цветная метка.
private struct PageGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.width / 30, y = rect.height / 38
        let point = { (px: Double, py: Double) in CGPoint(x: rect.minX + px * x, y: rect.minY + py * y) }
        var path = Path()
        path.move(to: point(4, 1))
        path.addLine(to: point(19, 1))
        path.addLine(to: point(29, 11))
        path.addLine(to: point(29, 33))
        path.addQuadCurve(to: point(25, 37), control: point(29, 37))
        path.addLine(to: point(4, 37))
        path.addQuadCurve(to: point(0, 33), control: point(0, 37))
        path.addLine(to: point(0, 5))
        path.addQuadCurve(to: point(4, 1), control: point(0, 1))
        path.closeSubpath()
        return path
    }
}

private extension ShelfFileKind {
    var color: Color {
        switch self {
        case .pdf: ConsoleStyle.red
        case .presentation: ConsoleStyle.orange
        case .document: Color(hex: 0x0A84FF)
        case .spreadsheet: ConsoleStyle.green
        case .archive, .image, .other: Color(hex: 0x8E8E93)
        }
    }
}

/// Плитка файла: превью картинки или лист с меткой формата, имя в две строки.
private struct ShelfTile: View {
    let model: ConsoleModel
    let item: ShelfItem
    static let size = 76.0

    // Обычный @State без Xcode недоступен: его макрос лежит только там.
    private let hovering = State(initialValue: false)

    init(model: ConsoleModel, item: ShelfItem) {
        self.model = model
        self.item = item
    }

    var body: some View {
        VStack(spacing: 6) {
            preview
                .overlay { ShelfDragArea(url: item.url) { model.removeFromShelf($0) } }
                .overlay(alignment: .topTrailing) {
                    if hovering.wrappedValue {
                        Button { model.removeFromShelf(item.url) } label: {
                            solar("close-circle", 18)
                        }
                        .buttonStyle(ConsolePressStyle())
                        .offset(x: 5, y: -5)
                        .accessibilityLabel("Убрать с полки")
                    }
                }
            Text(item.name)
                .font(ConsoleStyle.font(11))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(width: Self.size, height: 28, alignment: .top)
        }
        .frame(width: Self.size)
        .onHover { hovering.wrappedValue = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.name)
    }

    private var preview: some View {
        let kind = ShelfFileKind(name: item.name)
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0x1F / 255))
            if kind == .image, let image = model.shelfPreviews[item.url] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ConsoleStyle.edge, lineWidth: 1))
            } else {
                PageGlyph()
                    .fill(.white.opacity(0.92))
                    .frame(width: 30, height: 38)
                    .overlay(alignment: .bottomLeading) {
                        if let badge = ShelfFileKind.badge(name: item.name) {
                            Text(badge)
                                .font(ConsoleStyle.font(8, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .frame(height: 11)
                                .background(kind.color, in: RoundedRectangle(cornerRadius: 3))
                                .fixedSize()
                                .offset(x: -5, y: 7)
                        }
                    }
            }
        }
        .frame(width: Self.size, height: Self.size)
    }
}

struct ShelfTab: View {
    let model: ConsoleModel

    var body: some View {
        Group {
            if model.shelf.items.isEmpty {
                ConsoleCard {
                    ConsoleEmpty(icon: "folder-with-files", title: "Полка пуста", hint: "Брось файл на Пульт или на маскота")
                }
            } else {
                files
            }
        }
        .overlay {
            if model.dropTargeted {
                RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: ShelfTile.size, maximum: ShelfTile.size), spacing: 12)], alignment: .leading, spacing: 8) {
                    ForEach(model.shelf.items.reversed()) { ShelfTile(model: model, item: $0) }
                }
                .padding(.top, 6)
                .padding(.horizontal, 4)
            }
            HStack {
                Text("Потяни файл, чтобы забрать").font(noteFont).foregroundStyle(ConsoleStyle.caption).lineLimit(1)
                Spacer(minLength: 4)
                Button("Очистить") { model.clearShelf() }
                    .buttonStyle(ConsolePressStyle()).font(ConsoleStyle.font(11, .medium)).foregroundStyle(.white)
            }
            .padding(.horizontal, 4)
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
        if let playing = model.media.playing, model.media.availability != .unavailable {
            player(playing)
        } else {
            ConsoleCard {
                if model.media.availability == .unavailable {
                    VStack(spacing: 10) {
                        ConsoleEmpty(icon: "music-note", title: "Недоступно на этой системе")
                        PrompterSmallButton(title: "Управлять «Музыкой» и Spotify") { model.onConnectMusic?() }
                    }
                } else {
                    ConsoleEmpty(icon: "music-note", title: "Сейчас ничего не играет")
                }
            }
        }
    }

    private func player(_ playing: NowPlaying) -> some View {
        HStack(spacing: 16) {
            Group {
                if let artwork = model.artwork {
                    Image(nsImage: artwork).resizable().scaledToFill()
                } else {
                    solar("music-note", 40).opacity(0.5).frame(maxWidth: .infinity, maxHeight: .infinity).background(ConsoleStyle.card)
                }
            }
            .frame(width: 178, height: 178).clipShape(RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(playing.title).font(ConsoleStyle.font(15, .semibold)).foregroundStyle(.white).lineLimit(1).padding(.top, 8)
                if let artist = playing.artist {
                    Text(artist).font(ConsoleStyle.font(13)).foregroundStyle(ConsoleStyle.caption).lineLimit(1).padding(.top, 2)
                }
                Spacer(minLength: 6)
                if let duration = playing.duration {
                    ThinSlider(value: playing.position(now: model.now), range: 0...duration, label: "Позиция") { model.onSeek?($0) }
                    HStack {
                        Text(clock(playing.position(now: model.now)))
                        Spacer()
                        Text(clock(duration))
                    }
                    .font(noteFont).foregroundStyle(ConsoleStyle.caption)
                }
                Spacer(minLength: 6)
                HStack(spacing: 14) {
                    control("skip-previous", "Предыдущий", .previous, size: 20)
                    playButton(playing)
                    control("skip-next", "Следующий", .next, size: 20)
                    Spacer(minLength: 12)
                    if model.volume != nil {
                        solar("volume-loud", 14).opacity(0.55)
                        ThinSlider(value: model.volume ?? 0, range: 0...1, label: "Громкость") { model.onVolume?($0) }
                            .frame(width: 96)
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(.trailing, 4)
        }
    }

    private func playButton(_ playing: NowPlaying) -> some View {
        Button { model.onMediaCommand?(.togglePlayPause) } label: {
            Image(nsImage: SolarIcons.image(playing.isPlaying ? "pause" : "play") ?? NSImage())
                .resizable()
                .frame(width: 18, height: 18)
                .foregroundStyle(.black)
                .frame(width: 40, height: 40)
                .background(.white, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(ConsolePressStyle())
        .accessibilityLabel(playing.isPlaying ? "Пауза" : "Играть")
    }

    private func control(_ icon: String, _ label: String, _ command: MediaCommand, size: Double) -> some View {
        Button { model.onMediaCommand?(command) } label: {
            solar(icon, size).frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(ConsolePressStyle())
        .accessibilityLabel(label)
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
    /// Цветная кнопка: главное действие строки.
    var tint: Color?
    /// Занимает всю ширину колонки.
    var wide = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ConsoleStyle.font(13, .medium))
                .foregroundStyle(strong || tint != nil ? .black : .white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, title.count == 1 || wide ? 0 : 12)
                .frame(width: title.count == 1 ? 28 : nil, height: 28)
                .frame(maxWidth: wide ? .infinity : nil)
                .background(tint ?? (strong ? Color.white : ConsoleStyle.button), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(ConsolePressStyle())
    }
}

/// Вкладка «Суфлёр»: слева текст, справа управление. Тексты хранятся только на этом Mac.
struct PrompterTab: View {
    @Bindable var model: ConsoleModel

    var body: some View {
        HStack(spacing: 8) {
            if model.prompter.isActive {
                running
            } else if model.prompterRecentOpen {
                recent
            } else {
                editor
            }
            controls.frame(width: 176)
        }
    }

    private var hasText: Bool {
        !model.prompterDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var editor: some View {
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
        .overlay(alignment: .bottomTrailing) {
            if let estimate = model.prompterEstimate {
                Text(estimate).font(noteFont).foregroundStyle(ConsoleStyle.caption).padding(10).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if hasText {
                Button("Очистить") { model.prompterDraft = "" }
                    .buttonStyle(ConsolePressStyle())
                    .font(ConsoleStyle.font(11, .medium))
                    .foregroundStyle(ConsoleStyle.caption)
                    .padding(10)
            }
        }
        .background(ConsoleStyle.card, in: RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius, style: .continuous))
    }

    private var recent: some View {
        ConsoleCard {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.prompterLibrary.texts, id: \.self) { text in
                        HStack(spacing: 8) {
                            Button {
                                model.prompterDraft = text
                                model.prompterRecentOpen = false
                            } label: {
                                Text(text.replacingOccurrences(of: "\n", with: " "))
                                    .font(tabFont)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(ConsolePressStyle())
                            Button {
                                model.forgetPrompterText(text)
                                if model.prompterLibrary.texts.isEmpty { model.prompterRecentOpen = false }
                            } label: { solar("close-circle", 16).opacity(0.5) }
                            .buttonStyle(ConsolePressStyle())
                            .accessibilityLabel("Удалить")
                        }
                    }
                }
            }
        }
    }

    private var running: some View {
        ConsoleCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.prompter.mode == .paused ? "Пауза" : model.prompter.followsVoice ? "Идёт за голосом" : "Идёт текст")
                    .font(ConsoleStyle.font(11, .semibold))
                    .foregroundStyle(model.prompter.mode == .paused ? ConsoleStyle.yellow : ConsoleStyle.green)
                // Что сейчас и что дальше: панель у камеры видна не всегда.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<3, id: \.self) { row in
                        let index = model.prompterLine + row
                        Text(model.prompterLines.indices.contains(index) ? model.prompterLines[index].text : " ")
                            .font(ConsoleStyle.font(15, .medium))
                            .foregroundStyle(.white)
                            .opacity(PrompterLayout.lineOpacity(row: row))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                ThinSlider(
                    value: model.prompter.total > 0 ? model.prompter.elapsed / model.prompter.total : 0, range: 0...1, label: "Перемотка"
                ) { model.seekPrompter(toFraction: $0) }
                HStack {
                    Text(PrompterModule.clock(model.prompter.elapsed))
                    Spacer()
                    Text(PrompterModule.clock(model.prompter.total))
                }
                .font(noteFont)
                .foregroundStyle(ConsoleStyle.caption)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                PrompterSmallButton(title: "−") { model.changePrompterSpeed(faster: false) }
                Text(model.prompter.multiplierText)
                    .font(ConsoleStyle.font(13).monospacedDigit())
                    .foregroundStyle(ConsoleStyle.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                PrompterSmallButton(title: "+") { model.changePrompterSpeed(faster: true) }
            }
            HStack(spacing: 6) {
                Text("За голосом").font(ConsoleStyle.font(13)).foregroundStyle(ConsoleStyle.caption).lineLimit(1)
                Spacer(minLength: 0)
                Toggle("За голосом", isOn: Binding(
                    get: { model.prompter.followsVoice }, set: { model.onPrompterVoiceToggle?($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(ConsoleStyle.green)
            }
            if let problem = model.prompterVoiceProblem {
                Text(problem).font(ConsoleStyle.font(11)).foregroundStyle(ConsoleStyle.orange).lineLimit(2)
            }
            Spacer(minLength: 0)
            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.prompter.isActive {
            HStack(spacing: 8) {
                PrompterSmallButton(title: model.prompter.mode == .paused ? "Дальше" : "Пауза", strong: true, wide: true) { model.togglePrompterPause() }
                PrompterSmallButton(title: "Стоп", wide: true) { model.stopPrompter() }
            }
        } else if model.prompterRecentOpen {
            PrompterSmallButton(title: "Назад", wide: true) { model.prompterRecentOpen = false }
        } else {
            VStack(spacing: 8) {
                // Кнопки стоят на своих местах всегда: недоступная гаснет, а не исчезает.
                HStack(spacing: 8) {
                    PrompterSmallButton(title: "Вставить", wide: true) { model.pastePrompterText() }
                    PrompterSmallButton(title: "Недавние", wide: true) { model.prompterRecentOpen = true }
                        .disabled(model.prompterLibrary.texts.isEmpty)
                        .opacity(model.prompterLibrary.texts.isEmpty ? 0.4 : 1)
                }
                PrompterSmallButton(title: "Старт", strong: true, wide: true) { model.startPrompter() }
                    .disabled(!hasText)
                    .opacity(hasText ? 1 : 0.4)
            }
        }
    }
}

/// Вкладка «Перевод»: появляется по ⌃⌥T и уходит вместе с Пультом.
struct TranslateTab: View {
    let model: ConsoleModel

    var body: some View {
        ConsoleCard {
            switch model.translate.state {
            case .idle:
                EmptyView()
            case .askToCopy:
                ConsoleEmpty(icon: "translation", title: "Выделение не прочиталось", hint: TranslateModule.askToCopyHint)
            case .working:
                ConsoleEmpty(icon: "translation", title: "Перевожу…")
            case .failed(let problem):
                VStack(spacing: 10) {
                    ConsoleEmpty(icon: "translation", title: "Перевод не вышел", hint: problem)
                    if problem == ConsoleTranslator.needsLanguages {
                        PrompterSmallButton(title: "Открыть настройки языка") { ConsoleTranslator.openLanguages() }
                    }
                }
            case .done(let source, let result):
                done(source: source, result: result)
            }
        }
    }

    private func done(source: String, result: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(TranslateDirection.detect(source).title)
                    .font(ConsoleStyle.font(11, .semibold))
                    .foregroundStyle(ConsoleStyle.caption)
                ScrollView {
                    Text(source)
                        .font(ConsoleStyle.font(13))
                        .foregroundStyle(ConsoleStyle.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    Text(result)
                        .font(ConsoleStyle.font(15, .medium))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    PrompterSmallButton(title: model.translateCopied ? "Скопировано" : "Скопировать", strong: !model.translateCopied) {
                        model.copyTranslation(result)
                    }
                    if model.translate.replaceable {
                        PrompterSmallButton(title: "Заменить") { model.onTranslateReplace?(result) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
