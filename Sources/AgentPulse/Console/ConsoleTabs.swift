import AgentPulseCore
import AppKit
import SwiftUI

private let tabFont = ConsoleStyle.font(13, .medium)

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
        view.font = ConsoleStyle.nsFont(14, .medium)
        // Текст стоит по тому же полю, что и в остальных карточках: 14 с учётом внутреннего поля строки.
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
                if let icon = ["−": "minus", "+": "plus", "Старт": "play", "Пауза": "pause", "Стоп": "stop"][title] {
                    ConsoleAsset(name: icon, width: 16, height: 16,
                                 tint: title == "Старт" ? Color(hex: 0xF35B5B) : (strong ? .black : ConsoleStyle.text))
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

/// Вкладка «Суфлёр»: слева текст, справа управление. Тексты хранятся только на этом Mac.
struct PrompterTab: View {
    @Bindable var model: ConsoleModel

    var body: some View {
        HStack(spacing: ConsoleStyle.cardGap) {
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
                    .promoTarget("prompter-editor")
                if model.prompterDraft.isEmpty {
                    Text("Вставь текст или перетащи .txt и .md")
                        .font(ConsoleStyle.font(14, .medium))
                        .foregroundStyle(ConsoleStyle.caption)
                        .allowsHitTesting(false)
                }
            }
            .consoleScrollFade()
            if hasText {
                HStack(alignment: .bottom) {
                    ConsoleActionButton(title: "Очистить", color: ConsoleStyle.red) { model.prompterDraft = "" }
                        .promoTarget("prompter-clear")
                    Spacer(minLength: 8)
                    if let estimate = model.prompterEstimate {
                        Text(estimate).font(ConsoleStyle.noteFont).foregroundStyle(ConsoleStyle.caption).frame(height: 16)
                    }
                }
                .frame(height: 26)
                .padding(.top, 4)
            }
        }
        .padding(ConsoleStyle.cardPadding)
        .background(ConsoleStyle.card, in: RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius, style: .continuous)
                .strokeBorder(ConsoleStyle.red, lineWidth: 1)
                .opacity(model.prompterInputInvalid ? 1 : 0)
                .animation(.easeOut(duration: 0.45), value: model.prompterInputInvalid)
                .allowsHitTesting(false)
        }
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
                            } label: { ConsoleStyle.symbol("close-circle", 16).opacity(ConsoleStyle.iconOpacity) }
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
                    .font(ConsoleStyle.font(12, .semibold))
                    .foregroundStyle(model.prompter.mode == .paused ? ConsoleStyle.yellow : ConsoleStyle.green)
                // Что сейчас и что дальше: панель у камеры видна не всегда.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<3, id: \.self) { row in
                        let index = model.prompterLine + row
                        Text(model.prompterLines.indices.contains(index) ? model.prompterLines[index].text : " ")
                            .font(ConsoleStyle.font(14, .medium))
                            .foregroundStyle(.white)
                            .opacity(PrompterLayout.lineOpacity(row: row))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                ThinSlider(
                    value: model.prompter.total > 0 ? model.prompter.elapsed / model.prompter.total : 0, range: 0...1, label: "Перемотка",
                    commitsOnEnd: true
                ) { model.seekPrompter(toFraction: $0) }
                HStack {
                    Text(PrompterModule.clock(model.prompter.elapsed))
                    Spacer()
                    Text(PrompterModule.clock(model.prompter.total))
                }
                .frame(height: 16)
                .font(ConsoleStyle.noteFont)
                .foregroundStyle(ConsoleStyle.caption)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                PrompterSmallButton(title: "−") { model.changePrompterSpeed(faster: false) }
                Text(model.prompter.multiplierText)
                    .font(ConsoleStyle.font(12, .medium).monospacedDigit())
                    .foregroundStyle(ConsoleStyle.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                PrompterSmallButton(title: "+") { model.changePrompterSpeed(faster: true) }
            }
            HStack(spacing: 6) {
                Text("За голосом").font(ConsoleStyle.font(12, .medium)).foregroundStyle(ConsoleStyle.caption).lineLimit(1)
                Spacer(minLength: 0)
                Button { model.onPrompterVoiceToggle?(!model.prompter.followsVoice) } label: {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(model.prompter.followsVoice ? Color(hex: 0x1CB454) : ConsoleStyle.button)
                        .frame(width: 36, height: 18)
                        .overlay(alignment: model.prompter.followsVoice ? .trailing : .leading) {
                            RoundedRectangle(cornerRadius: 7).fill(.white).frame(width: 20, height: 14).padding(2)
                        }
                }.buttonStyle(ConsolePressStyle()).accessibilityLabel("За голосом")
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
            HStack(spacing: 4) {
                PrompterSmallButton(title: model.prompter.mode == .paused ? "Дальше" : "Пауза", strong: true, wide: true) { model.togglePrompterPause() }
                PrompterSmallButton(title: "Стоп", wide: true) { model.stopPrompter() }
            }
        } else if model.prompterRecentOpen {
            PrompterSmallButton(title: "Назад", wide: true) { model.prompterRecentOpen = false }
        } else {
            VStack(spacing: 8) {
                // Кнопки стоят на своих местах всегда: недоступная гаснет, а не исчезает.
                HStack(spacing: 4) {
                    PrompterSmallButton(title: "Вставить", wide: true) { model.pastePrompterText() }
                    PrompterSmallButton(title: "Недавние", wide: true) { model.prompterRecentOpen = true }
                        .disabled(model.prompterLibrary.texts.isEmpty)
                        .opacity(model.prompterLibrary.texts.isEmpty ? 0.4 : 1)
                }
                PrompterSmallButton(title: "Старт", strong: true, wide: true) { model.startPrompterDraft() }
            }
        }
    }
}

