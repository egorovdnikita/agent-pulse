import AgentPulseCore
import AppKit
import SwiftUI

/// Вкладки окна «Настройки».
enum SettingsNavigation {
    enum Tab: String, CaseIterable {
        case general, character, sources, console, news, lab

        var title: String {
            switch self {
            case .general: "Основные"
            case .character: "Характер"
            case .sources: "Агенты"
            case .console: "Модули"
            case .news: "Новости"
            case .lab: "Лаборатория"
            }
        }

        var subtitle: String {
            switch self {
            case .general: "Где живёт маскот, как выглядит и запускается ли вместе с Mac."
            case .character: "Как часто маскот говорит и шутит, и когда он молчит."
            case .sources: "Откуда маскот знает, что делают агенты, и сколько у них осталось лимитов."
            case .console: "Что есть в Пульте. Настройки модуля видны, пока он включён."
            case .news: "О чём маскот рассказывает, когда ты рядом и не занят."
            case .lab: "Настроение, чувства и ручной запуск состояний и реакций."
            }
        }

        /// Цвет плашки, как у разделов Системных настроек.
        var tint: Color {
            switch self {
            case .general: Color(nsColor: .systemGray)
            case .character: Color(nsColor: .systemOrange)
            case .sources: Color(nsColor: .systemPurple)
            case .console: Color(nsColor: .systemBlue)
            case .news: Color(nsColor: .systemPink)
            case .lab: Color(nsColor: .systemGreen)
            }
        }

        /// Что есть в разделе: по этим словам его находит поиск.
        var keywords: [String] {
            switch self {
            case .general: ["маскот", "облик", "бот", "угол", "дисплей", "экран", "размер", "запуск", "вход", "эксперимент", "версия", "лицензии"]
            case .character: ["болтливость", "озорство", "тишина", "тихие часы", "простой", "день рождения", "память", "забыть"]
            case .sources: ["claude", "code", "chatgpt", "codex", "cowork", "orca", "браузер", "chrome", "figma", "лимиты", "подключить"]
            case .console: ["пульт", "клавиша", "звуки", "лимиты", "суфлёр", "календарь", "файлы", "музыка", "диктовка", "перевод", "голос"]
            case .news: ["новости", "темы", "дизайн", "наука", "игры", "космос", "экономика", "искусство"]
            case .lab: ["лаборатория", "настроение", "гравитация", "жест", "состояния", "реакции", "сигнал"]
            }
        }

        func matches(_ query: String) -> Bool {
            let words = query.lowercased().trimmingCharacters(in: .whitespaces)
            return words.isEmpty || title.lowercased().contains(words) || keywords.contains { $0.contains(words) }
        }

        var icon: String {
            switch self {
            case .general: "gearshape.fill"
            case .character: "face.smiling.inverse"
            case .sources: "cpu.fill"
            case .console: "square.grid.2x2.fill"
            case .news: "newspaper.fill"
            case .lab: "flask.fill"
            }
        }
    }
}

/// Одно окно: всё, что не нужно каждый день, живёт здесь, а не в меню.
@MainActor
enum SettingsWindow {
    static let size = CGSize(width: 820, height: 620)

