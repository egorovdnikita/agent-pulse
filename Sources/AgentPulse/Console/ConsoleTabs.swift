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
                .fill(event.color.map { Color(hex: $0) } ?? ConsoleStyle.track)
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
        EventWords.detail(event, now: model.now)
    }
}

private enum EventWords {
    /// «Через 8 мин · Zoom», «Идёт, ещё 12 мин», «21:20 – 21:50».
    static func detail(_ event: MeetingEvent, now: Date) -> String {
        if event.isAllDay { return "Весь день" }
        let running = event.start <= now && event.end > now
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        let clock = CalendarText.formatter("HH:mm")
        let time: String
        if running {
            time = "Идёт, ещё \(max(1, Int(event.end.timeIntervalSince(now) / 60))) мин"
        } else if minutes >= 0, minutes < 60 {
            time = "Через \(max(1, minutes)) мин"
        } else {
            time = "\(clock.string(from: event.start)) – \(clock.string(from: event.end))"
        }
        return [time, event.link?.service.title].compactMap(\.self).joined(separator: " · ")
    }
}

/// Карточка ближайшей встречи: главное в календаре видно сразу, а не строкой в списке.
private struct FeaturedEvent: View {
    let model: ConsoleModel
    let event: MeetingEvent

    var body: some View {
        let running = event.start <= model.now
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(event.color.map { Color(hex: $0) } ?? ConsoleStyle.green).frame(width: 6, height: 6)
                Text(EventWords.detail(event, now: model.now))
                    .font(noteFont)
                    .foregroundStyle(running ? ConsoleStyle.green : ConsoleStyle.caption)
                    .lineLimit(1)
            }
            Text(event.title).font(ConsoleStyle.font(15, .semibold)).foregroundStyle(.white).lineLimit(2)
            Spacer(minLength: 0)
            if let link = event.link {
                PrompterSmallButton(title: "Войти", tint: ConsoleStyle.orange) { model.onJoin?(link.url) }
            }
        }
    }
}