/// Переводчик: две равные карточки, действия в заголовках.
struct TranslateTab: View {
    let model: ConsoleModel
    private var direction: TranslateDirection { model.translate.direction(of: model.translateInput) }

    var body: some View {
        HStack(spacing: ConsoleStyle.splitGap) {
            ConsoleCard {
                VStack(alignment: .leading, spacing: 8) {
                    languageRow(source: true)
                    ZStack(alignment: .topLeading) {
                        PrompterEditor(text: Binding(get: { model.translateInput }, set: { model.typeTranslation($0) }))
                            .promoTarget("translate-editor")
                        if model.translateInput.isEmpty {
                            Text("Введи или выдели его и нажми ⌃⌥T")
                                .font(ConsoleStyle.font(14, .medium)).foregroundStyle(ConsoleStyle.caption).allowsHitTesting(false)
                        }
                    }.consoleScrollFade()
                    if !model.translateInput.isEmpty {
                        action("Очистить", color: ConsoleStyle.red) { model.clearTranslation() }
                    }
                }
            }
            ConsoleCard {
                VStack(alignment: .leading, spacing: 8) {
                    languageRow(source: false)
                    output
                    if case .done(_, let result) = model.translate.state {
                        action(model.translateCopied ? "Скопировано" : "Скопировать", color: ConsoleStyle.green) { model.copyTranslation(result) }
                    }
                }
            }
        }
        .overlay {
            Button { model.flipTranslation() } label: {
                ConsoleAsset(name: "swap-languages", width: 20, height: 20, tint: ConsoleStyle.text)
                    .frame(width: 24, height: 40)
                    .background(ConsoleStyle.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    // Обводка макета идёт снаружи: внутренняя половина перекрыта заливкой кнопки.
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ConsoleStyle.surface, lineWidth: 6)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(ConsolePressStyle())
            .accessibilityLabel("Поменять языки")
            .help("Поменять языки")
            .promoTarget("translate-swap")
        }
    }

    private func action(_ title: String, color: Color, perform: @escaping () -> Void) -> some View {
        HStack {
            ConsoleActionButton(title: title, color: color, action: perform)
                .promoTarget("translate-" + title)
            Spacer(minLength: 0)
        }.frame(height: 26)
    }

    private func languageRow(source: Bool) -> some View {
        let selected = source ? model.translate.sourceLanguage : model.translate.targetLanguage
        let recent = source ? model.translate.recentSources : model.translate.recentTargets
        let codes: [String] = source && selected == nil ? ["auto"] + Array(recent.prefix(2)) : recent
        return HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(codes, id: \.self) { code in
                        languageButton(code, source: source, selected: selected == code || (selected == nil && code == "auto"))
                    }
                }
            }
            .background(ConsoleHorizontalScrollRegion())
            .overlay(alignment: .trailing) {
                LinearGradient(colors: [.clear, ConsoleStyle.card], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 40).allowsHitTesting(false)
            }
            Menu {
                if source {
                    Button { model.selectTranslationLanguage(nil, source: true) } label: {
                        if selected == nil { Label("Определить язык", systemImage: "checkmark") }
                        else { Text("Определить язык") }
                    }
                    Divider()
                }
                ForEach(model.translationLanguages, id: \.self) { code in
                    Button { model.selectTranslationLanguage(code, source: source) } label: {
                        if selected == code { Label(TranslateDirection.languageTitle(code), systemImage: "checkmark") }
                        else { Text(TranslateDirection.languageTitle(code)) }
                    }
                }
            } label: {
                ConsoleAsset(name: "language-chevron", width: 16, height: 16, tint: ConsoleStyle.text)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(width: 26, height: 26)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: 0x737373).opacity(41.0 / 255), lineWidth: 1).allowsHitTesting(false))
            .accessibilityLabel(source ? "Исходный язык" : "Язык перевода")
            .promoTarget(source ? "translate-source-menu" : "translate-target-menu")
        }.frame(height: 26)
        .task {
            let languages = await ConsoleTranslator.supportedLanguages()
            if !languages.isEmpty { model.translationLanguages = languages }
        }
    }

    private func languageButton(_ code: String, source: Bool, selected: Bool) -> some View {
        Button { model.selectTranslationLanguage(code == "auto" ? nil : code, source: source) } label: {
            Text(code == "auto" ? "Определить язык" : TranslateDirection.languageTitle(code))
                .font(ConsoleStyle.font(12, .semibold)).foregroundStyle(ConsoleStyle.text)
                // В Figma обводка входит в hug-размер: 8 pt поля + 1 pt рамки.
                .fixedSize().padding(.horizontal, selected ? 8 : 9).frame(height: 26)
                .background(selected ? Color(hex: 0x737373).opacity(61.0 / 255) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? .clear : Color(hex: 0x737373).opacity(41.0 / 255), lineWidth: 1))
        }.buttonStyle(ConsolePressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .promoTarget("translate-" + (source ? "source-" : "target-") + code)
    }

    @ViewBuilder private var output: some View {
        switch model.translate.state {
        case .idle:
            Text("Перевод")
                .font(ConsoleStyle.font(14, .medium))
                .foregroundStyle(ConsoleStyle.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .askToCopy: ConsoleEmpty(icon: "chat-round-dots", title: "Выделение не прочиталось", hint: TranslateModule.askToCopyHint)
        case .working: ConsoleEmpty(icon: "chat-round-dots", title: "Перевожу…")
        case .failed(let problem):
            VStack(spacing: 4) {
                ConsoleEmpty(icon: "chat-round-dots", title: "Перевод не вышел", hint: problem)
                if problem == ConsoleTranslator.needsLanguages {
                    PrompterSmallButton(title: "Скачать языки") { model.onOpenSettings?("Переводчик") }
                }
            }
        case .done(_, let result):
            ScrollView {
                Text(result).font(ConsoleStyle.font(14, .medium)).lineSpacing(1)
                    .foregroundStyle(ConsoleStyle.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.consoleScrollFade()
            .contextMenu {
                if model.translate.replaceable {
                    Button("Заменить выделенное") { model.onTranslateReplace?(result) }
                }
            }
        }
    }
}
