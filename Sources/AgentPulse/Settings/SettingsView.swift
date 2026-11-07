import AgentPulseCore
import AppKit
import SwiftUI

/// Вкладки окна «Настройки».
enum SettingsNavigation {
    enum Tab: String, CaseIterable {
        case general, character, console, news, sources, lab

        var title: String {
            switch self {
            case .general: "Основное"
            case .character: "Характер"
            case .console: "Пульт"
            case .news: "Новости"
            case .sources: "Источники"
            case .lab: "Лаборатория"
            }
        }

        var subtitle: String {
            switch self {
            case .general: "Что маскот делает сейчас, его место и облик"
            case .character: "Как часто он говорит, шутит и когда молчит"
            case .console: "Модули, клавиши и лимиты агентов"
            case .news: "О чём рассказывать и откуда брать"
            case .sources: "Откуда маскот узнаёт об агентах и о Mac"
            case .lab: "Состояния и реакции вручную, числа пластики"
            }
        }

        /// Иконка Solar.
        var icon: String {
            switch self {
            case .general: "tuning-2"
            case .character: "emoji-funny-circle"
            case .console: "devices"
            case .news: "document-text"
            case .sources: "wi-fi-router-round"
            case .lab: "atom"
            }
        }
    }
}

/// Одно окно вместо «Характера» и Mascot Lab: всё, что не нужно каждый день, живёт здесь, а не в меню.
@MainActor
enum SettingsWindow {
    /// Всё окно: боковая колонка и раздел шириной 660, как раньше.
    static let size = CGSize(width: SettingsStyle.sidebarWidth + 660, height: 720)

