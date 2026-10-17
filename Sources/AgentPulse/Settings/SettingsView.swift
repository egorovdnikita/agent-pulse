import AgentPulseCore
import AppKit
import SwiftUI

/// Вкладки окна «Настройки». Выбор живёт в наблюдаемом классе: `@State` без Xcode недоступен.
@Observable
final class SettingsNavigation {
    enum Tab: String, CaseIterable {
        case general, character, news, sources, lab

        var title: String {
            switch self {
            case .general: "Основное"
            case .character: "Характер"
            case .news: "Новости"
            case .sources: "Источники"
            case .lab: "Лаборатория"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .character: "face.smiling"
            case .news: "newspaper"
            case .sources: "point.3.connected.trianglepath.dotted"
            case .lab: "flask"
            }
        }
    }

    var tab: Tab = .general
}

/// Одно окно вместо «Характера» и Mascot Lab: всё, что не нужно каждый день, живёт здесь, а не в меню.
struct SettingsView: View {
    let app: AppDelegate
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettings(app: app)
                .tabItem { Label(SettingsNavigation.Tab.general.title, systemImage: SettingsNavigation.Tab.general.symbol) }
                .tag(SettingsNavigation.Tab.general)
            CharacterSettings(app: app)
                .tabItem { Label(SettingsNavigation.Tab.character.title, systemImage: SettingsNavigation.Tab.character.symbol) }
                .tag(SettingsNavigation.Tab.character)
            NewsSettings(app: app)
                .tabItem { Label(SettingsNavigation.Tab.news.title, systemImage: SettingsNavigation.Tab.news.symbol) }
                .tag(SettingsNavigation.Tab.news)
            SourcesSettings(app: app)
                .tabItem { Label(SettingsNavigation.Tab.sources.title, systemImage: SettingsNavigation.Tab.sources.symbol) }
                .tag(SettingsNavigation.Tab.sources)
            MascotLabView(model: app.model)
                .tabItem { Label(SettingsNavigation.Tab.lab.title, systemImage: SettingsNavigation.Tab.lab.symbol) }
                .tag(SettingsNavigation.Tab.lab)
        }
        .frame(width: 560, height: 640)
    }
}

// MARK: - Основное

private struct GeneralSettings: View {
    let app: AppDelegate

