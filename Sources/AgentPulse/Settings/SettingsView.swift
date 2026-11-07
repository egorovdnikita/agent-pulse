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
    /// Блок, к которому перейти: название его заголовка.
    var anchor: String?
}

/// Окно «Настройки»: слева разделы словами, справа заголовок и карточки, как в Пульте.
struct SettingsRoot: View {
    let app: AppDelegate
    @Bindable var selection: SettingsSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ZStack {
                section
                    .id(selection.tab)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeOut(duration: 0.16), value: selection.tab)
        }
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
        .background(Color.black)
        .font(SettingsStyle.body)
        .foregroundStyle(.white)
        .tint(.white)
        .toggleStyle(SettingsSwitchStyle())
        .buttonStyle(SettingsButtonStyle())
        .preferredColorScheme(.dark)
        .environment(\.settingsAnchor, selection.anchor)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.tab.title)
                    .font(SettingsStyle.title)
                    .tracking(-0.22)
                    .accessibilityAddTraits(.isHeader)
                Text(selection.tab.subtitle)
                    .font(SettingsStyle.body)
                    .foregroundStyle(SettingsStyle.muted)
            }
            .padding(.horizontal, 24 + ConsoleStyle.cardPadding)
            .padding(.top, 44)
            SettingsWindow.content(selection.tab, app: app)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(SettingsNavigation.Tab.allCases.enumerated()), id: \.element) { index, tab in
                SettingsSidebarItem(tab: tab, number: index + 1, isSelected: selection.tab == tab) {
                    selection.anchor = nil
                    selection.tab = tab
                }
            }
            Spacer()
        }
        .padding(.top, 52)
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .frame(width: SettingsStyle.sidebarWidth)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) { Rectangle().fill(ConsoleStyle.edge).frame(width: 1) }
    }
}

// MARK: - Основное

private struct GeneralSettings: View {
    let app: AppDelegate

