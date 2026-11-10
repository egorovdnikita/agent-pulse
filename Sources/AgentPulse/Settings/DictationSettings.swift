import AgentPulseCore
import AppKit
import ApplicationServices
import SwiftUI

/// Настройки диктовки: каждое разрешение спрашивается только при включении.
struct DictationOptions: View {
    let model: PulseModel
    let app: AppDelegate
    let controller: DictationController?

    private var settings: PulseConfig.Console { model.config.console }

    var body: some View {
        ModuleOption { ShortcutRow(title: "Держи и говори", keys: "⌃⌥D", busy: model.console.busyKeys.contains("dictation")) }
        ModuleOption {
            VStack(alignment: .leading, spacing: 4) {
                ShortcutRow(title: "Исправить последнюю вставку", keys: "⌃⌥R", busy: model.console.busyKeys.contains("correction"))
                Text("Зажми и скажи: «замени последнее слово на…». Нужен Универсальный доступ. Только последняя вставка, две минуты.")
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
        }
        if ConsoleTranslator.isAvailable {
            ModuleOption {
                SettingsPicker("Язык", selection: Binding(get: { settings.dictationLanguage }, set: { app.setDictationLanguage($0) })) {
                    Text("Русский").tag("ru")
                    Text("Английский").tag("en")
                }
            }
        }
        if let models = controller?.models { ModuleOption { VStack(alignment: .leading, spacing: 4) { modelRow(models) } } }
        AccessibilityOption(model: model, app: app)
        ModuleOption { DictationRulesEditor(model: model, app: app) }
        ModuleOption {
            Toggle("Голосовая разметка", isOn: Binding(get: { settings.dictationFormatting }, set: { app.setDictationFormatting($0) }))
            Text("Команды «новый абзац», «новая строка», «новый пункт» меняют разметку. В обычном режиме остаются текстом.")
                .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
        }
        ModuleOption {
            Toggle(isOn: Binding(get: { settings.dictationHistory }, set: { app.setDictationHistory($0) })) {
                Text("Хранить историю")
                Text("Только текст, 30 дней").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
        }
        if let controller, !controller.history.entries.isEmpty {
            ModuleOption {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(controller.history.entries.prefix(5)) { entry in
                        Text(entry.text).font(SettingsStyle.caption).textSelection(.enabled).lineLimit(3)
                    }
                    Button("Очистить историю") { controller.clearHistory() }
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ models: DictationModelStore) -> some View {
        switch models.state {
        case .absent:
            LabeledContent("Модель распознавания") {
                Button("Скачать, \(DictationModelSpec.downloadMB) MB") { models.download() }
            }
            Text("На диске займёт \(DictationModelSpec.diskMB) MB, при работе до 650 MB памяти, через 2 минуты память освобождается")
                .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
        case .downloading(let fraction):
            LabeledContent("Модель распознавания") {
                HStack {
                    ProgressView(value: fraction).frame(width: 120)
                    Button("Отмена") { models.cancel() }
                }
            }
        case .unpacking:
            LabeledContent("Модель распознавания", value: "Проверяю и распаковываю…")
        case .ready:
            LabeledContent("Модель распознавания") {
                HStack {
                    Text("Скачана").foregroundStyle(SettingsStyle.muted)
                    Button("Удалить") { models.remove() }
                }
            }
        case .failed(let problem):
            LabeledContent("Модель распознавания") {
                Button("Скачать ещё раз") { models.download() }
            }
            Text(problem).font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
        }
    }
}

/// Настройки перевода.
struct TranslatorOptions: View {
    let model: PulseModel
    let app: AppDelegate

    var body: some View {
        ModuleOption { ShortcutRow(title: "Перевести выделенное", keys: "⌃⌥T", busy: model.console.busyKeys.contains("t")) }
        ModuleOption { TranslatorLanguagesRow(direction: model.console.translate.direction(of: model.console.translateInput)) }
        ModuleOption {
            DisclosureGroup("Не переводить: \(model.console.translationTerms.terms.count)") {
                if model.console.translationTerms.terms.isEmpty {
                    Text("Выдели термин в исходном тексте Переводчика и выбери «Не переводить этот термин».")
                        .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                }
                ForEach(model.console.translationTerms.terms, id: \.self) { term in
                    HStack {
                        Text(term).textSelection(.enabled)
                        Spacer()
                        Button("Удалить") { model.console.removeTranslationTerm(term) }
                    }
                }
            }
        }
        AccessibilityOption(model: model, app: app)
    }
}

/// Вставка в поле и чтение выделения: нужен Универсальный доступ.
struct AccessibilityOption: View {
    let model: PulseModel
    let app: AppDelegate

    var body: some View {
        let on = model.config.console.accessibility
        ModuleOption {
            Toggle(isOn: Binding(get: { on }, set: { app.setConsoleAccessibility($0) })) {
                Text("Вставлять в поле и читать выделение")
                Text(on && !AXIsProcessTrusted() ? "Разреши в Системных настройках: Конфиденциальность → Универсальный доступ" : "Нужен Универсальный доступ")
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
        }
    }
}

/// «Произнесённое → записанное». Встроенный набор работает всегда, здесь только свои правила.
private struct DictationRulesEditor: View {
    let model: PulseModel
    let app: AppDelegate

    private var rules: [DictationRule] { model.config.console.dictationRules }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Словарь и правила замены")
            Text("Уже есть: диплой → deploy, пул реквест → pull request, коммит → commit, гитхаб → GitHub")
                .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            Text("Варианты произношения разделяй |. Точное написание сохраняет регистр, например iPhone.")
                .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            ForEach(rules.indices, id: \.self) { index in
                HStack {
                    TextField("Произнесённое", text: field(index, \.spoken))
                    Text("→").foregroundStyle(SettingsStyle.muted)
                    TextField("Записанное", text: field(index, \.written))
                    Toggle("Точно", isOn: Binding(
                        get: { index < rules.count && rules[index].exactSpelling == true },
                        set: { value in
                            guard index < rules.count else { return }
                            var list = rules
                            list[index].exactSpelling = value ? true : nil
                            app.setDictationRules(list)
                        }
                    )).help("Сохранять регистр написанного слова")
                    Button("Удалить") {
                        var list = rules
                        list.remove(at: index)
                        app.setDictationRules(list)
                    }
                }
            }
            Button("Добавить правило") { app.setDictationRules(rules + [DictationRule(spoken: "", written: "")]) }
        }
    }

    private func field(_ index: Int, _ path: WritableKeyPath<DictationRule, String>) -> Binding<String> {
        Binding(
            get: { index < rules.count ? rules[index][keyPath: path] : "" },
            set: { value in
                guard index < rules.count else { return }
                var list = rules
                list[index][keyPath: path] = value
                app.setDictationRules(list)
            }
        )
    }
}
