import AppKit
import SwiftUI

/// Настройки как у CapaTheNotch (MIT): светлая и тёмная палитра следом за Mac, маленькие радиусы, край почти не виден.
enum SettingsStyle {
    static let window = dynamic(light: 0xFAFAFA, dark: 0x171717)
    static let sidebar = dynamic(light: 0xF4F4F5, dark: 0x1E1E1E)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x252525)
    static let control = dynamic(light: 0xFFFFFF, dark: 0x333333)
    static let selection = dynamic(light: 0xE5E5E5, dark: 0x2C2C2C)
    static let hover = dynamic(light: 0xF4F4F5, dark: 0x2C2C2C)
    static let text = dynamic(light: 0x171717, dark: 0xF5F5F5)
    static let muted = dynamic(light: 0x737373, dark: 0xA3A3A3)
    static let icon = dynamic(light: 0x525252, dark: 0xA3A3A3)
    static let switchOff = dynamic(light: 0xE5E5E5, dark: 0x404040)
    static let destructive = dynamic(light: 0xC5332A, dark: 0xFF625D)
    static let accent = Color(hex: 0x6B97FF)
    static let keycap = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor.white.withAlphaComponent(0x0F / 255) : NSColor.black.withAlphaComponent(0x0A / 255)
    })
    /// Край карточек, кнопок и окна меню: почти не виден.
    static let ring = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor.white.withAlphaComponent(0x0F / 255) : NSColor.black.withAlphaComponent(0x0F / 255)
    })
    static let windowColor = dynamicNS(light: 0xFAFAFA, dark: 0x171717)

    static let sidebarWidth = 200.0
    static let contentInset = 40.0
    /// Настройка, которая зависит от строки над ней.
    static let childIndent = 16.0

    static let title = ConsoleStyle.font(22, .semibold)
    static let body = ConsoleStyle.font(13)
    static let bodyMedium = ConsoleStyle.font(13, .medium)
    static let caption = ConsoleStyle.font(12)

    static func spring(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.75)
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func dynamicNS(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = isDark(appearance) ? dark : light
            return NSColor(
                srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: 1
            )
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: dynamicNS(light: light, dark: dark))
    }
}

private struct SettingsAnchorKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Блок настроек, к которому надо перейти.
    var settingsAnchor: String? {
        get { self[SettingsAnchorKey.self] }
        set { self[SettingsAnchorKey.self] = newValue }
    }
}

/// Страница настроек: столбец карточек. Умеет сразу показать нужный блок.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.settingsAnchor) private var anchor

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { content }
                    .padding(.horizontal, SettingsStyle.contentInset)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .onAppear { reveal(proxy) }
            .onChange(of: anchor) { reveal(proxy) }
        }
        .labeledContentStyle(SettingsRowStyle())
    }

    private func reveal(_ proxy: ScrollViewProxy) {
        guard let anchor else { return }
        DispatchQueue.main.async { proxy.scrollTo(anchor, anchor: .top) }
    }
}

/// Карточка: заливка, край почти не виден, поле 4.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsStyle.card)
                    .shadow(color: SettingsStyle.ring, radius: 0.5, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SettingsStyle.ring, lineWidth: 1))
    }
}

/// Группа: подпись над карточкой, примечание под ней.
struct SettingsBlock<Content: View>: View {
    let title: String?
    let footnote: String?
    let content: Content

    init(_ title: String? = nil, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(ConsoleStyle.font(12, .medium))
                    .foregroundStyle(SettingsStyle.muted)
                    .padding(.leading, 14)
            }
            SettingsCard { _VariadicView.Tree(SettingsRows()) { content } }
            if let footnote {
                Text(footnote)
                    .font(SettingsStyle.caption)
                    .foregroundStyle(SettingsStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }
        }
        .id(title)
    }
}

/// Строки карточки: подсвечиваются под курсором, между ними тонкая линия.
private struct SettingsRows: _VariadicView_UnaryViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                SettingsRow { child }
                if child.id != children.last?.id {
                    Rectangle().fill(SettingsStyle.ring).frame(height: 1).padding(.horizontal, 10)
                }
            }
        }
    }
}

struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content
    // Обычный @State без Xcode недоступен: его макрос лежит только там.
    private let hovering = State(initialValue: false)

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering.wrappedValue ? SettingsStyle.hover : .clear)
            )
            .onHover { hovering.wrappedValue = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering.wrappedValue)
    }
}

/// Название слева, значение справа; ползунок занимает всё свободное место.
struct SettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            // Одна колонка подписей: ползунки и значения начинаются ровно, какой бы длины ни была подпись.
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 120, alignment: .leading)
                .layoutPriority(1)
            configuration.content
                .foregroundStyle(SettingsStyle.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// Выбор из списка: вне системной формы подпись и значение иначе слипаются.
struct SettingsPicker<Value: Hashable, Items: View>: View {
    let title: String
    let selection: Binding<Value>
    @ViewBuilder let items: Items

    init(_ title: String, selection: Binding<Value>, @ViewBuilder content: () -> Items) {
        self.title = title
        self.selection = selection
        items = content()
    }

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: selection) { items }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
        }
    }
}

