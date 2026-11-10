import AgentPulseCore
import AppKit
import SwiftUI

/// Переводчик: две равные карточки, языки сверху, действия снизу.
struct TranslateTab: View {
    let model: ConsoleModel
    private var direction: TranslateDirection { model.translate.direction(of: model.translateInput) }

    var body: some View {
        HStack(spacing: ConsoleStyle.splitGap) {
            ConsoleCard {
                VStack(alignment: .leading, spacing: 8) {
                    languageRow(source: true)
                    ZStack(alignment: .topLeading) {
                        PrompterEditor(text: Binding(get: { model.translateInput }, set: { model.typeTranslation($0) }), selectionActions: { source, range in
                            guard let fragment = TextFragment(source: source, range: range) else { return [] }
                            return [("Перевести выделенный фрагмент", { model.translateFragment(fragment) })]
                        })
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
                        .overlay { TranslationResultMenu(model: model).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    if case .done(_, let result) = model.translate.state {
                        action(model.translateCopied ? "Скопировано" : "Скопировать", color: ConsoleStyle.green) { model.copyTranslation(result) }
                    }
                }
            }
        }
        .task(id: model.translationLanguagesPending) {
            if let version = model.translationLanguagesPending { await model.waitForTranslationLanguages(version: version) }
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
                Text(model.comparingTranslation ? model.translateInput : result).font(ConsoleStyle.font(14, .medium)).lineSpacing(1)
                    .foregroundStyle(ConsoleStyle.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.consoleScrollFade()
                .help("Удерживай Option, чтобы увидеть оригинал")

        }
    }
}
