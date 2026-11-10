import AgentPulseCore
import AppKit
import SwiftUI

// MARK: - Полка

/// Файл копируется наружу, ссылка остаётся на полке для повторного использования.
/// Вид лежит поверх плитки и сам ловит нажатие: снизу до него мышь не доходит.
private final class ShelfDragView: NSView, NSDraggingSource {
    var url: URL?
    /// Что уносит перетаскивание: выбранное или один файл.
    var payload: (() -> [URL])?
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    private var pressedAt: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressedAt = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressedAt else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
        pressedAt = nil
        let carried = payload?() ?? []
        let side = 48.0
        let items = carried.enumerated().map { index, file in
            let item = NSDraggingItem(pasteboardWriter: file as NSURL)
            // Стопка: несколько файлов видно сразу, но за курсором она не разъезжается.
            let shift = Double(min(index, 4)) * 4
            item.setDraggingFrame(
                NSRect(x: point.x - side / 2 + shift, y: point.y - side / 2 - shift, width: side, height: side),
                contents: NSWorkspace.shared.icon(forFile: file.path)
            )
            return item
        }
        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self).draggingFormation = .pile
    }

    override func mouseUp(with event: NSEvent) {
        if pressedAt != nil { onClick?(event.modifierFlags) }
        pressedAt = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}

private struct ShelfDragArea: NSViewRepresentable {
    let url: URL
    let payload: () -> [URL]
    let onClick: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> ShelfDragView { ShelfDragView() }

    func updateNSView(_ view: ShelfDragView, context: Context) {
        view.url = url
        view.payload = payload
        view.onClick = onClick
    }
}

/// Где стоят плитки: рамка выделения проверяет по ним, что задела.
private struct ShelfFrames: PreferenceKey {
    static let defaultValue: [URL: CGRect] = [:]

    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue()) { $1 }
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
        case .archive, .image, .other: Color(hex: 0x262626)
        }
    }
}

/// Плитка файла: превью картинки или лист с меткой формата, имя в одну строку.
private struct ShelfTile: View {
    let model: ConsoleModel
    let item: ShelfItem
    static let size = (624.0 - 6 * ShelfTab.fileGap) / 7
    @Environment(\.promoCapture) private var capture

    // Обычный @State без Xcode недоступен: его макрос лежит только там.
    private let hovering = State(initialValue: false)

    init(model: ConsoleModel, item: ShelfItem) {
        self.model = model
        self.item = item
    }

    var body: some View {
        VStack(spacing: 4) {
            preview
                .overlay {
                    if model.shelfSelection.contains(item.url) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ConsoleStyle.selection, lineWidth: 2)
                    }
                }
                .overlay {
                    ShelfDragArea(
                        url: item.url,
                        payload: { model.shelfSelection.dragged(from: item.url, order: model.shelfOrder) },
                        onClick: { model.clickShelf(item.url, flags: $0) }
                    )
                }
                .overlay(alignment: .topTrailing) {
                    if hovering.wrappedValue || capture?.hoverShelfFiles == true {
                        Button { model.removeFromShelf(item.url) } label: {
                            ConsoleStyle.symbol("close-circle", 18)
                        }
                        .buttonStyle(ConsolePressStyle())
                        .padding(4)
                        .accessibilityLabel("Убрать")
                        .promoTarget("remove-file-\(item.name)")
                    }
                }
            Text(item.name)
                .font(ConsoleStyle.font(12, .medium))
                .foregroundStyle(ConsoleStyle.text)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Self.size, height: 28, alignment: .top)
        }
        .frame(width: Self.size)
        .promoTarget("file-\(item.name)")
        .background {
            GeometryReader { Color.clear.preference(key: ShelfFrames.self, value: [item.url: $0.frame(in: .named(ShelfTab.space))]) }
        }
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
                                .font(ConsoleStyle.font(10, .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 2)
                                .frame(height: 12)
                                .background(kind.color, in: RoundedRectangle(cornerRadius: 2))
                                .fixedSize()
                                .offset(x: -5, y: 7)
                        }
                    }
            }
        }
        .frame(width: Self.size, height: 76)
    }
}

struct ShelfTab: View {
    let model: ConsoleModel
    fileprivate static let space = "shelf"
    fileprivate static let fileGap = 4.0

    var body: some View {
        Group {
            if model.shelf.items.isEmpty {
                VStack(spacing: 24) {
                    LibraryCharacter(skin: model.librarySkin, paused: !model.expanded)
                        .promoTarget("library-character")
                    VStack(spacing: 8) {
                        Text("Перетащите сюда файлы, чтобы держать их под рукой")
                            .font(ConsoleStyle.font(14, .medium)).foregroundStyle(ConsoleStyle.text)
                        Text("До 20 файлов. Хранятся до удаления из Библиотеки")
                            .font(ConsoleStyle.font(12, .medium)).foregroundStyle(ConsoleStyle.caption)
                    }
                }
                .padding(ConsoleStyle.cardPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                .contentShape(Rectangle()).onTapGesture { model.chooseFiles() }
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

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        ConsoleActionButton(title: title, color: title == "Добавить" ? ConsoleStyle.green : ConsoleStyle.red, action: action)
            .promoTarget("shelf-\(title)")
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.fileGap), count: 7), alignment: .leading, spacing: 8) {
                    ForEach(model.shelf.items.reversed()) { ShelfTile(model: model, item: $0) }
                }
                // Пустое место тоже страница: клик снимает выделение, тянешь — рамка.
                .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { model.clearShelfSelection() }
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                        .onChanged { drag in
                            model.dragRubber(CGRect(
                                x: min(drag.startLocation.x, drag.location.x), y: min(drag.startLocation.y, drag.location.y),
                                width: abs(drag.location.x - drag.startLocation.x), height: abs(drag.location.y - drag.startLocation.y)
                            ))
                        }
                        .onEnded { _ in model.dragRubber(nil) }
                )
                .overlay(alignment: .topLeading) {
                    if let rubber = model.shelfRubber {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.white.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                            .frame(width: rubber.width, height: rubber.height)
                            .offset(x: rubber.minX, y: rubber.minY)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: Self.space)
                .onPreferenceChange(ShelfFrames.self) { frames in
                    MainActor.assumeIsolated { model.shelfFrames = frames }
                }
            }
            .consoleScrollFade()
            .onChange(of: model.shelfSelection.focused) { _, focused in
                if let focused { proxy.scrollTo(focused) }
            }
            }
            footer.frame(height: 26).padding(8)
        }
    }

    private var footer: some View {
        let selected = model.shelfSelection.count
        return HStack(alignment: .bottom, spacing: 4) {
            Text(selected > 0 ? "Выбрано \(selected). Потяни, чтобы забрать" : "Потяни файл, чтобы забрать")
                .font(ConsoleStyle.noteFont)
                .foregroundStyle(ConsoleStyle.caption)
                .lineLimit(1)
                .frame(height: 16)
            Spacer(minLength: 4)
            if selected > 0 {
                footerButton("Убрать") { model.removeSelectedFiles() }
            } else {
                footerButton("Добавить") { model.chooseFiles() }
                footerButton("Очистить") { model.clearShelf() }
            }
        }
    }
}