private struct MonthGrid: View {
    let model: ConsoleModel

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: model.now)
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let start = calendar.date(byAdding: .month, value: model.calendarMonth, to: first) ?? first
        let days = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        // Понедельник — первая колонка.
        let lead = (calendar.component(.weekday, from: start) + 5) % 7
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(["пн", "вт", "ср", "чт", "пт", "сб", "вс"], id: \.self) {
                Text($0).font(ConsoleStyle.font(11)).foregroundStyle(ConsoleStyle.caption)
            }
            ForEach(0..<(lead + days), id: \.self) { index in
                if index < lead {
                    Color.clear.frame(height: 19)
                } else if let day = calendar.date(byAdding: .day, value: index - lead, to: start) {
                    cell(day, number: index - lead + 1, isToday: calendar.isDate(day, inSameDayAs: today))
                }
            }
        }
    }

    private func isWeekend(_ day: Date) -> Bool {
        Calendar.current.isDateInWeekend(day)
    }

    private func cell(_ day: Date, number: Int, isToday: Bool) -> some View {
        Button {
            model.calendarDay = day
            model.calendarScope = .day
        } label: {
            ZStack {
                if isToday { Circle().fill(ConsoleStyle.red).frame(width: 18, height: 18) }
                if !isToday, model.calendarScope == .day, Calendar.current.isDate(day, inSameDayAs: model.calendarDay) {
                    Circle().strokeBorder(.white, lineWidth: 1).frame(width: 18, height: 18)
                }
                Text("\(number)").font(noteFont).foregroundStyle(isToday ? .white : isWeekend(day) ? ConsoleStyle.red : .white)
                if !model.calendar.events(on: day).isEmpty {
                    Circle().fill(isToday ? Color.white : ConsoleStyle.orange).frame(width: 3, height: 3).offset(y: 7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 19)
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
            ConsoleCard(padding: 12, radius: ConsoleStyle.calendarRadius) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Text(CalendarText.formatter("LLLL yyyy").string(from: shownMonth).capitalized)
                            .font(ConsoleStyle.font(13, .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        monthButton("alt-arrow-left", "Предыдущий месяц", -1)
                        monthButton("alt-arrow-right", "Следующий месяц", 1)
                    }
                    .frame(height: 18)
                    MonthGrid(model: model)
                }
            }
            .frame(width: 236)
            VStack(spacing: 6) {
                ConsoleSegments(values: [CalendarScope.day, .week], selected: model.calendarScope, title: \.title) { scope in
                    model.calendarDay = model.now
                    model.calendarScope = scope
                }
                ConsoleCard(radius: ConsoleStyle.calendarRadius) {
                    if model.calendarScope == .week { weekPage } else { dayPage }
                }
            }
        }
    }

    private var shownMonth: Date {
        Calendar.current.date(byAdding: .month, value: model.calendarMonth, to: model.now) ?? model.now
    }

    private func monthButton(_ icon: String, _ label: String, _ step: Int) -> some View {
        let target = model.calendarMonth + step
        let allowed = (0...2).contains(target)
        return Button {
            if allowed { model.calendarMonth = target }
        } label: {
            solar(icon, 12).opacity(allowed ? 1 : 0.3).frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(ConsolePressStyle())
        .accessibilityLabel(label)
    }

    private var dayPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(CalendarText.day(model.calendarDay, now: model.now))
                    .font(ConsoleStyle.font(13, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !Calendar.current.isDate(model.calendarDay, inSameDayAs: model.now) {
                    Button("Сегодня") {
                        model.calendarDay = model.now
                        model.calendarMonth = 0
                    }
                    .buttonStyle(ConsolePressStyle())
                    .font(ConsoleStyle.font(11, .medium))
                    .foregroundStyle(ConsoleStyle.caption)
                    .padding(.leading, 6)
                }
                Spacer(minLength: 4)
                dayButton("alt-arrow-left", "Предыдущий день", -1)
                dayButton("alt-arrow-right", "Следующий день", 1)
            }
            let events = model.calendar.events(on: model.calendarDay)
            let isToday = Calendar.current.isDate(model.calendarDay, inSameDayAs: model.now)
            let next = isToday ? events.first { !$0.isAllDay && $0.end > model.now } : nil
            let rest = events.filter { $0.id != next?.id }
            if events.isEmpty {
                ConsoleEmpty(icon: "calendar", title: "Встреч нет")
            } else {
                HStack(alignment: .top, spacing: 12) {
                    if let next { FeaturedEvent(model: model, event: next).frame(maxWidth: .infinity, alignment: .leading) }
                    if !rest.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(rest) { EventRow(model: model, event: $0) }
                            }
                        }
                        .frame(maxWidth: .infinity)
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
        case .document: ConsoleStyle.blue
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
                        .accessibilityLabel("Убрать")
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
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ConsoleStyle.tile)
            if kind == .image, let image = model.shelfPreviews[item.url] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))
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
                    ConsoleEmpty(icon: "folder-with-files", title: "Файлов нет", hint: "Брось файл на Пульт или на маскота")
                }
            } else {
                files
            }
        }
        .overlay {
            if model.dropTargeted {
                RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius, style: .continuous)
                    .strokeBorder(ConsoleStyle.dropAccent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
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
            }
            HStack {
                Text("Потяни файл, чтобы забрать").font(noteFont).foregroundStyle(ConsoleStyle.caption).lineLimit(1)
                Spacer(minLength: 4)
                Button("Очистить") { model.clearShelf() }
                    .buttonStyle(ConsolePressStyle()).font(ConsoleStyle.font(11, .medium)).foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Музыка

/// Эквалайзер: семь полосок. Движение считает Core Animation, кадров на CPU нет.
private struct EqualizerBars: NSViewRepresentable {
    let moving: Bool

    func makeNSView(context: Context) -> EqualizerView { EqualizerView() }
    func updateNSView(_ view: EqualizerView, context: Context) { view.moving = moving }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerView, context: Context) -> CGSize? { EqualizerView.size }
}

final class EqualizerView: NSView {
    static let size = CGSize(width: 32, height: 14)
    private static let rest = 4.0
    private var bars: [CALayer] = []

    var moving = false {
        didSet { if oldValue != moving { update() } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        bars = (0..<7).map { index in
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.cgColor
            bar.cornerRadius = 1
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.frame = CGRect(x: Double(index) * 5, y: (Self.size.height - Self.rest) / 2, width: 2, height: Self.rest)
            layer?.addSublayer(bar)
            return bar
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func update() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (index, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            guard moving, !reduce else { continue }
            let height = CABasicAnimation(keyPath: "bounds.size.height")
            height.fromValue = Self.rest
            height.toValue = 6 + Double((index * 5) % 9)
            height.duration = 0.3 + Double((index * 3) % 5) * 0.07
            height.autoreverses = true
            height.repeatCount = .infinity
            height.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(height, forKey: "beat")
        }
    }
}

struct MediaTab: View {
    let model: ConsoleModel

    private func clock(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    var body: some View {
        if let playing = model.media.playing ?? model.rememberedTrack, model.media.availability != .unavailable {
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
                    solar("music-note", 40).opacity(ConsoleStyle.iconOpacity).frame(maxWidth: .infinity, maxHeight: .infinity).background(ConsoleStyle.card)
                }
            }
            .frame(width: 178, height: 178).clipShape(RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text(playing.title).font(ConsoleStyle.font(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 0)
                    EqualizerBars(moving: playing.isPlaying).frame(width: EqualizerView.size.width, height: EqualizerView.size.height)
                        .opacity(playing.isPlaying ? 1 : 0.4)
                        .accessibilityHidden(true)
                }
                .padding(.top, 8)
                if let artist = playing.artist {
                    Text(artist).font(ConsoleStyle.font(13)).foregroundStyle(ConsoleStyle.caption).lineLimit(1).padding(.top, 2)
                }
                Spacer(minLength: 6)
                if let duration = playing.duration {
                    ThinSlider(value: playing.position(now: model.now), range: 0...duration, label: "Позиция", commitsOnEnd: true) { model.onSeek?($0) }
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
                        Button { model.toggleMute() } label: {
                            solar("volume-loud", 14).opacity((model.volume ?? 0) > 0 ? 0.55 : 0.2)
                                .frame(width: 22, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(ConsolePressStyle())
                        .accessibilityLabel((model.volume ?? 0) > 0 ? "Выключить звук" : "Включить звук")
                        ThinSlider(value: model.volume ?? 0, range: 0...1, label: "Громкость") { model.onVolume?($0) }
                            .frame(width: 96)
                    }
                }
                .padding(.bottom, 8)
            }
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
struct PrompterEditor: NSViewRepresentable {
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
        // Счётчик и «Очистить» под текстом, а не поверх него: длинный текст иначе на них наезжает.
        VStack(spacing: 0) {
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
            if hasText {
                HStack {
                    Button("Очистить") { model.prompterDraft = "" }
                        .buttonStyle(ConsolePressStyle())
                        .font(ConsoleStyle.font(11, .medium))
                        .foregroundStyle(ConsoleStyle.caption)
                    Spacer(minLength: 8)
                    if let estimate = model.prompterEstimate {
                        Text(estimate).font(noteFont).foregroundStyle(ConsoleStyle.caption)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .padding(.top, 4)
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
                            } label: { solar("close-circle", 16).opacity(ConsoleStyle.iconOpacity) }
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
                    value: model.prompter.total > 0 ? model.prompter.elapsed / model.prompter.total : 0, range: 0...1, label: "Перемотка",
                    commitsOnEnd: true
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

/// Страница «Перевод»: слева текст, справа перевод. Ввести, вставить или принести выделение по ⌃⌥T.
struct TranslateTab: View {
    let model: ConsoleModel

    private var direction: TranslateDirection {
        model.translate.direction(of: model.translateInput)
    }

    var body: some View {
        HStack(spacing: 8) {
            source
            ConsoleCard { output }
        }
    }

    /// Левая карточка: направление, текст и «Очистить». Отдельная строка съедала бы высоту страницы.
    private var source: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { model.flipTranslation() } label: {
                    Text(direction.title)
                        .font(ConsoleStyle.font(11, .semibold))
                        .foregroundStyle(ConsoleStyle.caption)
                        .frame(height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ConsolePressStyle())
                .help("Перевести в другую сторону")
                Spacer(minLength: 0)
                if !model.translateInput.isEmpty {
                    Button("Очистить") { model.clearTranslation() }
                        .buttonStyle(ConsolePressStyle())
                        .font(ConsoleStyle.font(11, .medium))
                        .foregroundStyle(ConsoleStyle.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            ZStack(alignment: .topLeading) {
                PrompterEditor(text: Binding(get: { model.translateInput }, set: { model.typeTranslation($0) }))
                if model.translateInput.isEmpty {
                    Text("Введи текст или выдели его и нажми ⌃⌥T")
                        .font(ConsoleStyle.font(13))
                        .foregroundStyle(ConsoleStyle.caption)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(ConsoleStyle.card, in: RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var output: some View {
        switch model.translate.state {
        case .idle:
            ConsoleEmpty(icon: "chat-round-dots", title: "Здесь будет перевод")
        case .askToCopy:
            ConsoleEmpty(icon: "chat-round-dots", title: "Выделение не прочиталось", hint: TranslateModule.askToCopyHint)
        case .working:
            ConsoleEmpty(icon: "chat-round-dots", title: "Перевожу…")
        case .failed(let problem):
            VStack(spacing: 10) {
                ConsoleEmpty(icon: "chat-round-dots", title: "Перевод не вышел", hint: problem)
                if problem == ConsoleTranslator.needsLanguages {
                    PrompterSmallButton(title: "Скачать языки") { model.onOpenSettings?("Переводчик") }
                }
            }
        case .done(_, let result):
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
        }
    }
}
