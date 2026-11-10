import AppKit
import SwiftUI

/// Поле текста. Файлы принимает вкладка: NSTextView вставил бы вместо них путь.
struct PrompterEditor: NSViewRepresentable {
    final class TextView: NSTextView {
        var selectionActions: ((String, NSRange) -> [(String, () -> Void)])?
        private var menuActions: [() -> Void] = []
        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = super.menu(for: event) ?? NSMenu()
            let additions = selectionActions?(string, selectedRange()) ?? []
            menuActions = additions.map { $0.1 }
            if !additions.isEmpty { menu.addItem(.separator()) }
            for (index, entry) in additions.enumerated() {
                let item = NSMenuItem(title: entry.0, action: #selector(runSelectionAction(_:)), keyEquivalent: "")
                item.target = self; item.tag = index
                menu.addItem(item)
            }
            return menu
        }
        @objc private func runSelectionAction(_ item: NSMenuItem) {
            guard menuActions.indices.contains(item.tag) else { return }
            menuActions[item.tag]()
        }
        override func updateDragTypeRegistration() { unregisterDraggedTypes() }
    }

    @Binding var text: String
    var selectionActions: ((String, NSRange) -> [(String, () -> Void)])? = nil

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let view = TextView()
        view.delegate = context.coordinator
        view.selectionActions = selectionActions
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textColor = .white
        view.insertionPointColor = .white
        view.font = ConsoleStyle.nsFont(14, .medium)
        // Отступ задаёт карточка: редактор не добавляет свои внутренние поля.
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 18
        paragraph.maximumLineHeight = 18
        view.defaultParagraphStyle = paragraph
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
        (scroll.documentView as? TextView)?.selectionActions = selectionActions
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
            HStack(spacing: 4) {
                if let icon = ["−": "minus", "+": "plus", "Старт": "play", "Продолжить": "play", "Пауза": "pause", "Стоп": "stop"][title] {
                    ConsoleAsset(name: icon, width: 16, height: 16,
                                 tint: (title == "Старт" || title == "Продолжить") ? Color(hex: 0xF35B5B) : (strong ? .black : ConsoleStyle.text))
                }
                if title.count != 1 { Text(title).font(ConsoleStyle.font(12, .medium)).lineLimit(1) }
            }
            .foregroundStyle(strong || tint != nil ? .black : ConsoleStyle.text)
            .frame(width: title.count == 1 ? 40 : nil, height: 40)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(tint ?? (strong ? Color.white : ConsoleStyle.button), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(ConsolePressStyle())
        .promoTarget("prompter-\(title)")
    }
}