    @ViewBuilder
    static func content(_ tab: SettingsNavigation.Tab, app: AppDelegate, selection: SettingsSelection) -> some View {
        Group {
            switch tab {
            case .general: GeneralSettings(app: app)
            case .character: CharacterSettings(app: app)
            case .sources: SourcesSettings(app: app)
            case .console: ConsoleSettings(app: app, selection: selection)
            case .news: NewsSettings(app: app)
            case .lab: MascotLabView(model: app.model, extras: AnyView(LabExtras(app: app)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Выбранный раздел. В наблюдаемом классе: `@State` без Xcode недоступен.
@Observable
final class SettingsSelection {
    var tab: SettingsNavigation.Tab = .general
    /// Блок, к которому перейти: название его заголовка.
    var anchor: String?
    /// Раскрытый модуль: один за раз.
    var module: String?
    /// Поиск над колонкой разделов.
    var query = ""
}

/// Окно «Настройки» — как системные: боковая колонка и сгруппированная форма.
struct SettingsRoot: View {
    let app: AppDelegate
    @Bindable var selection: SettingsSelection

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { Optional(selection.tab) },
                set: { tab in
                    guard let tab else { return }
                    selection.anchor = nil
                    selection.tab = tab
                }
            )) {
                ForEach(tabs, id: \.self) { tab in
                    Label { Text(tab.title) } icon: { SettingsIcon(name: tab.icon, tint: tab.tint) }
                        .tag(tab)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                SidebarSearch(text: $selection.query)
                    .padding(.horizontal, 10)
                    // Поле под кнопками окна; между кнопками, полем и разделами воздух как у системы.
                    .padding(.top, 34)
                    .padding(.bottom, 8)
            }
            .ignoresSafeArea(.container, edges: .top)
            .frame(width: 220)
            .navigationSplitViewColumnWidth(220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsWindow.content(selection.tab, app: app, selection: selection)
                .id(selection.tab)
                // Полоса с названием: 44 pt, как у Системных настроек, название по центру — сверху и снизу поровну.
                // Системная панель на macOS 26 выше и прижимает название к кнопкам окна.
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Text(selection.tab.title)
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 20)
                            .accessibilityAddTraits(.isHeader)
                        Divider()
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                }
                .ignoresSafeArea(.container, edges: .top)
        }
        // Своё название рисует полоса над формой; системное панель подставила бы «Без названия» поверх.
        .modifier(HidesToolbarTitle())
        .frame(minWidth: 720, minHeight: 480)
        .environment(\.settingsAnchor, selection.anchor)
    }

    /// «Лаборатория» — только с включёнными экспериментами.
    private var tabs: [SettingsNavigation.Tab] {
        SettingsNavigation.Tab.allCases
            .filter { $0 != .lab || app.model.config.senses.experimental || selection.tab == .lab }
            .filter { $0.matches(selection.query) }
    }
}

private extension AppDelegate {
    func senseBinding(_ keyPath: WritableKeyPath<PulseConfig.Senses, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.model.config.senses[keyPath: keyPath] },
            set: {
                self.model.config.senses[keyPath: keyPath] = $0
                self.model.applyCharacter()
                self.startSenses()
            }
        )
    }
}

/// Поиск как в Системных настройках: капсула 28 pt с системной заливкой, лупа и крестик — SF Symbols.
/// Системное поле поиска выше 24 pt не растягивается.
private struct SidebarSearch: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Поиск", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(.quaternary, in: Capsule())
    }
}

/// Убирает системное название из панели (macOS 15 и новее).
private struct HidesToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

// MARK: - Основные

private struct GeneralSettings: View {
    let app: AppDelegate