    var body: some View {
        let model = app.model
        SettingsPage {
            SettingsBlock {
                HStack(alignment: .top, spacing: 16) {
                    MascotView(animator: model.animator, diameter: 48)
                        .frame(width: 104, height: 104)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.now(model)).font(ConsoleStyle.font(15, .semibold))
                        if let today = Self.today(model) {
                            Text(today).font(SettingsStyle.body).foregroundStyle(SettingsStyle.muted)
                        }
                        MoodBars(mood: model.mood).padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            }
            SettingsBlock("Облик") {
                let bots = PalSkin.installed()
                let mode = PalWardrobe.Mode(config: model.config.mascot.skin)
                SettingsPicker("Кто на маскоте", selection: Binding(get: { model.config.mascot.skin }, set: { app.setSkin($0) })) {
                    Text("Светящийся круг").tag(PalSkin.classic)
                    if !bots.isEmpty { Text("Меняется сам").tag(PalWardrobe.Mode.shuffleConfig) }
                    ForEach(bots, id: \.bot) { Text($0.bot).tag($0.configValue) }
                }
                if bots.isEmpty {
                    Text("Боты не установлены, маскот остаётся светящимся кругом")
                        .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                } else if mode != .classic {
                    if mode == .shuffle {
                        Text("Новая задача любого агента или пробуждение — новый бот, не чаще раза в 3 мин. Все \(bots.count) по очереди, без повторов")
                            .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                    }
                }
            }
            SettingsBlock("Где живёт") {
                LabeledContent("Угол экрана") {
                    CornerPicker(anchor: Binding(get: { model.config.display.anchor }, set: { app.setAnchor($0) }))
                }
                SettingsPicker("Дисплей", selection: Binding(get: { model.config.display.screen }, set: { app.setScreen($0) })) {
                    Text("С Dock").tag("dock")
                    Text("Основной").tag("main")
                    Text("С курсором").tag("active")
                    Text("Встроенный").tag("builtin")
                }
                LabeledContent("Размер") {
                    HStack {
                        Slider(value: Binding(get: { model.config.display.mascotSize }, set: { app.setMascotSize($0) }),
                               in: 40...72, step: 4)
                        Text("\(Int(model.config.display.mascotSize)) pt").monospacedDigit().foregroundStyle(SettingsStyle.muted)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Button("Вернуть маскота в угол") { app.panel?.resetPosition() }
            }
            SettingsBlock("Поведение") {
                Toggle("Показывать маскота", isOn: Binding(get: { model.overlayVisible }, set: { app.setOverlayVisible($0) }))
                Toggle(isOn: Binding(get: { model.config.display.gravity }, set: { app.setGravity($0) })) {
                    Text("Гравитация")
                    Text("Отпущенный маскот падает на «пол» с отскоками").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                }
                Toggle("Запускать при входе", isOn: Binding(get: { model.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
                if model.serverError != nil {
                    Text("Не вижу агентов. Перезапусти приложение").foregroundStyle(ConsoleStyle.red)
                }
            }
            SettingsBlock("О программе") {
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                Text("Иконки категорий — Solar Icons, 480 Design, лицензия CC BY 4.0. Анимации ботов играет Lottie от Airbnb, лицензия Apache 2.0. «Музыка» работает через mediaremote-adapter, Jonas van den Berg, лицензия BSD-3. Диктовка: GigaAM (лицензия MIT), sherpa-onnx (Apache 2.0), ONNX Runtime (MIT).")
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                Button("Лицензии") {
                    if let url = Bundle.main.url(forResource: "Licenses", withExtension: nil) { NSWorkspace.shared.open(url) }
                }
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
            row("Общение", mood.social, Color(hex: 0x0A84FF))
        }
        .font(SettingsStyle.caption)
    }

    private func row(_ title: String, _ value: Double, _ color: Color) -> some View {
        GridRow {
            Text(title).foregroundStyle(SettingsStyle.muted)
            // Своя шкала: системная в неактивном окне теряет цвет.
            Capsule().fill(ConsoleStyle.track)
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
                .fill(ConsoleStyle.card)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ConsoleStyle.edge))
            // Dock внизу — ориентир.
            Capsule().fill(ConsoleStyle.track).frame(width: 40, height: 4)
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 4)
            ForEach(PulseConfig.Display.Anchor.allCases, id: \.self) { corner in
                Button { anchor = corner } label: {
                    Circle()
                        .fill(corner == anchor ? ConsoleStyle.green : ConsoleStyle.edge)
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
                Text("Болтливость — как часто облачко вне работы агентов. Озорство — до \(Int((model.config.character.mischief * 8).rounded())) приколов в день.")
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
            SettingsBlock("Тишина") {
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
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
            SettingsBlock("День рождения") {
                Toggle("Знаю день рождения", isOn: $form.known)
                if form.known {
                    DatePicker("Дата", selection: $form.date, displayedComponents: .date)
                }
            }
            .onChange(of: form.known) { saveBirthday() }
            .onChange(of: form.date) { saveBirthday() }
            SettingsBlock("Оценки реплик") {
                LabeledContent("Сегодня") {
                    Text("нравится \(model.feedbackToday["мило", default: 0]) · не надо \(model.feedbackToday["бесит", default: 0])")
                }
                LabeledContent("Отключено реплик") {
                    Text("\(model.mutedReactions.count)")
                }
            }
            SettingsBlock("Память") {
                Text("Только счётчики дня — задачи, ошибки, перерывы, поглаживания. Хранится 30 дней на этом Mac.")
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                Button("Забыть всё", role: .destructive) { model.resetMemory() }
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
                Text("Каждые 15 минут, с 9 до 22, когда ты рядом и не занят созвоном или агентом. Дизайн — большая часть.")
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
            SettingsBlock("Темы") {
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
                                .background(.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title)
                                Text(Set(sources.map(\.name).map { $0.components(separatedBy: " · ").first ?? $0 }).sorted().joined(separator: ", "))
                                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .disabled(!on)
            SettingsBlock {
                Text("Только публичные ленты и открытые Telegram-каналы, без данных о тебе. Показанное помнится на этом Mac.")
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
        }
    }
}

// MARK: - Пульт

private struct ConsoleSettings: View {
    let app: AppDelegate

    var body: some View {
        let model = app.model
        let settings = model.config.console
        SettingsPage {
            SettingsBlock {
                Toggle(isOn: Binding(get: { settings.enabled }, set: { app.setConsoleEnabled($0) })) {
                    Text("Показывать Пульт")
                    Text("Виджет в углу напротив маскота. Свёрнутый всегда показывает лимиты")
                        .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                }
            }
            SettingsBlock {
                Toggle(isOn: Binding(get: { settings.sounds }, set: { app.setSounds($0) })) {
                    Text("Звуки")
                    Text("Файл на полке, текст вставлен, лимит на исходе, запись диктовки. Молчат при суфлёре, в созвон и в тихие часы")
                        .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                }
                .disabled(!settings.enabled)
            }
            SettingsBlock("Модули") {
                Toggle("Лимиты", isOn: Binding(get: { settings.limits }, set: { app.setLimitsEnabled($0) }))
                    .disabled(!settings.enabled)
                if settings.limits {
                    SettingsPicker("В капсуле", selection: Binding(get: { settings.capsuleWindow }, set: { app.setCapsuleWindow($0) })) {
                        Text("Самое тесное окно").tag("")
                        ForEach(LimitWindowKind.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                    .padding(.leading, SettingsStyle.childIndent)
                    .disabled(!settings.enabled)
                }
                Toggle(isOn: Binding(get: { settings.prompter }, set: { app.setPrompterEnabled($0) })) {
                    Text("Суфлёр")
                    Text("Текст под камерой. Клик по панели — пауза")
                        .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                }
                .disabled(!settings.enabled)
                if settings.prompter {
                    SettingsPicker("Размер текста", selection: Binding(get: { settings.prompterTextSize }, set: { app.setPrompterTextSize($0) })) {
                        ForEach(PrompterTextSize.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .padding(.leading, SettingsStyle.childIndent)
                    .disabled(!settings.enabled)
                    Toggle(isOn: Binding(get: { settings.prompterHidden }, set: { app.setPrompterHidden($0) })) {
                        Text("Скрывать суфлёр при показе экрана")
                        Text("В Zoom на macOS 15 и новее суфлёр может быть виден. Meet, Teams, Телемост и QuickTime не проверены")
                            .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                    }
                    .padding(.leading, SettingsStyle.childIndent)
                    .disabled(!settings.enabled)
                    Toggle(isOn: Binding(get: { settings.prompterVoice }, set: { app.setPrompterVoice($0) })) {
                        Text("Суфлёр идёт за голосом")
                        Text("Спросит микрофон и распознавание речи. Всё на этом Mac, аудио не пишется")
                            .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                    }
                    .padding(.leading, SettingsStyle.childIndent)
                    .disabled(!settings.enabled)
                }
                Toggle(isOn: Binding(get: { settings.calendar }, set: { app.setCalendarEnabled($0) })) {
                    Text("Календарь")
                    Text("Спросит доступ к Календарям. Только чтение. Идущий звонок включает тишину маскота")
                        .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                }
                .disabled(!settings.enabled)
                Toggle("Полка", isOn: Binding(get: { settings.shelf }, set: { app.setShelfEnabled($0) }))
                    .disabled(!settings.enabled)
                if settings.shelf {
                    Toggle(isOn: Binding(get: { settings.shelfScreenshots }, set: { app.setShelfScreenshots($0) })) {
                        Text("Новые снимки экрана — на полку")
                        Text("Хранятся только ссылки на файлы, выход из приложения очищает полку")
                            .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                    }
                    .padding(.leading, SettingsStyle.childIndent)
                    .disabled(!settings.enabled)
                }
                Toggle(isOn: Binding(get: { settings.music }, set: { app.setMusicEnabled($0) })) {
                    Text("Музыка")
                    if model.console.media.availability == .unavailable {
                        Text("Недоступно на этой системе").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                    }
                }
                .disabled(!settings.enabled)
            }
            DictationSettings(model: model, app: app, controller: app.dictation)
            SettingsBlock("Клавиши") {
                SettingsPicker("Клавиша раскрытия", selection: Binding(get: { settings.hotkey }, set: { app.setConsoleHotKey($0) })) {
                    ForEach(ConsoleHotKey.letters, id: \.self) { Text("⌃⌥\($0.uppercased())").tag($0) }
                    Text("Нет").tag("")
                }
                .disabled(!settings.enabled)
                if settings.prompter { ShortcutRow(title: "Суфлёр: старт и стоп", keys: "⌃⌥P", busy: model.console.busyKeys.contains("prompter")) }
                if settings.prompter { ShortcutRow(title: "Суфлёр: скорость", keys: "⌃⌥↑ ⌃⌥↓") }
                if settings.prompter { ShortcutRow(title: "Суфлёр: строка назад и вперёд", keys: "⌃⌥← ⌃⌥→") }
                if settings.dictation { ShortcutRow(title: "Диктовка: держи и говори", keys: "⌃⌥D", busy: model.console.busyKeys.contains("dictation")) }
                if settings.translator, ConsoleTranslator.isAvailable { ShortcutRow(title: "Перевести выделенное", keys: "⌃⌥T", busy: model.console.busyKeys.contains("translate")) }
            }
            if model.config.senses.experimental {
                SettingsBlock("Эксперимент") {
                    Toggle(isOn: Binding(get: { settings.trackpadGesture }, set: { app.setTrackpadGesture($0) })) {
                        Text("Двойное касание двумя пальцами")
                        Text("Раскрывает Пульт. Читает касания через закрытый системный интерфейс, поэтому может перестать работать с обновлением macOS. ⌃⌥X работает всегда")
                            .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                    }
                    .disabled(!settings.enabled)
                    if settings.trackpadGesture {
                        LabeledContent("Состояние", value: app.trackpadGesture.status.title)
                    }
                }
            }
            SettingsBlock("Лимиты Claude") {
                LabeledContent("Подключение") {
                    HStack(spacing: 10) {
                        Text(model.statuslineInstalled ? "подключено" : "не подключено")
                        if model.statuslineInstalled {
                            Button("Отключить") { app.uninstallStatusline() }
                        } else {
                            Button("Подключить…") { app.installStatusline() }
                        }
                    }
                }
                if model.statuslineBroken {
                    Text("Исходная команда ссылается на скрипт Orca, которого больше нет. Отключите и подключите снова")
                        .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                }
                Text("Данные приходят только с подпиской Pro или Max и после первого ответа в сессии")
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
            SettingsBlock("Лимиты Codex") {
                LabeledContent("Состояние", value: model.codexStatus ?? "ещё не проверялось")
                LabeledContent("Где лежит Codex") {
                    TextField("Где лежит Codex", text: Binding(get: { settings.codexPath ?? "" }, set: { app.setCodexPath($0) }),
                              prompt: Text("найти самому"))
                        .labelsHidden()
                        .frame(maxWidth: 280)
                }
                SettingsPicker("Профиль Codex", selection: Binding(get: { settings.codexHome ?? "" }, set: { app.setCodexHome($0) })) {
                    Text("~/.codex").tag("")
                    ForEach(Array(CodexAppServer.accountHomes().enumerated()), id: \.element) { index, home in
                        Text("Orca, аккаунт \(index + 1)").tag(home)
                    }
                }
                Text("В Orca свой аккаунт Codex: выберите его, иначе лимиты будут от ~/.codex")
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
        }
    }
}

// MARK: - Источники

private struct SourcesSettings: View {
    let app: AppDelegate

    var body: some View {
        @Bindable var model = app.model
        SettingsPage {
            SettingsBlock("Claude Code") {
                LabeledContent("Подключение") {
                    HStack(spacing: 10) {
                        Text(model.hooksInstalled ? "подключено" + Self.ago(model, .claudeCode) : "не подключено")
                        if model.hooksInstalled {
                            Button("Отключить") { app.uninstallHooks() }
                        } else {
                            Button("Подключить…") { app.installHooks() }
                        }
                    }
                }
            }
            SettingsBlock("Claude Cowork") {
                Toggle(isOn: Binding(get: { model.config.sources.cowork }, set: { app.setCoworkEnabled($0) })) {
                    Text("Cowork")
                    Text(coworkStatus(model)).font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                }
            }
            SettingsBlock("ChatGPT") {
                LabeledContent("Подключение", value: Self.codexHooked ? "подключено" + Self.ago(model, .codex) : "не найдены")
                Text("Подключается вместе с Claude Code: маскот видит работу ChatGPT")
                    .font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
            }
            SettingsBlock("Orca") {
                Toggle(isOn: Binding(get: { model.config.sources.orca }, set: { app.setOrcaEnabled($0) })) {
                    Text("Агенты в Orca")
                    Text(orcaStatus(model)).font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted)
                }
            }
            SettingsBlock("Claude в браузере") {
                LabeledContent("Подключение") {
                    HStack(spacing: 10) {
                        Text(model.browserBridgeInstalled ? "подключено" + Self.ago(model, .claudeChat) : "не подключено")
                        if model.browserBridgeInstalled {
                            Button("Показать расширение") { app.revealExtension() }
                            Button("Отключить") { app.uninstallBrowserBridge() }
                        } else {
                            Button("Подключить…") { app.installBrowserBridge() }
                        }
                    }
                }
            }
            SettingsBlock("Figma") {
                Button("Показать плагин-компаньон") { app.revealFigmaPlugin() }
                if model.companionError != nil {
                    Text("Плагин Figma не подключился").foregroundStyle(ConsoleStyle.red)
                }
            }
            SettingsBlock("Органы чувств") {
                Toggle("Агенты", isOn: senseBinding(\.agents))
                Toggle("Тело ноутбука", isOn: senseBinding(\.body))
                Toggle("Ритм и время", isOn: senseBinding(\.rhythm))
                Toggle("Звук", isOn: senseBinding(\.audio))
                Toggle("Эксперименты (угол крышки)", isOn: senseBinding(\.experimental))
            }
        }
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
        case true?: "Подключено" + Self.ago(model, .cowork)
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
