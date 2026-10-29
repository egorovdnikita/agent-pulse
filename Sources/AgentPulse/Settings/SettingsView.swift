import AgentPulseCore
import AppKit
import SwiftUI

/// Вкладки окна «Настройки».
enum SettingsNavigation {
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
    }
}

/// Одно окно вместо «Характера» и Mascot Lab: всё, что не нужно каждый день, живёт здесь, а не в меню.
enum SettingsWindow {
    static let size = CGSize(width: 580, height: 660)

    @ViewBuilder
    static func content(_ tab: SettingsNavigation.Tab, app: AppDelegate) -> some View {
        Group {
            switch tab {
            case .general: GeneralSettings(app: app)
            case .character: CharacterSettings(app: app)
            case .news: NewsSettings(app: app)
            case .sources: SourcesSettings(app: app)
            case .lab: MascotLabView(model: app.model)
            }
        }
        .frame(width: size.width, height: size.height)
    }

}

/// Выбранный раздел. В наблюдаемом классе: `@State` без Xcode недоступен.
@Observable
final class SettingsSelection {
    var tab: SettingsNavigation.Tab = .general
}

/// Окно «Настройки»: сверху сегментированный переключатель разделов, ниже — раздел.
struct SettingsRoot: View {
    let app: AppDelegate
    @Bindable var selection: SettingsSelection

    var body: some View {
        VStack(spacing: 0) {
            Picker("Раздел", selection: $selection.tab) {
                ForEach(SettingsNavigation.Tab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 12)
            Divider()
            SettingsWindow.content(selection.tab, app: app)
        }
        .frame(width: SettingsWindow.size.width)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Основное

private struct GeneralSettings: View {
    let app: AppDelegate

    var body: some View {
        let model = app.model
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    MascotView(animator: model.animator, diameter: 48)
                        .frame(width: 104, height: 104)
                        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.now(model)).font(.headline)
                        if let today = Self.today(model) {
                            Text(today).font(.callout).foregroundStyle(.secondary)
                        }
                        MoodBars(mood: model.mood).padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Где живёт") {
                LabeledContent("Угол экрана") {
                    CornerPicker(anchor: Binding(get: { model.config.display.anchor }, set: { app.setAnchor($0) }))
                }
                Picker("Дисплей", selection: Binding(get: { model.config.display.screen }, set: { app.setScreen($0) })) {
                    Text("С Dock").tag("dock")
                    Text("Основной").tag("main")
                    Text("С курсором").tag("active")
                    Text("Встроенный").tag("builtin")
                }
                LabeledContent("Размер") {
                    HStack {
                        Slider(value: Binding(get: { model.config.display.mascotSize }, set: { app.setMascotSize($0) }),
                               in: 40...72, step: 4)
                        Text("\(Int(model.config.display.mascotSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Button("Вернуть маскота в угол") { app.panel?.resetPosition() }
            }
            Section("Поведение") {
                Toggle("Показывать маскота", isOn: Binding(get: { model.overlayVisible }, set: { app.setOverlayVisible($0) }))
                Toggle(isOn: Binding(get: { model.config.display.gravity }, set: { app.setGravity($0) })) {
                    Text("Гравитация")
                    Text("Отпущенный маскот падает на «пол» с отскоками").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Запускать при входе", isOn: Binding(get: { model.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
                if let error = model.serverError {
                    Text("Сокет недоступен: \(error)").foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Что делаю сейчас — тем же языком, что в облачке при наведении.
    @MainActor static func now(_ model: PulseModel) -> String {
        if let top = model.dominant, model.state != .sleep, model.state != .idle {
            let story = HoverStory.working(
                source: top.source, phase: top.phase, since: model.promptAt[top.id] ?? top.phaseSince,
                steps: top.timeline.count, now: Date()
            )
            return "\(story.title): \(story.text.prefix(1).lowercased() + story.text.dropFirst())"
        }
        return model.state == .sleep ? "Дремлю, пока все отдыхают" : "Я тут, всё спокойно"
    }

    @MainActor static func today(_ model: PulseModel) -> String? {
        guard let day = model.today else { return nil }
        return HoverStory.summary(today: day, week: day, weekday: 3, hour: 12)?.text
    }
}

/// Настроение маскота — четыре шкалы, как его видит Director.
private struct MoodBars: View {
    let mood: Mood

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
            row("Бодрость", mood.energy, .orange)
            row("Спокойствие", 1 - mood.stress, .teal)
            row("Радость", mood.joy, .pink)
            row("Общение", mood.social, .blue)
        }
        .font(.caption)
    }

    private func row(_ title: String, _ value: Double, _ color: Color) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            // Своя шкала: системная в неактивном окне теряет цвет.
            Capsule().fill(Color.secondary.opacity(0.2))
                .frame(width: 140, height: 6)
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: 140 * min(max(value, 0.03), 1), height: 6)
                }
        }
    }
}

/// Угол экрана — схемой экрана: клик по углу.
private struct CornerPicker: View {
    @Binding var anchor: PulseConfig.Display.Anchor

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.secondary.opacity(0.35)))
            // Dock внизу — ориентир.
            Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 40, height: 4)
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 4)
            ForEach(PulseConfig.Display.Anchor.allCases, id: \.self) { corner in
                Button { anchor = corner } label: {
                    Circle()
                        .fill(corner == anchor ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 12, height: 12)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: Alignment(horizontal: corner.isRight ? .trailing : .leading, vertical: corner.isTop ? .top : .bottom))
                .help(Self.title(corner))
            }
        }
        .frame(width: 112, height: 70)
    }

    static func title(_ corner: PulseConfig.Display.Anchor) -> String {
        switch corner {
        case .topRight: "Справа сверху"
        case .topLeft: "Слева сверху"
        case .bottomRight: "Справа снизу"
        case .bottomLeft: "Слева снизу"
        }
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
                Text("Каждые 15 минут, с 9 до 22, когда ты рядом и не занят созвоном или агентом. Дизайн — большая часть.")
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
            Section("Orca") {
                Toggle(isOn: Binding(get: { model.config.sources.orca }, set: { app.setOrcaEnabled($0) })) {
                    Text("Следить за агентами в Orca")
                    Text(orcaStatus(model)).font(.caption).foregroundStyle(.secondary)
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

    private func orcaStatus(_ model: PulseModel) -> String {
        switch model.orcaWatching {
        case true?: "Codex, OpenCode и другие" + Self.ago(model, .orca)
        case false?: "Orca не найдена"
        case nil: "Выключено"
        }
    }

    /// « · 3 мин назад» — когда источник последний раз подавал голос.
    static func ago(_ model: PulseModel, _ source: AgentEvent.Source) -> String {
        guard let date = model.lastEventBySource[source] else { return "" }
        return " · " + HumanTime.ago(Date().timeIntervalSince(date))
    }
}