    var body: some View {
        let model = app.model
        Form {
            Section {
                HStack(spacing: 16) {
                    MascotView(animator: model.animator, diameter: 48)
                        .frame(width: 96, height: 96)
                        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent Pulse").font(.title3.weight(.semibold))
                        Text(model.statusLine).foregroundStyle(.secondary)
                        if let reaction = model.lastReaction {
                            Text("Последняя реакция: \(model.lastLine ?? reaction)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Маскот") {
                Toggle("Показывать маскота", isOn: Binding(get: { model.overlayVisible }, set: { app.setOverlayVisible($0) }))
                Picker("Угол экрана", selection: Binding(get: { model.config.display.anchor }, set: { app.setAnchor($0) })) {
                    Text("Справа снизу").tag(PulseConfig.Display.Anchor.bottomRight)
                    Text("Слева снизу").tag(PulseConfig.Display.Anchor.bottomLeft)
                    Text("Справа сверху").tag(PulseConfig.Display.Anchor.topRight)
                    Text("Слева сверху").tag(PulseConfig.Display.Anchor.topLeft)
                }
                Picker("Дисплей", selection: Binding(get: { model.config.display.screen }, set: { app.setScreen($0) })) {
                    Text("С Dock").tag("dock")
                    Text("Основной").tag("main")
                    Text("С курсором").tag("active")
                    Text("Встроенный").tag("builtin")
                }
                Toggle("Гравитация", isOn: Binding(get: { model.config.display.gravity }, set: { app.setGravity($0) }))
                Text("С гравитацией отпущенный маскот падает на «пол» с отскоками.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Вернуть маскота в угол") { app.panel?.resetPosition() }
            }
            Section("Система") {
                Toggle("Запускать при входе", isOn: Binding(get: { model.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
                if let error = model.serverError {
                    Text("Сокет недоступен: \(error)").foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Характер

private struct CharacterSettings: View {
    let app: AppDelegate
    @Bindable private var form = BirthdayForm()

    var body: some View {
        @Bindable var model = app.model
        Form {
            Section("Характер") {
                LabeledContent("Болтливость") {
                    Slider(value: $model.config.character.talkativeness, in: 0...1) { editing in
                        if !editing { model.applyCharacter() }
                    }
                }
                LabeledContent("Озорство") {
                    Slider(value: $model.config.character.mischief, in: 0...1) { editing in
                        if !editing { model.applyCharacter() }
                    }
                }
                Text("Болтливость — как часто облачко вне работы агентов. Озорство — до \(Int((model.config.character.mischief * 8).rounded())) приколов в день.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Тишина") {
                LabeledContent("Тихие часы") {
                    HStack(spacing: 6) {
                        TextField("", text: Binding(
                            get: { model.config.character.quietFrom ?? "" },
                            set: { model.config.character.quietFrom = $0.isEmpty ? nil : $0; model.applyCharacter() }
                        ), prompt: Text("23:30"))
                        .frame(width: 60)
                        Text("—")
                        TextField("", text: Binding(
                            get: { model.config.character.quietTo ?? "" },
                            set: { model.config.character.quietTo = $0.isEmpty ? nil : $0; model.applyCharacter() }
                        ), prompt: Text("08:00"))
                        .frame(width: 60)
                    }
                }
                Toggle("Прятаться при долгом простое", isOn: Binding(
                    get: { model.config.character.hideWhenIdle },
                    set: { model.config.character.hideWhenIdle = $0; model.applyCharacter() }
                ))
                if model.config.character.hideWhenIdle {
                    Stepper("Через \(model.config.character.hideAfterMinutes) мин", value: Binding(
                        get: { model.config.character.hideAfterMinutes },
                        set: { model.config.character.hideAfterMinutes = $0; model.applyCharacter() }
                    ), in: 5...240, step: 5)
                }
                Text("Созвон, полный экран и тихие часы — облачко молчит, приколов нет. «Жду тебя» слышно всегда.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("День рождения") {
                Toggle("Знаю день рождения", isOn: $form.known)
                if form.known {
                    DatePicker("Дата", selection: $form.date, displayedComponents: .date)
                }
            }
            .onChange(of: form.known) { saveBirthday() }
            .onChange(of: form.date) { saveBirthday() }
            Section("Мило и бесит") {
                LabeledContent("Сегодня") {
                    Text("мило \(model.feedbackToday["мило", default: 0]) · бесит \(model.feedbackToday["бесит", default: 0])")
                }
                LabeledContent("Молчат после двух «бесит» за неделю") {
                    Text("\(model.mutedReactions.count)")
                }
            }
            Section("Память") {
                Text("Только счётчики дня — задачи, ошибки, перерывы, поглаживания. Хранится 30 дней на этом Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Забыть всё", role: .destructive) { model.resetMemory() }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadBirthday)
    }

    private func loadBirthday() {
        let model = app.model
        if let parts = model.config.character.birthday?.split(separator: "-"), parts.count == 2,
           let month = Int(parts[0]), let day = Int(parts[1]),
           let date = Calendar.current.date(from: DateComponents(year: 2000, month: month, day: day)) {
            form.date = date
            form.known = true
        }
    }

    private func saveBirthday() {
        let model = app.model
        if form.known {
            let parts = Calendar.current.dateComponents([.month, .day], from: form.date)
            model.config.character.birthday = String(format: "%02d-%02d", parts.month ?? 1, parts.day ?? 1)
        } else {
            model.config.character.birthday = nil
        }
        model.applyCharacter()
    }
}

@Observable
final class BirthdayForm {
    var known = false
    var date = Date()
}

// MARK: - Новости

private struct NewsSettings: View {
    let app: AppDelegate

    var body: some View {
        let model = app.model
        let on = model.config.character.designNews
        Form {
            Section {
                Toggle("Рассказывать новости", isOn: Binding(get: { on }, set: { app.setDesignNews($0) }))
                Text("До 6 в день, не чаще раза в 75 минут, с 9 до 22 и только когда ты рядом. Дизайн — большая часть.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Темы") {
                ForEach(NewsTopic.allCases, id: \.self) { topic in
                    let sources = NewsFeeds.all.filter { $0.topic == topic }
                    Toggle(isOn: Binding(
                        get: { model.config.character.enabledNewsTopics.contains(topic) },
                        set: { app.setNewsTopic(topic, on: $0) }
                    )) {
                        HStack(spacing: 8) {
                            // Белая плашка — как в облачке: тёмные цвета тем видны и в тёмной теме.
                            CategoryIcon(category: .news(topic))
                                .frame(width: 26, height: 26)
                                .background(.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title)
                                Text(Set(sources.map(\.name).map { $0.components(separatedBy: " · ").first ?? $0 }).sorted().joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .disabled(!on)
            Section {
                Text("Только публичные ленты и открытые Telegram-каналы, без данных о тебе. Показанное помнится на этом Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Источники

private struct SourcesSettings: View {
    let app: AppDelegate

    var body: some View {
        @Bindable var model = app.model
        Form {
            Section("Claude Code") {
                LabeledContent("Хуки", value: model.hooksInstalled ? "установлены" + Self.ago(model, .claudeCode) : "не установлены")
                if model.hooksInstalled {
                    Button("Удалить хуки") { app.uninstallHooks() }
                } else {
                    Button("Установить хуки…") { app.installHooks() }
                }
            }
            Section("Claude Cowork") {
                Toggle(isOn: Binding(get: { model.config.sources.cowork }, set: { app.setCoworkEnabled($0) })) {
                    Text("Следить за Cowork")
                    Text(coworkStatus(model)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Claude в браузере") {
                LabeledContent("Мост для расширения", value: model.browserBridgeInstalled ? "установлен" + Self.ago(model, .claudeChat) : "не установлен")
                if model.browserBridgeInstalled {
                    HStack {
                        Button("Показать расширение") { app.revealExtension() }
                        Button("Отключить") { app.uninstallBrowserBridge() }
                    }
                } else {
                    Button("Подключить…") { app.installBrowserBridge() }
                }
            }
            Section("Claude Chat в приложении") {
                Toggle(isOn: Binding(get: { model.config.sources.claudeChat }, set: { app.setChatWindowEnabled($0) })) {
                    Text("Следить за чатом")
                    Text(model.config.sources.claudeChat && !model.accessibilityTrusted
                         ? "Нужен «Универсальный доступ» в Системных настройках"
                         : "Через «Универсальный доступ»: видно только, что Claude отвечает")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.config.sources.claudeChat && model.accessibilityTrusted {
                    Button("Снимок окна Claude для настройки") { app.saveChatWindowSnapshot() }
                }
            }
            Section("Figma") {
                Button("Показать плагин-компаньон") { app.revealFigmaPlugin() }
                if let error = model.companionError {
                    Text("Порт занят — \(error)").foregroundStyle(.red)
                }
            }
            Section("Органы чувств") {
                Toggle("Агенты", isOn: senseBinding(\.agents))
                Toggle("Тело ноутбука", isOn: senseBinding(\.body))
                Toggle("Ритм и время", isOn: senseBinding(\.rhythm))
                Toggle("Звук", isOn: senseBinding(\.audio))
                Toggle("Эксперименты (угол крышки)", isOn: senseBinding(\.experimental))
            }
        }
        .formStyle(.grouped)
    }

    private func senseBinding(_ keyPath: WritableKeyPath<PulseConfig.Senses, Bool>) -> Binding<Bool> {
        Binding(
            get: { app.model.config.senses[keyPath: keyPath] },
            set: {
                app.model.config.senses[keyPath: keyPath] = $0
                app.model.applyCharacter()
                app.startSenses()
            }
        )
    }

    private func coworkStatus(_ model: PulseModel) -> String {
        switch model.coworkWatching {
        case true?: "Слежу" + Self.ago(model, .cowork)
        case false?: "Cowork не найден"
        case nil: "Выключено"
        }
    }

    /// « · 3 мин назад» — когда источник последний раз подавал голос.
    static func ago(_ model: PulseModel, _ source: AgentEvent.Source) -> String {
        guard let date = model.lastEventBySource[source] else { return "" }
        return " · " + HumanTime.ago(Date().timeIntervalSince(date))
    }
}