/// Переключатель. В Пульте зелёный, как шкалы; в настройках и меню — акцент референса.
struct ConsoleSwitch: View {
    let isOn: Bool
    var on = ConsoleStyle.green
    var off = ConsoleStyle.track
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(isOn ? on : off)
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
            .animation(SettingsStyle.spring(reduced: reduceMotion), value: isOn)
    }
}

/// Подпись остаётся столбцом: название и пояснение.
struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsSwitch(configuration: configuration)
    }
}

private struct SettingsSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        // Кнопка, а не жест: иначе до переключателя не добраться с клавиатуры.
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) { configuration.label }
                    .frame(maxWidth: .infinity, alignment: .leading)
                ConsoleSwitch(isOn: configuration.isOn, on: SettingsStyle.accent, off: SettingsStyle.switchOff)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "Включено" : "Выключено")
    }
}

/// Кнопка: 24 pt, радиус 6, край почти не виден.
struct SettingsButtonStyle: ButtonStyle {
    /// Главная кнопка страницы: тёмная на светлом и наоборот.
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsStyle.body)
            .foregroundStyle(prominent ? SettingsStyle.window : SettingsStyle.text)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? SettingsStyle.text : configuration.isPressed ? SettingsStyle.hover : SettingsStyle.control)
                    .shadow(color: SettingsStyle.ring, radius: 1, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(SettingsStyle.ring, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Клавиши: каждая в своей плашке.
struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(keys.indices, id: \.self) { index in
                Text(keys[index])
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsStyle.muted)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(SettingsStyle.keycap, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

/// Раздел в боковой колонке: значок, название, клавиши.
struct SettingsSidebarItem: View {
    let tab: SettingsNavigation.Tab
    let number: Int
    let isSelected: Bool
    let action: () -> Void
    private let hovering = State(initialValue: false)

    init(tab: SettingsNavigation.Tab, number: Int, isSelected: Bool, action: @escaping () -> Void) {
        self.tab = tab
        self.number = number
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(nsImage: SolarIcons.image(tab.icon) ?? NSImage())
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(isSelected ? SettingsStyle.text : SettingsStyle.icon)
                Text(tab.title)
                    .font(isSelected ? SettingsStyle.bodyMedium : SettingsStyle.body)
                    .foregroundStyle(SettingsStyle.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                KeyCaps(keys: ["⌘", String(number)])
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsStyle.selection)
                } else if hovering.wrappedValue {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsStyle.hover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering.wrappedValue = $0 }
        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Строка со списком клавиш: что нажать, видно в одном месте.
struct ShortcutRow: View {
    let title: String
    let keys: String?
    /// Клавишу занял кто-то другой.
    var busy = false

    var body: some View {
        LabeledContent(title) {
            if let keys {
                HStack(spacing: 8) {
                    if busy { Text("Занята другим приложением").font(SettingsStyle.caption).foregroundStyle(SettingsStyle.destructive) }
                    ForEach(keys.split(separator: " ").map(String.init), id: \.self) { group in
                        KeyCaps(keys: group.map(String.init))
                    }
                }
            } else {
                Text("Нет").foregroundStyle(SettingsStyle.muted)
            }
        }
    }
}

/// Модуль: значок, название, что делает, переключатель. Клик открывает его настройки.
struct ModuleCard<Options: View>: View {
    let title: String
    let summary: String
    let icon: String
    let isOn: Bool
    let toggle: (Bool) -> Void
    let expanded: Bool
    let expand: () -> Void
    @ViewBuilder let options: Options
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        SettingsCard {
            HStack(spacing: 12) {
                Button(action: expand) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SettingsStyle.text)
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(nsImage: SolarIcons.image(icon) ?? NSImage())
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .foregroundStyle(SettingsStyle.window)
                            }
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(SettingsStyle.bodyMedium)
                            Text(summary).font(SettingsStyle.caption).foregroundStyle(SettingsStyle.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title): настройки")
                .accessibilityValue(expanded ? "Открыто" : "Закрыто")
                Button { toggle(!isOn) } label: {
                    ConsoleSwitch(isOn: isOn, on: SettingsStyle.accent, off: SettingsStyle.switchOff)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? "Включено" : "Выключено")
            }
            .padding(.horizontal, 10)
            .frame(height: 56)
            if expanded {
                VStack(alignment: .leading, spacing: 0) { options }
                    .padding(.leading, 44)
                    .padding(.bottom, 6)
                    .labeledContentStyle(SettingsRowStyle())
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Строка в раскрытом модуле.
struct ModuleOption<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }
}
