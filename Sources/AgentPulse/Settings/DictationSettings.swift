import AgentPulseCore
import AppKit
import ApplicationServices
import SwiftUI

/// Настройки диктовки и переводчика. Каждое разрешение спрашивается только при включении.
struct DictationSettings: View {
    let model: PulseModel
    let app: AppDelegate
    let controller: DictationController?

    private var settings: PulseConfig.Console { model.config.console }

    var body: some View {
        Section("Диктовка") {
            Toggle(isOn: Binding(get: { settings.dictation }, set: { app.setDictationEnabled($0) })) {
                Text("Диктовка")
                Text("Зажми ⌃⌥D, говори, отпусти. Спросит микрофон. Всё на этом Mac, аудио не сохраняется")
                    .font(SettingsStyle.caption).foregroundStyle(.secondary)
            }
            .disabled(!settings.enabled)
            if settings.dictation {
                if ConsoleTranslator.isAvailable {
                    Picker("Язык", selection: Binding(get: { settings.dictationLanguage }, set: { app.setDictationLanguage($0) })) {
                        Text("Русский").tag("ru")
                        Text("Английский").tag("en")
                    }
                }
                if let models = controller?.models { modelRow(models) }
                accessibilityRow
                DictationRulesEditor(model: model, app: app)
                Toggle(isOn: Binding(get: { settings.dictationHistory }, set: { app.setDictationHistory($0) })) {
                    Text("Хранить историю")
                    Text("Только текст, 30 дней. Аудио не сохраняется никогда")
                        .font(SettingsStyle.caption).foregroundStyle(.secondary)
                }
                if let controller, !controller.history.entries.isEmpty {
                    ForEach(controller.history.entries.prefix(5)) { entry in
                        Text(entry.text).font(SettingsStyle.caption).textSelection(.enabled).lineLimit(3)
                    }
                    Button("Очистить историю") { controller.clearHistory() }
                }
            }
        }
        if ConsoleTranslator.isAvailable {
            Section("Переводчик") {
                Toggle(isOn: Binding(get: { settings.translator }, set: { app.setTranslatorEnabled($0) })) {
                    Text("Переводчик")
                    Text("Выдели текст и нажми ⌃⌥T. Русский ↔ английский, на этом Mac")
                        .font(SettingsStyle.caption).foregroundStyle(.secondary)
                }
                .disabled(!settings.enabled)
                if settings.translator, !settings.dictation { accessibilityRow }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ models: DictationModelStore) -> some View {
        switch models.state {
        case .absent:
            LabeledContent("Модель GigaAM") {
                Button("Скачать, \(DictationModelSpec.downloadMB) MB") { models.download() }
            }
            Text("На диске займёт \(DictationModelSpec.diskMB) MB, при работе до 650 MB памяти, через 2 минуты память освобождается")
                .font(SettingsStyle.caption).foregroundStyle(.secondary)
        case .downloading(let fraction):
            LabeledContent("Модель GigaAM") {
                HStack {
                    ProgressView(value: fraction).frame(width: 120)
                    Button("Отмена") { models.cancel() }
                }
            }
        case .unpacking:
            LabeledContent("Модель GigaAM", value: "Проверяю и распаковываю…")
        case .ready:
            LabeledContent("Модель GigaAM") {
                HStack {
                    Text("Скачана").foregroundStyle(.secondary)
                    Button("Удалить") { models.remove() }
                }
            }
        case .failed(let problem):
            LabeledContent("Модель GigaAM") {
                Button("Скачать ещё раз") { models.download() }
            }
            Text(problem).font(SettingsStyle.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var accessibilityRow: some View {
        Toggle(isOn: Binding(get: { settings.accessibility }, set: { app.setConsoleAccessibility($0) })) {
            Text("Вставлять в поле и читать выделение")
            Text("Нужен Универсальный доступ. Без него диктовка кладёт текст в буфер обмена, прежнее содержимое буфера не сохраняется")
                .font(SettingsStyle.caption).foregroundStyle(.secondary)
        }
        if settings.accessibility, !AXIsProcessTrusted() {
            Text("Разреши: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → Agent Pulse")
                .font(SettingsStyle.caption).foregroundStyle(.secondary)
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
            Text("Правила замены")
            Text("Уже есть: диплой → deploy, пул реквест → pull request, коммит → commit, гитхаб → GitHub")
                .font(SettingsStyle.caption).foregroundStyle(.secondary)
            ForEach(rules.indices, id: \.self) { index in
                HStack {
                    TextField("Произнесённое", text: field(index, \.spoken))
                    Text("→").foregroundStyle(.secondary)
                    TextField("Записанное", text: field(index, \.written))
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