    var body: some View {
        let model = app.model
        SettingsPage {
            SettingsBlock("Маскот", footnote: PalSkin.installed().isEmpty ? "Боты не установлены, маскот остаётся светящимся кругом" : nil) {
                Toggle("Показывать маскота", isOn: Binding(get: { model.overlayVisible }, set: { app.setOverlayVisible($0) }))
                let bots = PalSkin.installed()
                SettingsPicker("Кто на маскоте", selection: Binding(get: { model.config.mascot.skin }, set: { app.setSkin($0) })) {
                    Text("Светящийся круг").tag(PalSkin.classic)
                    if !bots.isEmpty { Text("Меняется сам").tag(PalWardrobe.Mode.shuffleConfig) }
                    ForEach(bots, id: \.bot) { Text($0.bot).tag($0.configValue) }
                }
                LabeledContent("Угол экрана") {
                    HStack(spacing: 8) {
                        Button("Вернуть в угол") { app.panel?.resetPosition() }
                        Picker("Угол экрана", selection: Binding(get: { model.config.display.anchor }, set: { app.setAnchor($0) })) {
                            ForEach(PulseConfig.Display.Anchor.allCases, id: \.self) { Text(Self.title($0)).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }
                SettingsPicker("Дисплей", selection: Binding(get: { model.config.display.screen }, set: { app.setScreen($0) })) {
                    Text("С Dock").tag("dock")
                    Text("Основной").tag("main")
                    Text("С курсором").tag("active")
                    Text("Встроенный").tag("builtin")
                }
                LabeledContent("Размер") {
                    HStack {
                        Slider(value: Binding(get: { model.config.display.mascotSize }, set: { app.setMascotSize($0) }), in: 40...72, step: 4)
                        Text("\(Int(model.config.display.mascotSize)) pt").monospacedDigit().foregroundStyle(SettingsStyle.muted)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            SettingsBlock {
                Toggle("Запускать при входе", isOn: Binding(get: { model.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
                Toggle(isOn: app.senseBinding(\.experimental)) {
                    Text("Эксперименты")
                    Text("Добавляет раздел «Лаборатория»").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                }
            }
            SettingsBlock(footnote: "Иконки Solar — 480 Design, CC BY 4.0. Анимации ботов — Lottie, Airbnb, Apache 2.0. Остальное — в лицензиях.") {
                LabeledContent("Версия") {
                    HStack(spacing: 8) {
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                        Button("Лицензии") {
                            if let url = Bundle.main.url(forResource: "Licenses", withExtension: nil) { NSWorkspace.shared.open(url) }
                        }
                    }
                }
            }
        }
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
        SettingsPage {
            SettingsBlock {
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
            }
            SettingsBlock("Тишина", footnote: "В созвон, на полном экране и в тихие часы облачко молчит. «Жду тебя» слышно всегда.") {
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
            }
            SettingsBlock {
                Toggle("Знаю день рождения", isOn: $form.known)
                if form.known {
                    DatePicker("Дата", selection: $form.date, displayedComponents: .date)
                }
            }
            .onChange(of: form.known) { saveBirthday() }
            .onChange(of: form.date) { saveBirthday() }
            SettingsBlock(footnote: "Только счётчики дня, 30 дней, на этом Mac.") {
                LabeledContent("Память") {
                    Button("Забыть всё", role: .destructive) { model.resetMemory() }
                }
            }
        }
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
        SettingsPage {
            SettingsBlock {
                Toggle("Рассказывать новости", isOn: Binding(get: { on }, set: { app.setDesignNews($0) }))
            }
            SettingsBlock("Темы", footnote: "Только публичные ленты, без данных о тебе.") {
                ForEach(NewsTopic.allCases, id: \.self) { topic in
                    Toggle(topic.title, isOn: Binding(
                        get: { model.config.character.enabledNewsTopics.contains(topic) },
                        set: { app.setNewsTopic(topic, on: $0) }
                    ))
                }
            }
            .disabled(!on)
        }
    }
}

// MARK: - Модули

private struct ConsoleSettings: View {
    let app: AppDelegate
    let selection: SettingsSelection

    private func card<Options: View>(
        _ title: String, _ summary: String, icon: String, tint: Color, isOn: Bool, toggle: @escaping (Bool) -> Void,
        @ViewBuilder options: () -> Options
    ) -> some View {
        ModuleCard(
            title: title, summary: summary, icon: icon, tint: tint, isOn: isOn, toggle: toggle, options: options
        )
    }

    var body: some View {
        let model = app.model
        let settings = model.config.console
        SettingsPage {
            SettingsBlock {
                Toggle("Показывать Пульт", isOn: Binding(get: { settings.enabled }, set: { app.setConsoleEnabled($0) }))
                SettingsPicker("Клавиша раскрытия", selection: Binding(get: { settings.hotkey }, set: { app.setConsoleHotKey($0) })) {
                    ForEach(ConsoleHotKey.letters, id: \.self) { Text("⌃⌥\($0.uppercased())").tag($0) }
                    Text("Нет").tag("")
                }
                .disabled(!settings.enabled)
                Toggle("Звуки", isOn: Binding(get: { settings.sounds }, set: { app.setSounds($0) }))
                    .disabled(!settings.enabled)
            }
            Group {
                card("Лимиты", "Сколько осталось у Claude и Codex", icon: "chart.pie.fill", tint: Color(nsColor: .systemGreen), isOn: settings.limits, toggle: { app.setLimitsEnabled($0) }) {
                    ModuleOption {
                        Button("Подключить в разделе «Агенты»") { app.showSettings(.sources, anchor: "Лимиты") }
                    }
                }
                card("Суфлёр", "Текст под камерой", icon: "text.alignleft", tint: Color(nsColor: .systemOrange), isOn: settings.prompter, toggle: { app.setPrompterEnabled($0) }) {
                    ModuleOption {
                        SettingsPicker("Размер текста", selection: Binding(get: { settings.prompterTextSize }, set: { app.setPrompterTextSize($0) })) {
                            ForEach(PrompterTextSize.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                    ModuleOption {
                        Toggle(isOn: Binding(get: { settings.prompterVoice }, set: { app.setPrompterVoice($0) })) {
                            Text("Идёт за голосом")
                            Text("Спросит микрофон. Всё на этом Mac").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                        }
                    }
                    ModuleOption {
                        Toggle(isOn: Binding(get: { settings.prompterHidden }, set: { app.setPrompterHidden($0) })) {
                            Text("Скрывать при показе экрана")
                            Text("В Zoom на macOS 15 и новее может быть виден").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                        }
                    }
                    ModuleOption { ShortcutRow(title: "Старт и стоп", keys: "⌃⌥P", busy: model.console.busyKeys.contains("p")) }
                    ModuleOption { ShortcutRow(title: "Скорость", keys: "⌃⌥↑ ⌃⌥↓") }
                    ModuleOption { ShortcutRow(title: "Строка назад и вперёд", keys: "⌃⌥← ⌃⌥→") }
                }
                card("Календарь", "Встречи и кнопка «Войти»", icon: "calendar", tint: Color(nsColor: .systemRed), isOn: settings.calendar, toggle: { app.setCalendarEnabled($0) }) {
                    ModuleOption {
                        Text("Спросит доступ к Календарям, только чтение. Идущий звонок включает тишину маскота")
                            .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                    }
                }
                card("Файлы", "Полка для файлов под рукой", icon: "folder.fill", tint: Color(nsColor: .systemBlue), isOn: settings.shelf, toggle: { app.setShelfEnabled($0) }) {
                    ModuleOption {
                        Toggle(isOn: Binding(get: { settings.shelfScreenshots }, set: { app.setShelfScreenshots($0) })) {
                            Text("Новые снимки экрана")
                            Text("Хранятся только ссылки, выход очищает список").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                        }
                    }
                }
                card(
                    "Музыка", model.console.media.availability == .unavailable ? "Недоступно на этой системе" : "Что играет и управление",
                    icon: "music.note", tint: Color(nsColor: .systemPink), isOn: settings.music, toggle: { app.setMusicEnabled($0) }
                ) {
                    EmptyView()
                }
                card("Диктовка", "Зажми клавишу, говори, отпусти", icon: "mic.fill", tint: Color(nsColor: .systemIndigo), isOn: settings.dictation, toggle: { app.setDictationEnabled($0) }) {
                    DictationOptions(model: model, app: app, controller: app.dictation)
                }
                if ConsoleTranslator.isAvailable {
                    card("Перевод", "Русский и английский на этом Mac", icon: "character.bubble.fill", tint: Color(nsColor: .systemTeal), isOn: settings.translator, toggle: { app.setTranslatorEnabled($0) }) {
                        TranslatorOptions(model: model, app: app)
                    }
                }
            }
            .disabled(!settings.enabled)
        }
    }
}

// MARK: - Агенты

private struct SourcesSettings: View {
    let app: AppDelegate

    private func row<Trailing: View>(_ title: String, _ status: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        // Кнопки по центру строки: строка формы ставит их по первой строке подписи.
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(status).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }

    var body: some View {
        @Bindable var model = app.model
        let settings = model.config.console
        SettingsPage {
            SettingsBlock(footnote: model.serverError != nil ? "Не вижу агентов. Перезапусти приложение" : nil) {
                row("Claude Code", model.hooksInstalled ? "Подключено" + Self.ago(model, .claudeCode) : "Не подключено") {
                    if model.hooksInstalled {
                        Button("Отключить") { app.uninstallHooks() }
                    } else {
                        Button("Подключить") { app.installHooks() }
                    }
                }
                row("ChatGPT", Self.codexHooked ? "Подключено" + Self.ago(model, .codex) : "Подключается вместе с Claude Code") {
                    EmptyView()
                }
                row("Claude Cowork", coworkStatus(model)) {
                    Toggle("Claude Cowork", isOn: Binding(get: { model.config.sources.cowork }, set: { app.setCoworkEnabled($0) }))
                        .labelsHidden()
                }
                row("Агенты в Orca", orcaStatus(model)) {
                    Toggle("Агенты в Orca", isOn: Binding(get: { model.config.sources.orca }, set: { app.setOrcaEnabled($0) }))
                        .labelsHidden()
                }
                row("Claude в браузере", model.browserBridgeInstalled ? "Подключено" + Self.ago(model, .claudeChat) : "Не подключено") {
                    if model.browserBridgeInstalled {
                        Button("Показать расширение") { app.revealExtension() }
                        Button("Отключить") { app.uninstallBrowserBridge() }
                    } else {
                        Button("Подключить") { app.installBrowserBridge() }
                    }
                }
                row("Figma", model.companionError != nil ? "Плагин не подключился" : "Плагин-компаньон") {
                    Button("Показать плагин") { app.revealFigmaPlugin() }
                }
            }
            SettingsBlock("Лимиты", footnote: "Claude отдаёт данные только с подпиской Pro или Max и после первого ответа в сессии.") {
                row("Claude", model.statuslineBroken ? "Подключение сломалось. Отключи и подключи снова" : model.statuslineInstalled ? "Подключено" : "Не подключено") {
                    if model.statuslineInstalled {
                        Button("Отключить") { app.uninstallStatusline() }
                    } else {
                        Button("Подключить") { app.installStatusline() }
                    }
                }
                row("Codex", model.codexStatus ?? "Ещё не проверялось") { EmptyView() }
                let homes = CodexAppServer.accountHomes()
                if !homes.isEmpty {
                    SettingsPicker("Профиль Codex", selection: Binding(get: { settings.codexHome ?? "" }, set: { app.setCodexHome($0) })) {
                        Text("Обычный").tag("")
                        ForEach(Array(homes.enumerated()), id: \.element) { index, home in
                            Text("Orca, аккаунт \(index + 1)").tag(home)
                        }
                    }
                }
                // Нужно, только когда Codex сам не нашёлся.
                if settings.codexPath != nil || model.codexStatus?.contains("не найден") == true {
                    LabeledContent("Где лежит Codex") {
                        TextField("Где лежит Codex", text: Binding(get: { settings.codexPath ?? "" }, set: { app.setCodexPath($0) }), prompt: Text("найти самому"))
                            .labelsHidden()
                            .frame(maxWidth: 240)
                    }
                }
            }
        }
    }

    private func coworkStatus(_ model: PulseModel) -> String {
        switch model.coworkWatching {
        case true?: "Подключено" + Self.ago(model, .cowork)
        case false?: "Не найден"
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

// MARK: - Лаборатория

/// Редкое и отладочное: то, чему не место на основных экранах.
struct LabExtras: View {
    let app: AppDelegate

    var body: some View {
        let model = app.model
        let settings = model.config.console
        SettingsBlock("Сейчас") {
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.now(model)).font(SettingsStyle.bodyMedium)
                if let today = Self.today(model) {
                    Text(today).foregroundStyle(SettingsStyle.muted)
                }
                MoodBars(mood: model.mood).padding(.top, 2)
            }
            LabeledContent("Оценки реплик сегодня") {
                Text("нравится \(model.feedbackToday["мило", default: 0]) · не надо \(model.feedbackToday["бесит", default: 0])")
            }
            LabeledContent("Отключено реплик") { Text("\(model.mutedReactions.count)") }
        }
        SettingsBlock("Что замечает") {
            Toggle("Агенты", isOn: app.senseBinding(\.agents))
            Toggle("Тело ноутбука", isOn: app.senseBinding(\.body))
            Toggle("Ритм и время", isOn: app.senseBinding(\.rhythm))
            Toggle("Звук", isOn: app.senseBinding(\.audio))
        }
        SettingsBlock("Поведение") {
            Toggle(isOn: Binding(get: { model.config.display.gravity }, set: { app.setGravity($0) })) {
                Text("Гравитация")
                Text("Отпущенный маскот падает на «пол» с отскоками").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
            Toggle(isOn: Binding(get: { settings.trackpadGesture }, set: { app.setTrackpadGesture($0) })) {
                Text("Двойное касание двумя пальцами")
                Text("Раскрывает Пульт. Может перестать работать с обновлением macOS").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
            if settings.trackpadGesture {
                LabeledContent("Состояние", value: app.trackpadGesture.status.title)
            }
        }
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
            row("Бодрость", mood.energy, ConsoleStyle.orange)
            row("Спокойствие", 1 - mood.stress, Color(hex: 0x64D2FF))
            row("Радость", mood.joy, Color(hex: 0xFF375F))
            row("Общение", mood.social, ConsoleStyle.blue)
        }
        .font(SettingsStyle.caption)
    }

    private func row(_ title: String, _ value: Double, _ color: Color) -> some View {
        GridRow {
            Text(title).foregroundStyle(SettingsStyle.muted)
            // Своя шкала: системная в неактивном окне теряет цвет.
            Capsule().fill(SettingsStyle.track)
                .frame(width: 140, height: 6)
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: 140 * min(max(value, 0.03), 1), height: 6)
                }
        }
    }
}