    @ViewBuilder
    static func content(_ tab: SettingsNavigation.Tab, app: AppDelegate) -> some View {
        Group {
            switch tab {
            case .general: GeneralSettings(app: app)
            case .character: CharacterSettings(app: app)
            case .console: ConsoleSettings(app: app)
            case .news: NewsSettings(app: app)
            case .sources: SourcesSettings(app: app)
            case .lab: MascotLabView(model: app.model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

/// Выбранный раздел. В наблюдаемом классе: `@State` без Xcode недоступен.
@Observable
final class SettingsSelection {
    var tab: SettingsNavigation.Tab = .general
}

/// Окно «Настройки»: слева разделы, справа заголовок и раздел.
struct SettingsRoot: View {
    let app: AppDelegate
    @Bindable var selection: SettingsSelection
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.tab.title)
                        .font(SettingsStyle.title)
                        .tracking(-0.22)
                        .foregroundStyle(SettingsStyle.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(selection.tab.subtitle)
                        .font(SettingsStyle.body)
                        .foregroundStyle(SettingsStyle.muted)
                }
                .padding(.horizontal, 32)
                .padding(.top, 44)
                .padding(.bottom, 4)
                SettingsWindow.content(selection.tab, app: app).id(selection.tab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
        .background(SettingsStyle.window)
        .font(SettingsStyle.body)
        .tint(SettingsStyle.accent)
        .toggleStyle(SettingsSwitchStyle())
        .buttonStyle(SettingsButtonStyle())
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(SettingsNavigation.Tab.allCases.enumerated()), id: \.element) { index, tab in
                SettingsSidebarItem(
                    tab: tab, number: index + 1, isSelected: selection.tab == tab, highlight: highlight
                ) { selection.tab = tab }
            }
            Spacer()
        }
        .padding(.top, 52)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(width: SettingsStyle.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(SettingsStyle.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(SettingsStyle.ring).frame(width: 1) }
        .animation(SettingsStyle.spring(reduced: reduceMotion), value: selection.tab)
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
            Section("Облик") {
                let bots = PalSkin.installed()
                let mode = PalWardrobe.Mode(config: model.config.mascot.skin)
                Picker("Кто на маскоте", selection: Binding(get: { model.config.mascot.skin }, set: { app.setSkin($0) })) {
                    Text("Светящийся круг").tag(PalSkin.classic)
                    if !bots.isEmpty { Text("Меняется сам").tag(PalWardrobe.Mode.shuffleConfig) }
                    ForEach(bots, id: \.bot) { Text($0.bot).tag($0.configValue) }
                }
                if bots.isEmpty {
                    Text("Боты Agent Pals не установлены: scripts/install-agent-pals.sh путь/к/паку.zip")
                        .font(SettingsStyle.caption).foregroundStyle(.secondary)
                } else if mode != .classic {
                    if mode == .shuffle {
                        Text("Новая задача любого агента или пробуждение — новый бот, не чаще раза в 3 мин. Все \(bots.count) по очереди, без повторов")
                            .font(SettingsStyle.caption).foregroundStyle(.secondary)
                    }
                    if let skin = model.animator.skin, bots.contains(skin) {
                        DisclosureGroup("Сценарии: анимации и облачка") { PalGallery(skin: skin, diameter: model.config.display.mascotSize) }
                    }
                }
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
                    Text("Отпущенный маскот падает на «пол» с отскоками").font(SettingsStyle.caption).foregroundStyle(.secondary)
                }
                Toggle("Запускать при входе", isOn: Binding(get: { model.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
                if let error = model.serverError {
                    Text("Сокет недоступен: \(error)").foregroundStyle(.red)
                }
            }
            Section("О программе") {
                Text("Иконки категорий — Solar Icons, 480 Design, лицензия CC BY 4.0. Анимации ботов играет Lottie от Airbnb, лицензия Apache 2.0. «Музыка» работает через mediaremote-adapter, Jonas van den Berg, лицензия BSD-3. Диктовка: GigaAM (лицензия MIT), sherpa-onnx (Apache 2.0), ONNX Runtime (MIT).")
                    .font(SettingsStyle.caption).foregroundStyle(.secondary)
                Button("Лицензии") {
                    if let url = Bundle.main.url(forResource: "Licenses", withExtension: nil) { NSWorkspace.shared.open(url) }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Что делаю сейчас — тем же языком, что в облачке при наведении.
    @MainActor static func now(_ model: PulseModel) -> String {
        if let top = model.dominant, model.state != .sleep, model.state != .idle {
            let story = HoverStory.working(
                source: top.source, host: top.hostBundleId, phase: top.phase, since: model.promptAt[top.id] ?? top.phaseSince,
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
        .font(SettingsStyle.caption)
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
            Section {
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
                    .font(SettingsStyle.caption).foregroundStyle(.secondary)
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
                Text("Созвон, полный экран и тихие часы — облачко молчит, приколов нет. «Жду тебя» слышно всегда, а в тихие часы — и ответ на твоё действие: кабель, тычок, поглаживание.")
                    .font(SettingsStyle.caption).foregroundStyle(.secondary)
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
                    .font(SettingsStyle.caption).foregroundStyle(.secondary)
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
                    .font(SettingsStyle.caption).foregroundStyle(.secondary)
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
                                    .font(SettingsStyle.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .disabled(!on)
            Section {
                Text("Только публичные ленты и открытые Telegram-каналы, без данных о тебе. Показанное помнится на этом Mac.")
                    .font(SettingsStyle.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Пульт

private struct ConsoleSettings: View {
    let app: AppDelegate

    var body: some View {
        let model = app.model
        let settings = model.config.console
        Form {
            Section {
                Toggle(isOn: Binding(get: { settings.enabled }, set: { app.setConsoleEnabled($0) })) {
                    Text("Показывать Пульт")
                    Text("Виджет в углу напротив маскота. Выключен — маскот работает как раньше")
                        .font(SettingsStyle.caption).foregroundStyle(.secondary)
                }
                Picker("Клавиша раскрытия", selection: Binding(get: { settings.hotkey }, set: { app.setConsoleHotKey($0) })) {
                    ForEach(ConsoleHotKey.letters, id: \.self) { Text("⌃⌥\($0.uppercased())").tag($0) }
                    Text("Нет").tag("")
                }
                .disabled(!settings.enabled)
            }
            Section("Модули") {
                Toggle("Лимиты", isOn: Binding(get: { settings.limits }, set: { app.setLimitsEnabled($0) }))
                    .disabled(!settings.enabled)
                Toggle(isOn: Binding(get: { settings.prompter }, set: { app.setPrompterEnabled($0) })) {
                    Text("Суфлёр")
                    Text("Текст под камерой. ⌃⌥P — старт и стоп, ⌃⌥↑ и ⌃⌥↓ — скорость, клик — пауза")
                        .font(SettingsStyle.caption).foregroundStyle(.secondary)
                }
                .disabled(!settings.enabled)
                if settings.prompter {
                    Toggle(isOn: Binding(get: { settings.prompterHidden }, set: { app.setPrompterHidden($0) })) {
                        Text("Скрывать суфлёр при показе экрана")
                        Text("В Zoom на macOS 15 и новее суфлёр может быть виден. Meet, Teams, Телемост и QuickTime не проверены")
                            .font(SettingsStyle.caption).foregroundStyle(.secondary)
                    }
                    .disabled(!settings.enabled)
                    Toggle(isOn: Binding(get: { settings.prompterVoice }, set: { app.setPrompterVoice($0) })) {
                        Text("Суфлёр идёт за голосом")
                        Text("Спросит микрофон и распознавание речи. Всё на этом Mac, аудио не пишется")
                            .font(SettingsStyle.caption).foregroundStyle(.secondary)
                    }
                    .disabled(!settings.enabled)
                }
                Toggle(isOn: Binding(get: { settings.calendar }, set: { app.setCalendarEnabled($0) })) {
                    Text("Календарь")
                    Text("Спросит доступ к Календарям. Только чтение. Идущий звонок включает тишину маскота")
                        .font(SettingsStyle.caption).foregroundStyle(.secondary)
                }
                .disabled(!settings.enabled)
                Toggle("Полка", isOn: Binding(get: { settings.shelf }, set: { app.setShelfEnabled($0) }))
                    .disabled(!settings.enabled)
                if settings.shelf {
                    Toggle(isOn: Binding(get: { settings.shelfScreenshots }, set: { app.setShelfScreenshots($0) })) {
                        Text("Новые снимки экрана — на полку")
                        Text("Хранятся только ссылки на файлы, выход из приложения очищает полку")
                            .font(SettingsStyle.caption).foregroundStyle(.secondary)
                    }
                    .disabled(!settings.enabled)
                }
                Toggle(isOn: Binding(get: { settings.music }, set: { app.setMusicEnabled($0) })) {
                    Text("Музыка")
                    if model.console.media.availability == .unavailable {
                        Text("Недоступно на этой системе").font(SettingsStyle.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!settings.enabled)
            }
            DictationSettings(model: model, app: app, controller: app.dictation)
            Section("Лимиты Claude") {
                LabeledContent("Statusline", value: model.statuslineInstalled ? "подключена" : "не подключена")
                if model.statuslineBroken {
                    Text("Исходная команда ссылается на скрипт Orca, которого больше нет. Отключите и подключите снова")
                        .font(SettingsStyle.caption).foregroundStyle(.secondary)
                }
                if model.statuslineInstalled {
                    Button("Отключить") { app.uninstallStatusline() }
                } else {
                    Button("Подключить…") { app.installStatusline() }
                }
                Text("Данные приходят только с подпиской Pro или Max и после первого ответа в сессии")
                    .font(SettingsStyle.caption).foregroundStyle(.secondary)
            }
            Section("Лимиты Codex") {
                LabeledContent("Состояние", value: model.codexStatus ?? "ещё не проверялось")
                TextField("Путь к codex", text: Binding(get: { settings.codexPath ?? "" }, set: { app.setCodexPath($0) }),
                          prompt: Text("найти самому"))
                Picker("Аккаунт", selection: Binding(get: { settings.codexHome ?? "" }, set: { app.setCodexHome($0) })) {
                    Text("~/.codex").tag("")
                    ForEach(Array(CodexAppServer.accountHomes().enumerated()), id: \.element) { index, home in
                        Text("Orca, аккаунт \(index + 1)").tag(home)
                    }
                }
                Text("В Orca свой аккаунт Codex: выберите его, иначе лимиты будут от ~/.codex")
                    .font(SettingsStyle.caption).foregroundStyle(.secondary)
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
                    Text(coworkStatus(model)).font(SettingsStyle.caption).foregroundStyle(.secondary)
                }
            }
            Section("ChatGPT") {
                LabeledContent("Хуки Codex", value: Self.codexHooked ? "зовут маскота" + Self.ago(model, .codex) : "не найдены")
                Text("Приложение ChatGPT перенимает хуки Claude Code: маскот видит его работу")
                    .font(SettingsStyle.caption).foregroundStyle(.secondary)
            }
            Section("Orca") {
                Toggle(isOn: Binding(get: { model.config.sources.orca }, set: { app.setOrcaEnabled($0) })) {
                    Text("Следить за агентами в Orca")
                    Text(orcaStatus(model)).font(SettingsStyle.caption).foregroundStyle(.secondary)
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
                        .font(SettingsStyle.caption).foregroundStyle(.secondary)
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
    static var codexHooked: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/hooks.json")
        return (try? String(contentsOf: url, encoding: .utf8))?.contains("pulse-hook") ?? false
    }

    static func ago(_ model: PulseModel, _ source: AgentEvent.Source) -> String {
        guard let date = model.lastEventBySource[source] else { return "" }
        return " · " + HumanTime.ago(Date().timeIntervalSince(date))
    }
}
