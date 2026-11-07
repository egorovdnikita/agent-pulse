import AppKit
import SwiftUI

/// Настройки на языке Пульта: чёрная поверхность, карточки, слова вместо значков. Всегда тёмные, как и сам Пульт.
enum SettingsStyle {
    static let text = Color.white
    static let muted = ConsoleStyle.caption

    static let sidebarWidth = 170.0
    /// Настройка, которая зависит от строки над ней.
    static let childIndent = 16.0

    static let title = ConsoleStyle.font(22, .semibold)
    static let body = ConsoleStyle.font(13)
    static let bodyMedium = ConsoleStyle.font(13, .medium)
    static let caption = ConsoleStyle.font(11)

    static func spring(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.75)
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
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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

/// Карточка настроек с заголовком над ней; строки разделены тонкой линией.
struct SettingsBlock<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(ConsoleStyle.font(11, .medium))
                    .foregroundStyle(SettingsStyle.muted)
                    .padding(.leading, ConsoleStyle.cardPadding)
            }
            _VariadicView.Tree(SettingsRows()) { content }
        }
        .id(title)
    }
}

private struct SettingsRows: _VariadicView_UnaryViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                child
                    .padding(.horizontal, ConsoleStyle.cardPadding)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                if child.id != children.last?.id {
                    Rectangle().fill(.white.opacity(0.06)).frame(height: 1).padding(.leading, ConsoleStyle.cardPadding)
                }
            }
        }
        .background(ConsoleStyle.card, in: RoundedRectangle(cornerRadius: ConsoleStyle.cardRadius, style: .continuous))
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

/// Переключатель Пульта: зелёный, как шкалы.
struct ConsoleSwitch: View {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(isOn ? ConsoleStyle.green : ConsoleStyle.track)
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
                ConsoleSwitch(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "Включено" : "Выключено")
    }
}

/// Кнопка как в Пульте: капсула без рамки.
struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ConsoleStyle.font(13, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(ConsoleStyle.button, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Раздел в боковой колонке: слово без подложки, как страницы Пульта.
struct SettingsSidebarItem: View {
    let tab: SettingsNavigation.Tab
    let number: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tab.title)
                .font(ConsoleStyle.font(14, isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : ConsoleStyle.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(ConsolePressStyle())
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
                HStack(spacing: 4) {
                    if busy { Text("Занята другим приложением").font(SettingsStyle.caption).foregroundStyle(ConsoleStyle.orange) }
                    ForEach(keys.split(separator: " ").map(String.init), id: \.self) { key in
                        Text(key)
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(height: 20)
                            .background(ConsoleStyle.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            } else {
                Text("Нет").foregroundStyle(SettingsStyle.muted)
            }
        }
    }
}
